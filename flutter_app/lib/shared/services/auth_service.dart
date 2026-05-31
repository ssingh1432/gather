import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import 'push_notification_service.dart';

class AuthService {
  SupabaseClient get _client => SupabaseConfig.client;

  Stream<AuthState> authChanges() => _client.auth.onAuthStateChange;
  Session? currentSession() => _client.auth.currentSession;

  Future<AuthResponse> signUp(String email, String password, {required String username}) async {
    final res = await _client.auth.signUp(email: email, password: password, data: {'username': username});
    final uid = res.user?.id;
    if (uid != null) {
      await _client.from('users').upsert({'id': uid, 'email': email, 'username': username, 'status': 'active'});
    }
    return res;
  }

  Future<AuthResponse> signIn(String email, String password) async {
    final res = await _client.auth.signInWithPassword(email: email, password: password);
    final uid = res.user?.id;
    if (uid != null) {
      final user = await _client.from('users').select('status').eq('id', uid).maybeSingle();
      if (user?['status'] == 'banned') {
        await signOut();
        throw Exception('Account banned');
      }
    }
    return res;
  }

  Future<void> signOut() async {
    await PushNotificationService.instance.clearTokenForCurrentUser();
    await _client.auth.signOut();
  }
  Future<void> resetPassword(String email) => _client.auth.resetPasswordForEmail(email);
}
