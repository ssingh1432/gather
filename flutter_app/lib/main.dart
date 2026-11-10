import 'dart:async';
import 'dart:ui';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'core/env.dart';
import 'core/router.dart';
import 'core/supabase_client.dart';
import 'core/theme/app_theme.dart';
import 'shared/services/analytics_service.dart';
import 'shared/services/beta_error_logging_service.dart';
import 'shared/services/device_service.dart';
import 'shared/services/mfa_service.dart';
import 'shared/services/push_notification_service.dart';
import 'shared/services/remember_me_service.dart';
import 'shared/services/remote_config_service.dart';
import 'shared/services/ads_bootstrap.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      BetaErrorLoggingService.instance.record(details.exception, details.stack, context: 'FlutterError.onError');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      BetaErrorLoggingService.instance.record(error, stack, context: 'PlatformDispatcher.onError');
      return true;
    };

    // Load environment variables
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      try {
        await dotenv.load(fileName: '.env.example');
      } catch (_) {}
    }

    // Initialize Supabase and related services. Each step is isolated so a
    // failure in one (e.g. a web-specific auth/session bug) can never
    // prevent runApp() from being called — that was leaving the whole app
    // as a permanently blank white screen with the real error only visible
    // in the console.
    if (AppEnv.supabaseUrl.isNotEmpty && AppEnv.supabaseAnonKey.isNotEmpty) {
      try {
        await SupabaseConfig.initialize();
        await RememberMeService.instance.enforceOnStartup();
      } catch (error, stack) {
        BetaErrorLoggingService.instance.record(error, stack, context: 'SupabaseConfig.initialize');
      }
      try {
        // Restored session at AAL1 with 2FA enabled must still pass the challenge.
        await MfaGate.refresh();
      } catch (error, stack) {
        BetaErrorLoggingService.instance.record(error, stack, context: 'MfaGate.refresh');
      }
      try {
        await PushNotificationService.instance.initialize();
      } catch (error, stack) {
        BetaErrorLoggingService.instance.record(error, stack, context: 'PushNotificationService.initialize');
      }
      try {
        AnalyticsService.instance.dailyActiveUser();
      } catch (error, stack) {
        BetaErrorLoggingService.instance.record(error, stack, context: 'AnalyticsService.dailyActiveUser');
      }
      try {
        await RemoteConfigService.instance.load();
        await maybeInitAds();
      } catch (error, stack) {
        BetaErrorLoggingService.instance.record(error, stack, context: 'RemoteConfigService/AdsService.initialize');
      }
      // Desktop-only: Android/iOS/Web use google_sign_in's native picker
      // (see AuthService.signInWithGoogle) and never leave the app, so they
      // don't need this. macOS/Windows/Linux have no native Google SDK, so
      // AuthService.signInWithGoogleOAuth() opens the system browser and the
      // OAuth result comes back via the io.eiquoab.gather:// deep link,
      // which we catch here and hand to Supabase to finish the sign-in.
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux)) {
        try {
          final appLinks = AppLinks();
          appLinks.uriLinkStream.listen((uri) async {
            if (uri.scheme == 'io.eiquoab.gather') {
              try {
                await SupabaseConfig.client.auth.getSessionFromUrl(uri);
                await DeviceService.instance.registerCurrentDevice();
                await MfaGate.refresh();
              } catch (error, stack) {
                BetaErrorLoggingService.instance.record(error, stack, context: 'Google OAuth deep link');
              }
            }
          });
        } catch (error, stack) {
          BetaErrorLoggingService.instance.record(error, stack, context: 'AppLinks listener setup');
        }
      }
    } else {
      debugPrint("⚠️ Supabase URL or Anon Key is missing in .env");
    }

    runApp(const ProviderScope(child: GatherApp()));
  }, (error, stack) {
    BetaErrorLoggingService.instance.record(error, stack, context: 'runZonedGuarded');
  });
}

class GatherApp extends StatefulWidget {
  const GatherApp({super.key});

  @override
  State<GatherApp> createState() => _GatherAppState();
}

class _GatherAppState extends State<GatherApp> {
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  @override
  void initState() {
    super.initState();
    _listenForSharedContent();
  }

  void _listenForSharedContent() {
    // Someone tapped "Share" from Facebook/TikTok/a news site/etc into
    // Gather (see the SEND intent-filter in AndroidManifest.xml) — open
    // compose pre-filled with whatever text/link they shared, rather than
    // trying to import the other platform's content directly.
    void handle(List<SharedMediaFile> files) {
      if (files.isEmpty) return;
      final shared = files.first.path;
      if (shared.isEmpty) return;
      appRouter.push('/create-post?sharedText=${Uri.encodeComponent(shared)}');
    }

    ReceiveSharingIntent.instance.getInitialMedia().then(handle).catchError((_) {});
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(handle, onError: (_) {});
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Gather',
      routerConfig: appRouter,
      theme: AppTheme.light,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
    );
  }
}