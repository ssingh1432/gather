import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

import '../../core/env.dart';
import '../../core/legal_constants.dart';
import '../../core/supabase_client.dart';
import 'analytics_service.dart';
import 'beta_access_service.dart';
import 'device_service.dart';
import 'mfa_service.dart';
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
    String? phoneNumber,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedPhone = (phoneNumber == null || phoneNumber.trim().isEmpty) ? null : phoneNumber.trim();
    if (!await _betaAccess.isEmailAllowed(normalizedEmail)) {
      throw Exception('This email is not on the closed beta allowlist.');
    }
    if (normalizedPhone != null) {
      final existingPhone = await _client.from('users').select('id').eq('phone_number', normalizedPhone).maybeSingle();
      if (existingPhone != null) throw Exception('This phone number is already registered.');
    }
    final existingUsername = await _client.from('users').select('id').eq('username', username).maybeSingle();
    if (existingUsername != null) throw Exception('That username is already taken.');

    final res = await _authSignUpOrFriendlyError(normalizedEmail, password, username, normalizedPhone);
    final uid = res.user?.id;
    if (uid != null) {
      if (_client.auth.currentSession != null) {
        final betaAllowed = await _betaAccess.claimForCurrentUser();
        if (!betaAllowed) {
          await signOut();
          throw Exception('Closed beta access required');
        }
      }
      AnalyticsService.instance.signupStarted();
      AnalyticsService.instance.userSignedUp();
      AnalyticsService.instance.dailyActiveUser();
    }
    return res;
  }

  Future<void> resendSignupEmail(String email) =>
      _client.auth.resend(type: OtpType.signup, email: email.trim().toLowerCase());

  Future<AuthResponse> verifySignupEmailOtp(String email, String code) {
    return _client.auth.verifyOTP(type: OtpType.signup, email: email.trim().toLowerCase(), token: code.trim());
  }

  Future<bool> claimBetaAccessForCurrentUser() => _betaAccess.claimForCurrentUser();

  Future<AuthResponse> signIn(String email, String password) async {
    final normalizedEmail = email.trim().toLowerCase();
    final lockout = await _client.rpc('check_login_lockout', params: {'p_email': normalizedEmail}) as Map;
    if (lockout['locked'] == true) {
      final seconds = (lockout['retry_after_seconds'] as num).toInt();
      final minutes = (seconds / 60).ceil();
      throw Exception('Too many failed attempts. Try again in $minutes minute${minutes == 1 ? '' : 's'}.');
    }

    try {
      final res = await _client.auth.signInWithPassword(email: normalizedEmail, password: password);
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
        unawaited(_client.rpc('record_login_attempt', params: {'p_email': normalizedEmail, 'p_success': true}));
        await DeviceService.instance.registerCurrentDevice();
        await MfaGate.refresh();
      }
      return res;
    } on AuthApiException {
      unawaited(_client.rpc('record_login_attempt', params: {'p_email': normalizedEmail, 'p_success': false}));
      rethrow;
    }
  }

  bool get isNativeGoogleSignInSupported =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  /// Native Google sign-in for Android, iOS and Web.
  ///
  /// Supabase requires both Google's ID token and access token for native
  /// Google sign-in. Fail early with a useful configuration error instead of
  /// sending an incomplete credential to Supabase.
  Future<AuthResponse> signInWithGoogle() async {
    if (AppEnv.googleWebClientId.isEmpty) {
      throw Exception('Google sign-in is not configured: GOOGLE_WEB_CLIENT_ID is missing.');
    }

    // On Flutter Web, google_sign_in needs `clientId` — it silently
    // ignores `serverClientId`, which is what native Android/iOS uses
    // instead. Passing only serverClientId (as before) left web with no
    // client ID at all, crashing with a generic null-check error before
    // the account picker ever showed.
    final googleSignIn = GoogleSignIn(
      clientId: kIsWeb ? AppEnv.googleWebClientId : null,
      serverClientId: kIsWeb ? null : AppEnv.googleWebClientId,
    );
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Google sign-in was cancelled.');
    }

    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;
    if (idToken == null) {
      throw Exception('Google did not return an ID token. Check the OAuth client configuration.');
    }
    if (accessToken == null) {
      throw Exception('Google did not return an access token. Check the OAuth client configuration.');
    }

    final res = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );
    await _afterOAuthSignIn(res);
    return res;
  }

  /// Desktop (macOS/Windows/Linux) Google OAuth. The resulting session is
  /// completed asynchronously by the deep-link listener in main.dart.
  Future<void> signInWithGoogleOAuth() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.eiquoab.gather://login-callback',
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<void> _afterOAuthSignIn(AuthResponse res) async {
    final uid = res.user?.id;
    if (uid == null) return;
    final user = await _client.from('users').select('status').eq('id', uid).maybeSingle();
    if (user?['status'] == 'banned' || user?['status'] == 'suspended') {
      await signOut();
      throw Exception('Account not active');
    }
    AnalyticsService.instance.userLoggedIn();
    AnalyticsService.instance.dailyActiveUser();
    await DeviceService.instance.registerCurrentDevice();
    await MfaGate.refresh();
  }

  String toE164(String normalizedPhone) => '+977$normalizedPhone';

  Future<void> sendPhoneOtp(String normalizedPhone) async {
    await _client.auth.updateUser(UserAttributes(phone: toE164(normalizedPhone)));
  }

  Future<void> verifyPhoneOtp(String normalizedPhone, String code) async {
    await _client.auth.verifyOTP(type: OtpType.phoneChange, phone: toE164(normalizedPhone), token: code.trim());
    await _client.rpc('mark_phone_verified');
  }

  Future<AuthResponse> _authSignUpOrFriendlyError(
    String email,
    String password,
    String username,
    String? phone,
  ) async {
    try {
      return await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'username': username,
          if (phone != null) 'phone_number': phone,
          'privacy_policy_version': kPrivacyPolicyVersion,
        },
      );
    } on AuthApiException catch (e) {
      if (e.code == 'over_email_send_rate_limit' || e.statusCode == '429') {
        throw Exception('Too many signups too quickly — please wait a minute and try again.');
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await PushNotificationService.instance.clearTokenForCurrentUser();
    } catch (_) {}
    await _client.auth.signOut();
    MfaGate.clear();
  }

  Future<void> resetPassword(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    await _client.auth.resetPasswordForEmail(normalizedEmail, redirectTo: 'https://eiquoab.xyz/reset-password');
    unawaited(_client.rpc('log_security_event', params: {
      'p_event_type': 'password_reset_requested',
      'p_metadata': {'email': normalizedEmail},
    }));
  }

  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
    unawaited(_client.rpc('log_security_event', params: {'p_event_type': 'password_reset_completed'}));
  }
}
