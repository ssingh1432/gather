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
}
