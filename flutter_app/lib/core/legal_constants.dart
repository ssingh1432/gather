/// Single source of truth for the current privacy policy / terms of
/// service version. Bump this whenever the policy text changes.
///
/// Used by:
/// - `signup_screen.dart` — stamped into signUp() metadata so the
///   `handle_new_user` DB trigger can record consent at account-creation
///   time (see migration 020_auto_record_signup_consent.sql), which works
///   even when email confirmation is required and there's no client
///   session yet.
/// - `data_privacy_screen.dart` — compared against the person's latest
///   recorded consent to decide whether to show "Accept".
///
/// If you bump this, also update the fallback version hardcoded in the
/// `handle_new_user` trigger (in case an old client build without this
/// value in its metadata is still in the wild).
const String kPrivacyPolicyVersion = '2026-07-19';
const String kPrivacyPolicyUrl = 'https://eiquoab.xyz/privacy-policy/';
const String kTermsOfServiceUrl = 'https://eiquoab.xyz/terms/';
