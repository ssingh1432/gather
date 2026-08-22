import 'package:flutter_test/flutter_test.dart';

import '../../../shared/models/models.dart';

void main() {
  test('Page owner Home Feed rows use page_owner content type and Page identity', () {
    final post = PostModel.fromMap({
      'id': 'page-post-1',
      'author_id': 'owner-1',
      'author_username': 'Coffee House',
      'author_avatar_url': 'https://example.test/logo.png',
      'community_id': 'page-1',
      'text_content': 'Today we are open until 9 PM.',
      'created_at': '2026-08-22T10:00:00Z',
      'location': 'Posted on Coffee House',
      'content_type': 'page_owner',
      'media_items': [
        {'media_url': 'https://example.test/image.jpg', 'media_type': 'image'},
      ],
    });

    expect(post.contentType, 'page_owner');
    expect(post.communityId, 'page-1');
    expect(post.authorUsername, 'Coffee House');
    expect(post.authorAvatarUrl, 'https://example.test/logo.png');
    expect(post.mediaItems, hasLength(1));
    expect(post.mediaItems.single.mediaType, 'image');
  });

  test('Page owner and visitor Home Feed content types remain distinct', () {
    expect('page_owner', isNot('page_visitor'));
  });
}
