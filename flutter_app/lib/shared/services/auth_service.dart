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

  Future<AuthResponse> signUp(
    String email,
    String password, {
    required String username,
    required String phoneNumber,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedPhone = phoneNumber.trim();
    if (!await _betaAccess.isEmailAllowed(normalizedEmail)) {
      throw Exception('This email is not on the closed beta allowlist.');
    }
    final res = await _client.auth.signUp(
      email: normalizedEmail,
      password: password,
      data: {'username': username, 'phone_number': normalizedPhone},
    );
    final uid = res.user?.id;
    if (uid != null) {
      try {
        await _client.from('users').upsert({
          'id': uid,
          'email': normalizedEmail,
          'username': username,
          'phone_number': normalizedPhone,
          'status': 'active',
        });
      } on PostgrestException catch (e) {
        if (e.code == '23505') {
          // Unique violation. The users_phone_number_key index is the only
          // one an unauthenticated new signup could hit here.
          await signOut();
          throw Exception('This phone number is already registered.');
        }
        rethrow;
      }
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

  /// Converts a normalized 10-digit Nepali number into E.164 for Supabase/Twilio.
  String toE164(String normalizedPhone) => '+977$normalizedPhone';

  /// Sends (or resends) an SMS OTP to verify the current user's phone number.
  /// Requires the Phone provider (Twilio) to be configured in Supabase Auth.
  Future<void> sendPhoneOtp(String normalizedPhone) async {
    await _client.auth.updateUser(UserAttributes(phone: toE164(normalizedPhone)));
  }

  /// Confirms the SMS code the user typed in and marks the phone verified.
  Future<void> verifyPhoneOtp(String normalizedPhone, String code) async {
    await _client.auth.verifyOTP(
      type: OtpType.phoneChange,
      phone: toE164(normalizedPhone),
      token: code.trim(),
    );
    final uid = _client.auth.currentUser?.id;
    if (uid != null) {
      await _client.from('users').update({'phone_verified': true}).eq('id', uid);
    }
  }

  Future<void> signOut() async {
    // Best-effort: clearing the FCM token must never block the actual
    // sign-out. Previously an exception here (e.g. a flaky network call)
    // propagated all the way up and left the person stuck on the "Sign
    // out" button with no error and no signed-out state.
    try {
      await PushNotificationService.instance.clearTokenForCurrentUser();
    } catch (_) {
      // Ignored — a stale token is harmless; failing to sign out is not.
    }
    await _client.auth.signOut();
  }
  Future<void> resetPassword(String email) => _client.auth.resetPasswordForEmail(email);
}
