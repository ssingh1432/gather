import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

class AuthService {
  SupabaseClient get _client => SupabaseConfig.client;

  Stream<AuthState> authChanges() => _client.auth.onAuthStateChange;

  Session? currentSession() => _client.auth.currentSession;

  Future<AuthResponse> signUp(String email, String password) {
    return _client.auth.signUp(email: email, password: password);
  }

  Future<AuthResponse> signIn(String email, String password) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<void> resetPassword(String email) =>
      _client.auth.resetPasswordForEmail(email);
}
