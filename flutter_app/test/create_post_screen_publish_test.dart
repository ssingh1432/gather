// Widget-level tests for CreatePostScreen's _publish() state machine —
// requirement #17, the part that was previously untestable because the
// composer called PostRepository()/SupabaseConfig directly with no
// injection seam and this repo had no mocking library. Both gaps are now
// closed: CreatePostScreen takes an @visibleForTesting postRepository
// override, and SupabaseConfig.debugUserIdOverride lets tests set a fake
// signed-in user without a live Supabase connection.
//
// What's covered: single-flight (a rapid double-tap can't fire two
// publishes), the resume-after-failure path calling updatePendingPost
// instead of a second createPost, and that a failure leaves the composer
// usable (text preserved, no navigation) with the correct labeled error
// message. What's NOT covered here: Tag Friends' network calls
// (ProfileRepository isn't injectable — a smaller, separate seam would
// be needed) and media upload/attach, since MediaUploadService/file
// pickers aren't mocked either. Flagging honestly rather than pretending
// full coverage.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:gather_app/core/supabase_client.dart';
import 'package:gather_app/features/data/repositories.dart';
import 'package:gather_app/features/posts/create_post_screen.dart';

class MockPostRepository extends Mock implements PostRepository {}

void main() {
  const testUserId = 'test-user-1';

  late MockPostRepository repo;

  setUp(() {
    repo = MockPostRepository();
    SupabaseConfig.debugUserIdOverride = testUserId;

    // Default stubs so initState()'s draft/no-op paths don't hit
    // MissingStubError — individual tests override what they care about.
    when(() => repo.loadDraft(userId: any(named: 'userId'), communityId: any(named: 'communityId')))
        .thenAnswer((_) async => null);
    when(() => repo.deleteDraft(userId: any(named: 'userId'), communityId: any(named: 'communityId')))
        .thenAnswer((_) async {});
    when(() => repo.saveDraft(
          userId: any(named: 'userId'),
          communityId: any(named: 'communityId'),
          textContent: any(named: 'textContent'),
          tags: any(named: 'tags'),
          visibility: any(named: 'visibility'),
          pendingPostId: any(named: 'pendingPostId'),
        )).thenAnswer((_) async {});
  });

  tearDown(() {
    SupabaseConfig.debugUserIdOverride = null;
  });

  /// Minimal router so context.go('/') on publish success has somewhere
  /// to land, without depending on the app's real router.dart.
  Widget harness() {
    final router = GoRouter(
      initialLocation: '/compose',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('home'))),
        GoRoute(path: '/compose', builder: (_, __) => CreatePostScreen(postRepository: repo)),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  group('CreatePostScreen publish', () {
    testWidgets('a text-only post calls createPost once, then finalizePost, then navigates home', (tester) async {
      when(() => repo.createPost(any())).thenAnswer((_) async => {'id': 'post-1'});
      when(() => repo.finalizePost('post-1')).thenAnswer((_) async {});

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('composeTextField')), 'hello world');
      await tester.tap(find.byKey(const Key('publishButton')));
      await tester.pumpAndSettle();

      verify(() => repo.createPost(any())).called(1);
      verify(() => repo.finalizePost('post-1')).called(1);
      expect(find.text('home'), findsOneWidget); // navigated away on success
    });

    testWidgets('a rapid double-tap only fires one publish (single-flight)', (tester) async {
      final createPostCompleter = Completer<Map<String, dynamic>>();
      when(() => repo.createPost(any())).thenAnswer((_) => createPostCompleter.future);
      when(() => repo.finalizePost(any())).thenAnswer((_) async {});

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('composeTextField')), 'hello world');

      // First tap starts the publish; createPost is still pending.
      await tester.tap(find.byKey(const Key('publishButton')));
      await tester.pump();

      // Second, third rapid tap while the first is still in flight.
      await tester.tap(find.byKey(const Key('publishButton')));
      await tester.tap(find.byKey(const Key('publishButton')));
      await tester.pump();

      createPostCompleter.complete({'id': 'post-1'});
      await tester.pumpAndSettle();

      // Exactly one createPost call, no matter how many taps landed while
      // the button should have been disabled/guarded.
      verify(() => repo.createPost(any())).called(1);
    });

    testWidgets('finalizePost failing keeps the composer open with content preserved, and a retry resumes (no second createPost)', (tester) async {
      when(() => repo.createPost(any())).thenAnswer((_) async => {'id': 'post-1'});
      when(() => repo.finalizePost('post-1')).thenThrow(Exception('network blip'));

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('composeTextField')), 'hello world');
      await tester.tap(find.byKey(const Key('publishButton')));
      await tester.pumpAndSettle();

      // Did NOT navigate away — still on the composer.
      expect(find.text('home'), findsNothing);
      expect(find.byKey(const Key('composeTextField')), findsOneWidget);
      // Text content is preserved for the retry.
      expect(find.text('hello world'), findsOneWidget);
      // Requirement #12: the error names the step that actually failed.
      // (findsWidgets, not findsOneWidget: the same message also briefly
      // shows in a SnackBar alongside the persistent inline error text.)
      expect(find.textContaining('Finalizing post failed'), findsWidgets);

      // Retry: this time finalizePost succeeds.
      when(() => repo.finalizePost('post-1')).thenAnswer((_) async {});
      when(() => repo.updatePendingPost(
            'post-1',
            textContent: any(named: 'textContent'),
            visibility: any(named: 'visibility'),
            tags: any(named: 'tags'),
            mentionedUserIds: any(named: 'mentionedUserIds'),
            mentionedUsernames: any(named: 'mentionedUsernames'),
            isSensitive: any(named: 'isSensitive'),
          )).thenAnswer((_) async {});

      await tester.tap(find.byKey(const Key('publishButton')));
      await tester.pumpAndSettle();

      // The resume path updates the existing pending post rather than
      // creating a second one — createPost must still have been called
      // exactly once total, across both attempts.
      verify(() => repo.createPost(any())).called(1);
      verify(() => repo.updatePendingPost(
            'post-1',
            textContent: any(named: 'textContent'),
            visibility: any(named: 'visibility'),
            tags: any(named: 'tags'),
            mentionedUserIds: any(named: 'mentionedUserIds'),
            mentionedUsernames: any(named: 'mentionedUsernames'),
            isSensitive: any(named: 'isSensitive'),
          )).called(1);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('createPost failing shows a "Post creation failed" message, not a generic one', (tester) async {
      when(() => repo.createPost(any())).thenThrow(Exception('db unreachable'));

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('composeTextField')), 'hello world');
      await tester.tap(find.byKey(const Key('publishButton')));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsNothing);
      expect(find.textContaining('Post creation failed'), findsWidgets);
    });
  });
}
