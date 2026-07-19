/// Centralized password strength rules so every screen that sets or
/// changes a password (signup, reset) enforces the same policy.
///
/// Policy: at least 8 characters, with a mix of upper case, lower case,
/// and a digit. This is a baseline aligned with Supabase Auth's own
/// minimum recommendations without being so strict it frustrates users
/// on a Nepal-first, largely mobile-typing audience.
class PasswordValidator {
  PasswordValidator._();

  static const int minLength = 8;

  /// Returns a user-facing error message, or null if the password is
  /// strong enough.
  static String? validate(String password) {
    if (password.length < minLength) {
      return 'Password must be at least $minLength characters.';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Password must include at least one uppercase letter.';
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Password must include at least one lowercase letter.';
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Password must include at least one number.';
    }
    return null;
  }

  static bool isStrong(String password) => validate(password) == null;
}
