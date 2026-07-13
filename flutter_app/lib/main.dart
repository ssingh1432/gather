import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/env.dart';
import 'core/router.dart';
import 'core/supabase_client.dart';
import 'core/theme/app_theme.dart';
import 'shared/services/analytics_service.dart';
import 'shared/services/beta_error_logging_service.dart';
import 'shared/services/push_notification_service.dart';
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
      } catch (error, stack) {
        BetaErrorLoggingService.instance.record(error, stack, context: 'SupabaseConfig.initialize');
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
    } else {
      debugPrint("⚠️ Supabase URL or Anon Key is missing in .env");
    }

    runApp(const ProviderScope(child: GatherApp()));
  }, (error, stack) {
    BetaErrorLoggingService.instance.record(error, stack, context: 'runZonedGuarded');
  });
}

class GatherApp extends StatelessWidget {
  const GatherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Gather',
      routerConfig: appRouter,
      theme: AppTheme.light,
    );
  }
}