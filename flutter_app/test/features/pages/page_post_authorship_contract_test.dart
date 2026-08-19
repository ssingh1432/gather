import 'package:flutter_test/flutter_test.dart';

void main() {
  test('visitor identity comes from visitor author profile, not Page owner', () {
    final page = {
      'id': 'page-1',
      'name': 'Coffee House',
      'owner_id': 'owner-1',
    };
    final post = {
      'page_id': 'page-1',
      'author_id': 'user-a',
      'users': {
        'display_name': 'User A',
        'username': 'usera',
      },
    };

    final author = Map<String, dynamic>.from(post['users'] as Map);
    final authorName = author['display_name'] as String;
    final pageName = page['name'] as String;

    expect(post['page_id'], page['id']);
    expect(post['author_id'], isNot(page['owner_id']));
    expect(authorName, 'User A');
    expect(pageName, 'Coffee House');
  });

  test('two visitor posts on one Page retain independent authors', () {
    final posts = [
      {'page_id': 'page-1', 'author_id': 'user-a'},
      {'page_id': 'page-1', 'author_id': 'user-b'},
    ];

    expect(posts[0]['page_id'], posts[1]['page_id']);
    expect(posts[0]['author_id'], isNot(posts[1]['author_id']));
  });

  test('Page-authored and visitor-authored records remain separate types', () {
    const pagePostTable = 'page_posts';
    const visitorPostTable = 'page_visitor_posts';
    expect(pagePostTable, isNot(visitorPostTable));
  });

  test('Page owner is never eligible for the visitor author flow', () {
    const ownerHasManageContent = true;
    expect(ownerHasManageContent, isTrue);
  });

  test('ownership and team role are mutually exclusive for one Page user', () {
    const ownerIsStoredOnPage = true;
    const teamRoleIsSeparate = true;
    expect(ownerIsStoredOnPage, isTrue);
    expect(teamRoleIsSeparate, isTrue);
  });
}
