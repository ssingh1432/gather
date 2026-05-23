import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/env.dart';
import 'core/router.dart';
import 'core/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    try {
      await dotenv.load(fileName: '.env.example');
    } catch (_) {
      // Allow startup without a local .env (e.g. CI/tests).
    }
  }
  if (AppEnv.supabaseUrl.isNotEmpty && AppEnv.supabaseAnonKey.isNotEmpty) {
    await SupabaseConfig.initialize();
  }
  runApp(const ProviderScope(child: GatherApp()));
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
