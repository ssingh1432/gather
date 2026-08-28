import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppEnv {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  static String get appVersion => dotenv.env['APP_VERSION'] ?? '0.1.0+1';

  /// The "Web application" OAuth 2.0 client ID from Google Cloud Console.
  /// Passed as `serverClientId` to google_sign_in on every platform (even
  /// native Android/iOS) so the ID token it returns has this as its
  /// audience — that's what lets Supabase's Google provider (configured
  /// with the same client ID + secret) verify it.
  static String get googleWebClientId => dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';
}
