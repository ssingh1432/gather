import '../../core/supabase_client.dart';
import 'remember_me_service_io.dart' if (dart.library.html) 'remember_me_service_web.dart' as impl;

/// "Remember me" on login. Supabase always persists the session locally so
/// the person doesn't have to re-verify email/phone on this device again —
/// that part is automatic and not affected by this flag. What this flag
/// controls is whether that persisted session survives a full app restart:
/// unchecked means we sign out on the next cold start, so a shared/public
/// device doesn't stay logged in indefinitely.
class RememberMeService {
  RememberMeService._();
  static final instance = RememberMeService._();

  bool get isRemembered => impl.readRememberMe();

  void setRemembered(bool remember) => impl.writeRememberMe(remember);

  /// Call once at startup, after Supabase has restored any persisted
  /// session, and before the app is shown.
  Future<void> enforceOnStartup() async {
    if (!isRemembered) {
      final client = SupabaseConfig.maybeClient;
      if (client?.auth.currentSession != null) {
        await client!.auth.signOut();
      }
      // Reset the flag so this device defaults back to "remembered" the
      // next time someone signs in, rather than being permanently opted out.
      setRemembered(true);
    }
  }
}
