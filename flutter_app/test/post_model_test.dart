import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/shared/models/models.dart';

void main() {
  test('PostModel.fromMap parses nested author/media', () {
    final model = PostModel.fromMap({
      'id': 'p1',
      'author_id': 'u1',
      'text_content': 'hello',
      'created_at': '2026-01-01T00:00:00Z',
      'community_id': 'c1',
      'users': {'username': 'alice'},
      'post_media': [
        {'media_url': 'https://example.com/a.png'}
      ],
    });

    expect(model.id, 'p1');
    expect(model.authorUsername, 'alice');
    expect(model.imageUrl, 'https://example.com/a.png');
    expect(model.communityId, 'c1');
  });

  test('PostModel.fromMap parses backend feed fields', () {
    final model = PostModel.fromMap({
      'id': 'p2',
      'author_id': 'u2',
      'text_content': 'from rpc',
      'created_at': '2026-01-01T00:00:00Z',
      'author_username': 'bob',
      'image_url': 'https://example.com/b.png',
      'like_count': 3,
      'comment_count': '4',
      'is_liked': true,
      'is_bookmarked': true,
    });

    expect(model.authorUsername, 'bob');
    expect(model.imageUrl, 'https://example.com/b.png');
    expect(model.likeCount, 3);
    expect(model.commentCount, 4);
    expect(model.isLiked, isTrue);
    expect(model.isBookmarked, isTrue);
  });
}
