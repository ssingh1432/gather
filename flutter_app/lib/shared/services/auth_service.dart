import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import 'analytics_service.dart';
import 'beta_access_service.dart';
import 'push_notification_service.dart';

class AuthService {
  SupabaseClient get _client => SupabaseConfig.client;
  final BetaAccessService _betaAccess = BetaAccessService();

  Stream<AuthState> authChanges() => _client.auth.onAuthStateChange;
  Session? currentSession() => _client.auth.currentSession;

  Future<AuthResponse> signUp(String email, String password, {required String username}) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (!await _betaAccess.isEmailAllowed(normalizedEmail)) {
      throw Exception('This email is not on the closed beta allowlist.');
    }
    final res = await _client.auth.signUp(email: normalizedEmail, password: password, data: {'username': username});
    final uid = res.user?.id;
    if (uid != null) {
      await _client.from('users').upsert({'id': uid, 'email': normalizedEmail, 'username': username, 'status': 'active'});
      final betaAllowed = await _betaAccess.claimForCurrentUser();
      if (!betaAllowed) {
        await signOut();
        throw Exception('Closed beta access required');
      }
      AnalyticsService.instance.signupStarted();
      AnalyticsService.instance.userSignedUp();
      AnalyticsService.instance.dailyActiveUser();
    }
    return res;
  }

  Future<AuthResponse> signIn(String email, String password) async {
    final res = await _client.auth.signInWithPassword(email: email.trim().toLowerCase(), password: password);
    final uid = res.user?.id;
    if (uid != null) {
      final user = await _client.from('users').select('status').eq('id', uid).maybeSingle();
      if (user?['status'] == 'banned' || user?['status'] == 'suspended') {
        await signOut();
        throw Exception('Account not active');
      }
      final betaAllowed = await _betaAccess.claimForCurrentUser();
      if (!betaAllowed) {
        await signOut();
        throw Exception('This account is not on the closed beta allowlist.');
      }
      AnalyticsService.instance.userLoggedIn();
      AnalyticsService.instance.dailyActiveUser();
    }
    return res;
  }

  Future<void> signOut() async {
    await PushNotificationService.instance.clearTokenForCurrentUser();
    await _client.auth.signOut();
  }
  Future<void> resetPassword(String email) => _client.auth.resetPasswordForEmail(email);
}
