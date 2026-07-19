import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'secure_local_storage.dart';

/// Thin wrapper around the Supabase singleton so the rest of the app can
/// call `SupabaseConfig.client` / `.maybeClient` / `.currentUserId` without
/// worrying about initialization order.
class SupabaseConfig {
  SupabaseConfig._();

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: AppEnv.supabaseUrl,
      anonKey: AppEnv.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        localStorage: SecureLocalStorage(),
      ),
    );
  }

  /// Throws if Supabase hasn't been initialized yet. Use in code paths that
  /// only run after `main()` has completed initialization.
  static SupabaseClient get client => Supabase.instance.client;

  /// Null-safe accessor for code paths (e.g. widget build methods) that may
  /// run before/without Supabase being initialized (e.g. missing .env).
  static SupabaseClient? get maybeClient {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static String? get currentUserId => maybeClient?.auth.currentUser?.id;
}
