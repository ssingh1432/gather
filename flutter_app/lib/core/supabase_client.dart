import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';

class SupabaseConfig {
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: AppEnv.supabaseUrl,
      anonKey: AppEnv.supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  static SupabaseClient? get maybeClient {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static String? get currentUserId => maybeClient?.auth.currentUser?.id;
}
