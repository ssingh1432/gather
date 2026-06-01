import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/env.dart';
import 'core/router.dart';
import 'core/supabase_client.dart';
import 'shared/services/analytics_service.dart';
import 'shared/services/beta_error_logging_service.dart';
import 'shared/services/push_notification_service.dart';

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

    // Initialize Supabase
    if (AppEnv.supabaseUrl.isNotEmpty && AppEnv.supabaseAnonKey.isNotEmpty) {
      await SupabaseConfig.initialize();
      await PushNotificationService.instance.initialize();
      AnalyticsService.instance.dailyActiveUser();
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
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    );
  }
}