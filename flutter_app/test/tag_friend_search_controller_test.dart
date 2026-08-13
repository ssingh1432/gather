import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/features/posts/tag_friend_search_controller.dart';

void main() {
  group('TagFriendSearchController', () {
    test('a slow early response cannot overwrite a faster later one', () async {
      // Simulates: user types "a" (slow network, 100ms), then "alice"
      // (fast, 10ms) before "a" has resolved. Requirement #10 / the
      // original bug report's exact scenario.
      final controller = TagFriendSearchController();

      final aFuture = controller.search('a', (q) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return [
          {'id': '1', 'username': 'aaron'},
          {'id': '2', 'username': 'amanda'},
        ];
      });

      // "alice" is issued while "a" is still in flight.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final aliceFuture = controller.search('alice', (q) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return [
          {'id': '3', 'username': 'alice'},
        ];
      });

      final aResult = await aFuture;
      final aliceResult = await aliceFuture;

      // The stale "a" response must be discarded (null), not applied.
      expect(aResult, isNull);
      expect(aliceResult, isNotNull);
      expect(aliceResult!.single['username'], 'alice');
    });

    test('responses that resolve in issue order both come through normally', () async {
      final controller = TagFriendSearchController();

      final first = await controller.search('a', (q) async => [
            {'id': '1', 'username': 'aaron'}
          ]);
      final second = await controller.search('al', (q) async => [
            {'id': '2', 'username': 'alice'}
          ]);

      expect(first, isNotNull); // was current when it resolved — no newer search existed yet
      expect(second, isNotNull);
      expect(second!.single['username'], 'alice');
    });

    test('a stale request that fails does not surface as an error once a newer one has already succeeded', () async {
      // The subtle half of the bug: it's not just successful stale
      // responses that must be discarded — a stale request that *errors*
      // after a newer one already resolved successfully must not clobber
      // those correct results with a spurious error state.
      final controller = TagFriendSearchController();

      final slowFailing = controller.search('a', (q) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        throw Exception('network blip');
      });

      await Future<void>.delayed(const Duration(milliseconds: 5));
      final fastSucceeding = controller.search('alice', (q) async => [
            {'id': '3', 'username': 'alice'}
          ]);

      final aliceResult = await fastSucceeding;
      expect(aliceResult, isNotNull);

      // The stale failure must resolve to null (discarded), not throw.
      await expectLater(slowFailing, completion(isNull));
    });

    test('a genuinely current request that fails still throws, so the UI can show an error', () async {
      final controller = TagFriendSearchController();

      await expectLater(
        controller.search('a', (q) async => throw Exception('boom')),
        throwsA(isA<Exception>()),
      );
    });
  });
}
