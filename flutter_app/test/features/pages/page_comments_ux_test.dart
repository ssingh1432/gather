import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gather_app/features/pages/page_comments_ux.dart';

void main() {
  final comments = <Map<String, dynamic>>[
    {'id': 'c1', 'user_id': 'u1', 'content': 'Main comment', 'created_at': '2026-08-25T00:00:00Z', 'parent_comment_id': null, 'users': {'username': 'John'}},
    {'id': 'c2', 'user_id': 'u2', 'content': 'First reply', 'created_at': '2026-08-25T00:01:00Z', 'parent_comment_id': 'c1', 'users': {'username': 'Mary'}},
    {'id': 'c3', 'user_id': 'u3', 'content': 'Second reply', 'created_at': '2026-08-25T00:02:00Z', 'parent_comment_id': 'c2', 'users': {'username': 'David'}},
    {'id': 'c4', 'user_id': 'u4', 'content': 'Third reply', 'created_at': '2026-08-25T00:03:00Z', 'parent_comment_id': 'c3', 'users': {'username': 'Peter'}},
  ];

  testWidgets('renders reply chains flat and identifies exact reply targets', (tester) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PageCommentsUx(
          comments: comments,
          loading: false,
          sending: false,
          replyingTo: comments[2],
          onReply: (_) {},
          onCancelReply: () {},
          onSubmit: () {},
          controller: controller,
          focusNode: focus,
        ),
      ),
    ));

    expect(find.byKey(const ValueKey('page-comment-c1')), findsOneWidget);
    expect(find.byKey(const ValueKey('page-comment-c2')), findsOneWidget);
    expect(find.byKey(const ValueKey('page-comment-c3')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('page-comment-c4')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('page-comment-c4')), findsOneWidget);
    expect(find.byKey(const ValueKey('page-reply-target-c2')), findsOneWidget);
    expect(find.byKey(const ValueKey('page-reply-target-c3')), findsOneWidget);
    expect(find.byKey(const ValueKey('page-reply-target-c4')), findsOneWidget);
    expect(find.text('First reply'), findsOneWidget);
    expect(find.text('Second reply'), findsOneWidget);
    expect(find.text('Third reply'), findsOneWidget);
    expect(find.text('Replying to @David'), findsOneWidget);
  });

  testWidgets('keeps ten-plus replies in bounded scrollable list', (tester) async {
    final many = <Map<String, dynamic>>[
      {'id': 'root', 'user_id': 'u0', 'content': 'Root', 'created_at': '2026-08-25T00:00:00Z', 'parent_comment_id': null, 'users': {'username': 'root'}},
      for (var i = 1; i <= 12; i++)
        {'id': 'c$i', 'user_id': 'u$i', 'content': 'Reply $i', 'created_at': '2026-08-25T00:00:00Z', 'parent_comment_id': i == 1 ? 'root' : 'c${i - 1}', 'users': {'username': 'user$i'}},
    ];
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PageCommentsUx(
          comments: many,
          loading: false,
          sending: false,
          replyingTo: null,
          onReply: (_) {},
          onCancelReply: () {},
          onSubmit: () {},
          controller: controller,
          focusNode: focus,
        ),
      ),
    ));

    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('Write a comment…'), findsOneWidget);
  });
}
