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

    // Friendly duplicate checks *before* creating the auth user. These run
    // as anon (public.users has an open SELECT policy), so they work even
    // though the account doesn't exist/have a session yet.
    if (normalizedPhone != null) {
      final existingPhone = await _client.from('users').select('id').eq('phone_number', normalizedPhone).maybeSingle();
      if (existingPhone != null) {
        throw Exception('This phone number is already registered.');
      }
    }
    final existingUsername = await _client.from('users').select('id').eq('username', username).maybeSingle();
    if (existingUsername != null) {
      throw Exception('That username is already taken.');
    }

    final res = await _authSignUpOrFriendlyError(normalizedEmail, password, username, normalizedPhone);
    final uid = res.user?.id;
    if (uid != null) {
      // The public.users row is now provisioned server-side by a trigger on
      // auth.users (see migration 015) — it no longer depends on the client
      // having a session, which matters because when email confirmation is
      // required there is no session yet at this point.
      //
      // Only claim beta access if we actually have a session (i.e. email
      // confirmation is off, or this account was already confirmed). If
      // confirmation is pending, there's nothing to claim yet — the user
      // will land here again with a session once they confirm.
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

  /// Re-sends the signup confirmation email (rate-limited server-side).
  /// With the "Confirm signup" template set to show `{{ .Token }}`, this
  /// resends a fresh 6-digit code rather than a link.
  Future<void> resendSignupEmail(String email) =>
      _client.auth.resend(type: OtpType.signup, email: email.trim().toLowerCase());

  /// Confirms the signup email code and establishes a session, entirely
  /// in-app — no link to click, no leaving the app. Pairs with
  /// `VerifyEmailScreen`. Requires the Supabase "Confirm signup" email
  /// template to use `{{ .Token }}` (see project docs).
  Future<AuthResponse> verifySignupEmailOtp(String email, String code) {
    return _client.auth.verifyOTP(
      type: OtpType.signup,
      email: email.trim().toLowerCase(),
      token: code.trim(),
    );
  }

  /// Claims closed-beta access for whoever is currently signed in. Called
  /// right after signUp() when a session exists immediately, and again
  /// after `verifySignupEmailOtp` succeeds (that's the first moment a
  /// session exists when email confirmation was required).
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
      }
      return res;
    } on AuthApiException {
      unawaited(_client.rpc('record_login_attempt', params: {'p_email': normalizedEmail, 'p_success': false}));
      rethrow;
    }
  }

  /// Whether the native (in-app, no browser) Google Sign-In flow is
  /// available on this platform. Android, iOS, and Web all have first-class
  /// native/embedded Google account-picker support via the google_sign_in
  /// plugin. Desktop (macOS/Windows/Linux) has no such SDK and falls back
  /// to [signInWithGoogleOAuth] instead.
  bool get isNativeGoogleSignInSupported =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  /// Signs in (or signs up, the first time) with Google using the
  /// platform's native account picker — the user never leaves the app,
  /// matching the rest of our auth flows. Android, iOS, and Web only; see
  /// [signInWithGoogleOAuth] for desktop.
  ///
  /// Note: unlike email/password signup, this is NOT gated by the closed
  /// beta allowlist — any Google account can create an account this way
  /// (product decision, 2026-08-27).
  Future<AuthResponse> signInWithGoogle() async {
    final googleSignIn = GoogleSignIn(serverClientId: AppEnv.googleWebClientId);
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Google sign-in was cancelled.');
    }
    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) {
      throw Exception('Google did not return an ID token. Check the OAuth client configuration.');
    }

    final res = await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: googleAuth.accessToken,
    );
    await _afterOAuthSignIn(res);
    return res;
  }

  /// Desktop (macOS/Windows/Linux) Google sign-in: opens the system browser
  /// for the OAuth consent screen, then returns to the app via the
  /// `io.eiquoab.gather://login-callback` deep link (caught in main.dart,
  /// which finishes the session with `getSessionFromUrl`). The resulting
  /// session arrives asynchronously — listen to `authChanges()` rather than
  /// awaiting a return value here.
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
    // phone_verified is now only settable server-side (see guard_user_update
    // trigger) — this RPC checks auth.users.phone_confirmed_at itself
    // rather than trusting the client.
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
          // Read by the handle_new_user DB trigger to stamp consent at
          // account-creation time — works even when there's no session
          // yet (confirmation-required path). See legal_constants.dart.
          'privacy_policy_version': kPrivacyPolicyVersion,
        },
      );
    } on AuthApiException catch (e) {
      if (e.code == 'over_email_send_rate_limit' || e.statusCode == '429') {
        throw Exception(
          'Too many signups too quickly — please wait a minute and try again.',
        );
      }
      rethrow;
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
  Future<void> resetPassword(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    await _client.auth.resetPasswordForEmail(
      normalizedEmail,
      redirectTo: 'https://eiquoab.xyz/reset-password',
    );
    unawaited(_client.rpc('log_security_event', params: {
      'p_event_type': 'password_reset_requested',
      'p_metadata': {'email': normalizedEmail},
    }));
  }

  /// Sets a new password for the currently-active recovery session (i.e.
  /// after the user has opened the password-reset email link).
  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
    unawaited(_client.rpc('log_security_event', params: {'p_event_type': 'password_reset_completed'}));
  }
}
