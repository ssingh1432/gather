import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/features/legal/copyright_repository.dart';
import 'package:gather_app/features/legal/my_copyright_screen.dart' show copyrightStatusLabel;

String? _notice({
  String name = 'Asha Gurung',
  String email = 'asha@example.com',
  String work = 'My original photograph of Pashupatinath',
  String signature = 'Asha Gurung',
  String? original,
  String? infringing = 'https://gather.example/p/1',
  String? post,
  bool goodFaith = true,
  bool accuracy = true,
}) =>
    CopyrightFormValidator.validateNotice(
      name: name,
      email: email,
      workDescription: work,
      signature: signature,
      originalWorkUrl: original,
      infringingUrl: infringing,
      targetPostId: post,
      goodFaith: goodFaith,
      accuracy: accuracy,
    );

void main() {
  group('CopyrightFormValidator.validateNotice (mirrors migration 130 constraints)', () {
    test('accepts a complete notice', () => expect(_notice(), isNull));

    test('accepts a post target without an infringing URL', () {
      expect(_notice(infringing: null, post: 'post-uuid'), isNull);
    });

    test('rejects missing or too-short name, signature and description', () {
      expect(_notice(name: 'A'), contains('legal name'));
      expect(_notice(name: '  '), contains('legal name'));
      expect(_notice(work: 'short'), contains('at least 10'));
      expect(_notice(signature: ''), contains('signature'));
    });

    test('enforces DB length limits (200 name, 2000 description, 254 email)', () {
      expect(_notice(name: 'a' * 201), isNotNull);
      expect(_notice(name: 'a' * 200), isNull);
      expect(_notice(work: 'a' * 2001), contains('too long'));
      expect(_notice(work: 'a' * 2000), isNull);
      expect(_notice(email: '${'a' * 250}@b.co'), contains('valid'));
    });

    test('validates the email like the SQL regex', () {
      for (final bad in ['', 'plain', 'a@b', '@b.com', 'a b@c.com']) {
        expect(_notice(email: bad), contains('valid'), reason: bad);
      }
      expect(_notice(email: 'a@b.co'), isNull);
    });

    test('needs a target and only accepts http(s) links', () {
      expect(_notice(infringing: '', post: null), contains('link to the content'));
      expect(_notice(infringing: 'javascript:alert(1)'), contains('http'));
      expect(_notice(infringing: 'ftp://x.com/a'), contains('http'));
      expect(_notice(original: 'not a url'), contains('original work'));
      expect(_notice(original: 'https://example.com/work'), isNull);
    });

    test('both statements are mandatory', () {
      expect(_notice(goodFaith: false), contains('good-faith'));
      expect(_notice(accuracy: false), contains('accurate'));
    });
  });

  group('validateCounterNotice', () {
    test('accepts valid', () {
      expect(CopyrightFormValidator.validateCounterNotice(statement: 'This is my own photo.', signature: 'Asha', consent: true), isNull);
    });
    test('rejects short statement, no consent, no signature', () {
      expect(CopyrightFormValidator.validateCounterNotice(statement: 'short', signature: 'Asha', consent: true), contains('at least 10'));
      expect(CopyrightFormValidator.validateCounterNotice(statement: 'This is my own photo.', signature: 'Asha', consent: false), contains('jurisdiction'));
      expect(CopyrightFormValidator.validateCounterNotice(statement: 'This is my own photo.', signature: '', consent: true), contains('signature'));
    });
  });

  group('friendlyError', () {
    test('maps RPC exception codes', () {
      expect(CopyrightFormValidator.friendlyError('PostgrestException: rate_limited'), contains('too many'));
      expect(CopyrightFormValidator.friendlyError('post_not_found'), contains('no longer exists'));
      expect(CopyrightFormValidator.friendlyError('cannot_counter'), contains('counter-notice'));
      expect(CopyrightFormValidator.friendlyError('forbidden'), contains('permission'));
      expect(CopyrightFormValidator.friendlyError('already_resolved'), contains('already'));
    });
    test('unknown errors do not leak internals', () {
      final msg = CopyrightFormValidator.friendlyError('PostgrestException(message: relation x, code: 42P01)');
      expect(msg, isNot(contains('42P01')));
    });
  });

  test('every database status has a readable label', () {
    const statuses = ['submitted', 'under_review', 'content_removed', 'rejected', 'counter_notice_received', 'restored', 'withdrawn'];
    for (final s in statuses) {
      expect(copyrightStatusLabel(s), isNot(contains('_')), reason: s);
    }
  });
}
