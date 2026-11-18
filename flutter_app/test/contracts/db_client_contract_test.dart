// Cross-layer contract tests: the Flutter client mirrors a few rules that the
// database enforces. If either side changes without the other, these fail in
// CI instead of surfacing as a confusing runtime error in production.
//
// `flutter test` runs with the working directory set to flutter_app/, so the
// migrations are at ../database/migrations.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/core/legal_constants.dart';
import 'package:gather_app/shared/utils/profile_themes.dart';
import 'package:gather_app/shared/utils/username_validator.dart';

String _migration(String name) {
  final f = File('../database/migrations/$name');
  if (!f.existsSync()) {
    fail('Missing ${f.path}. Run tests from flutter_app/ inside the full repo checkout.');
  }
  return f.readAsStringSync();
}

Set<String> _quotedList(String source) =>
    RegExp(r"'([a-z0-9_]+)'").allMatches(source).map((m) => m.group(1)!).toSet();

void main() {
  test('profile theme keys match users_profile_theme_check (migration 123)', () {
    final sql = _migration('123_phase12_profile_identity.sql');
    final m = RegExp(r'profile_theme in \(([^)]*)\)').firstMatch(sql);
    expect(m, isNotNull, reason: 'users_profile_theme_check not found');
    expect(_quotedList(m!.group(1)!), ProfileThemes.accents.keys.toSet());
  });

  test('reserved usernames match validate_username() (migration 123)', () {
    final sql = _migration('123_phase12_profile_identity.sql');
    final m = RegExp(r'reserved text\[\] := array\[(.*?)\];', dotAll: true).firstMatch(sql);
    expect(m, isNotNull, reason: 'reserved array not found');
    final serverReserved = _quotedList(m!.group(1)!);
    for (final name in serverReserved) {
      expect(UsernameValidator.validate(name), isNotNull,
          reason: '$name is reserved on the server but accepted by the client');
    }
  });

  test('privacy policy version matches handle_new_user fallback (migration 020)', () {
    final sql = _migration('020_auto_record_signup_consent.sql');
    expect(sql, contains("'$kPrivacyPolicyVersion'"),
        reason: 'Bumped kPrivacyPolicyVersion without updating the trigger fallback '
            '(see legal_constants.dart doc comment).');
  });

  test('legal URLs are HTTPS and the version is an ISO date', () {
    expect(Uri.parse(kPrivacyPolicyUrl).scheme, 'https');
    expect(Uri.parse(kTermsOfServiceUrl).scheme, 'https');
    expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(kPrivacyPolicyVersion), isTrue);
  });

  test('report_category enum has the 14 Phase 6 categories (migration 021)', () {
    final sql = _migration('021_phase6_moderation_enums.sql');
    final m = RegExp(r'create type public\.report_category as enum \((.*?)\);', dotAll: true)
        .firstMatch(sql);
    expect(m, isNotNull);
    final serverValues = _quotedList(m!.group(1)!);
    expect(serverValues.length, 14, reason: 'Phase 6 specifies 14 report categories');
    expect(serverValues, containsAll(['spam', 'child_abuse', 'terrorism', 'self_harm', 'other']));
  });
}
