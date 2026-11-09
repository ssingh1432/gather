import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import 'device_service.dart';

/// Result of starting TOTP enrollment.
class TotpEnrollment {
  const TotpEnrollment({required this.factorId, required this.secret, required this.uri});
  final String factorId;
  final String secret;
  final String uri;
}

/// Wraps Supabase Auth MFA (TOTP). Requires MFA/TOTP to be enabled in the
/// Supabase dashboard (Auth > Sign In / Providers > Multi-Factor).
class MfaService {
  MfaService._();
  static final MfaService instance = MfaService._();

  GoTrueMFAApi get _mfa => SupabaseConfig.client.auth.mfa;

  Future<Factor?> verifiedTotpFactor() async {
    final res = await _mfa.listFactors();
    return res.totp.isEmpty ? null : res.totp.first;
  }

  Future<bool> isEnabled() async => (await verifiedTotpFactor()) != null;

  /// Starts enrollment. Abandoned (unverified) factors are removed first so
  /// repeated attempts do not pile up.
  Future<TotpEnrollment> startEnrollment() async {
    final all = await _mfa.listFactors();
    for (final f in all.all) {
      if (f.status == FactorStatus.unverified) {
        try {
          await _mfa.unenroll(f.id);
        } catch (_) {}
      }
    }
    final res = await _mfa.enroll(
      factorType: FactorType.totp,
      friendlyName: 'Gather ${DateTime.now().millisecondsSinceEpoch}',
    );
    final totp = res.totp;
    if (totp == null) throw Exception('Could not start two-factor setup.');
    return TotpEnrollment(factorId: res.id, secret: totp.secret, uri: totp.uri);
  }

  /// Verifies the 6-digit code. For enrollment this activates the factor;
  /// for login it upgrades the session to AAL2.
  Future<void> verify(String factorId, String code) async {
    await _mfa.challengeAndVerify(factorId: factorId, code: code.trim());
  }

  Future<void> disable(String factorId) => _mfa.unenroll(factorId);
}

/// Decides whether the signed-in session still owes a 2FA challenge.
///
/// A password (or Google) sign-in yields an AAL1 session. If the user has a
/// verified factor and this device is not trusted, the router keeps them on
/// /mfa-challenge until the session reaches AAL2.
///
/// Client-side gate: server-side, sensitive RPCs additionally call
/// require_aal2_if_enrolled().
class MfaGate {
  MfaGate._();

  static final ValueNotifier<bool> pending = ValueNotifier<bool>(false);

  static Future<void> refresh() async {
    final client = SupabaseConfig.maybeClient;
    if (client == null || client.auth.currentSession == null) {
      pending.value = false;
      return;
    }
    try {
      final aal = client.auth.mfa.getAuthenticatorAssuranceLevel();
      final needsStepUp = aal.nextLevel == AuthenticatorAssuranceLevels.aal2 &&
          aal.currentLevel != AuthenticatorAssuranceLevels.aal2;
      if (!needsStepUp) {
        pending.value = false;
        return;
      }
      pending.value = !(await DeviceService.instance.isCurrentDeviceTrusted());
    } catch (_) {
      // Leave the previous value; do not lock users out on a transient error.
    }
  }

  static void clear() => pending.value = false;
}
