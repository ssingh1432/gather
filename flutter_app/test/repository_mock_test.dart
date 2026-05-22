import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/shared/models/models.dart';

void main() {
  test('PostModel.fromMap parses schema-aligned fields', () {
    final post = PostModel.fromMap({
      'id': 'p1',
      'author_id': 'u1',
      'text_content': 'hello',
      'created_at': '2026-01-01T00:00:00Z',
      'users': {'username': 'alice'},
      'post_media': [
        {'media_url': 'https://img'}
      ]
    });
    expect(post.authorId, 'u1');
    expect(post.textContent, 'hello');
    expect(post.authorUsername, 'alice');
    expect(post.imageUrl, 'https://img');
  });
}
