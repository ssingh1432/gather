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
    expect(model.displayImageUrl, 'https://example.com/a.png');
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
    expect(model.displayImageUrl, 'https://example.com/b.png');
    expect(model.likeCount, 3);
    expect(model.commentCount, 4);
    expect(model.isLiked, isTrue);
    expect(model.isBookmarked, isTrue);
  });

  // --- migration 095: multi-attachment posts ---

  test('mediaItems parses the RPC-aggregated media_items array (get_home_feed*, get_community_feed, search_posts)', () {
    final model = PostModel.fromMap({
      'id': 'p4',
      'author_id': 'u4',
      'text_content': 'a post with everything',
      'created_at': '2026-01-01T00:00:00Z',
      'image_url': 'https://example.com/first.mp4', // legacy single column, still populated
      'media_items': [
        {'media_url': 'https://example.com/first.mp4', 'media_type': 'video'},
        {'media_url': 'https://example.com/second.png', 'media_type': 'image'},
        {'media_url': 'https://example.com/third.mp3', 'media_type': 'audio'},
        {'media_url': 'https://example.com/fourth.pdf', 'media_type': 'document'},
      ],
    });

    expect(model.mediaItems, hasLength(4));
    expect(model.mediaItems.map((m) => m.mediaType), ['video', 'image', 'audio', 'document']);
    // Legacy single-item fields mirror element 0, for any code not yet
    // updated to read mediaItems.
    expect(model.imageUrl, 'https://example.com/first.mp4');
    expect(model.mediaType, 'video');
    expect(model.isVideo, isTrue);
  });

  test('mediaItems parses the full post_media embed (publicFeed/repliesTo/postsByUser/getPost), not just the first row', () {
    final model = PostModel.fromMap({
      'id': 'p5',
      'author_id': 'u5',
      'text_content': 'image plus audio',
      'created_at': '2026-01-01T00:00:00Z',
      'post_media': [
        {'media_url': 'https://example.com/pic.png', 'media_type': 'image'},
        {'media_url': 'https://example.com/clip.mp3', 'media_type': 'audio'},
      ],
    });

    expect(model.mediaItems, hasLength(2));
    expect(model.mediaItems[0].mediaType, 'image');
    expect(model.mediaItems[1].mediaType, 'audio');
    expect(model.imageUrl, 'https://example.com/pic.png');
  });

  test('an RPC row with no media_items (post has no attachments) yields an empty mediaItems, not a crash', () {
    final model = PostModel.fromMap({
      'id': 'p6',
      'author_id': 'u6',
      'text_content': 'text only',
      'created_at': '2026-01-01T00:00:00Z',
      'media_items': <dynamic>[],
    });

    expect(model.mediaItems, isEmpty);
    expect(model.imageUrl, isNull);
    expect(model.mediaType, isNull);
  });

  test('audio/document posts classify correctly even when the RPC omits a flat media_type column '
      '(the get_home_feed/get_home_feed_cursor bug fixed by migration 095 — audio/document used to '
      'render as a broken image on the home feed because mediaType was always null there)', () {
    final model = PostModel.fromMap({
      'id': 'p7',
      'author_id': 'u7',
      'text_content': 'voice note',
      'created_at': '2026-01-01T00:00:00Z',
      'image_url': 'https://example.com/note.mp3', // what get_home_feed_cursor called it before the fix
      // no top-level 'media_type' key at all — matches the old RPC shape
      'media_items': [
        {'media_url': 'https://example.com/note.mp3', 'media_type': 'audio'},
      ],
    });

    expect(model.isAudio, isTrue);
    expect(model.isVideo, isFalse);
    expect(model.isDocument, isFalse);
  });

  test('copyWith preserves mediaItems (realtime like/comment-count patches must not silently drop attachments)', () {
    final model = PostModel.fromMap({
      'id': 'p8',
      'author_id': 'u8',
      'text_content': 'multi',
      'created_at': '2026-01-01T00:00:00Z',
      'media_items': [
        {'media_url': 'https://example.com/a.png', 'media_type': 'image'},
        {'media_url': 'https://example.com/b.mp4', 'media_type': 'video'},
      ],
    });

    final patched = model.copyWith(likeCount: 42);

    expect(patched.likeCount, 42);
    expect(patched.mediaItems, hasLength(2));
    expect(patched.mediaItems.map((m) => m.mediaType), ['image', 'video']);
  });

  test('PostModel derives structured thumbnail url for optimized uploads', () {
    final model = PostModel.fromMap({
      'id': 'p3',
      'author_id': 'u3',
      'text_content': '',
      'created_at': '2026-01-01T00:00:00Z',
      'image_url': 'https://example.supabase.co/storage/v1/object/public/post-media/posts/p3/original',
    });

    expect(model.displayImageUrl, 'https://example.supabase.co/storage/v1/object/public/post-media/posts/p3/thumb');
  });
}
