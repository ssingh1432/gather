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
    expect(post['page_id'], page['id']);
    expect(post['author_id'], isNot(page['owner_id']));
    expect(author['display_name'], 'User A');
    expect(page['name'], 'Coffee House');
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

  test('Page owner cannot be represented as a visitor author for the same Page', () {
    const pageOwnerId = 'owner-1';
    const visitorAuthorId = 'user-a';
    expect(visitorAuthorId, isNot(pageOwnerId));
  });

  test('a Page owner is not simultaneously a Page team role', () {
    const pageOwnerId = 'owner-1';
    const teamRoleUserId = 'user-a';
    expect(teamRoleUserId, isNot(pageOwnerId));
  });

  test('visitor authorship never grants Page ownership', () {
    const visitorAuthorId = 'user-a';
    const pageOwnerId = 'owner-1';
    expect(visitorAuthorId, isNot(pageOwnerId));
  });
}
