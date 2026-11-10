/// Client-side mirror of public.validate_username() (migration 123).
/// The server is the source of truth; this only gives instant feedback.
class UsernameValidator {
  UsernameValidator._();

  static const _reserved = {
    'admin', 'administrator', 'moderator', 'mod', 'support', 'help', 'gather', 'official',
    'staff', 'team', 'security', 'system', 'root', 'null', 'undefined', 'api', 'www',
    'about', 'privacy', 'terms', 'settings', 'login', 'signup', 'register',
  };

  /// Returns an error message, or null when [input] is acceptable.
  static String? validate(String input) {
    final v = input.trim();
    if (!RegExp(r'^[a-z0-9_.]{3,30}$').hasMatch(v)) {
      return 'Usernames are 3-30 characters: lowercase letters, numbers, underscore or dot.';
    }
    if (v.startsWith('.') || v.startsWith('_') || v.endsWith('.') || v.endsWith('_')) {
      return 'Usernames cannot start or end with a dot or underscore.';
    }
    if (v.contains('..')) return 'Usernames cannot contain two dots in a row.';
    if (!RegExp(r'[a-z]').hasMatch(v)) return 'Usernames must contain at least one letter.';
    if (_reserved.contains(v)) return 'That username is reserved.';
    return null;
  }
}
