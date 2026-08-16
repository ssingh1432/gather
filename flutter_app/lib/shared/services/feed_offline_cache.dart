import 'dart:convert';

import '../models/models.dart';
import 'feed_offline_cache_io.dart' if (dart.library.html) 'feed_offline_cache_web.dart' as impl;

/// A small, non-authoritative disk/localStorage snapshot of the last
/// successfully-loaded first page of the home feed (Step 16 — offline
/// support). Never a source of truth: it's read only when a live fetch
/// fails, purely so the person sees *something* instead of a blank error
/// screen when they open the app without a connection.
class FeedOfflineCache {
  FeedOfflineCache._();

  static const _maxCachedPosts = 20;

  static Future<void> save(List<PostModel> posts) async {
    if (posts.isEmpty) return;
    try {
      final payload = jsonEncode({
        'saved_at': DateTime.now().toIso8601String(),
        'posts': posts.take(_maxCachedPosts).map(_toJson).toList(),
      });
      await impl.write(payload);
    } catch (_) {
      // Best-effort — a failed cache write should never interrupt a
      // successful feed load.
    }
  }

  static Future<CachedFeed?> load() async {
    try {
      final raw = await impl.read();
      if (raw == null) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(decoded['saved_at'] as String? ?? '') ?? DateTime.now();
      final posts = ((decoded['posts'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(PostModel.fromMap)
          .toList();
      return CachedFeed(posts: posts, savedAt: savedAt);
    } catch (_) {
      return null;
    }
  }

  /// Only the fields PostModel.fromMap actually reads for feed-card
  /// rendering — this is a read-mostly fallback view, not a full offline
  /// replica of the row (likes/comments interactions still require a live
  /// connection either way).
  static Map<String, dynamic> _toJson(PostModel p) => {
        'id': p.id,
        'author_id': p.authorId,
        'author_username': p.authorUsername,
        'author_avatar_url': p.authorAvatarUrl,
        'community_id': p.communityId,
        'text_content': p.textContent,
        'image_url': p.imageUrl,
        'thumbnail_url': p.thumbnailUrl,
        'created_at': p.createdAt.toIso8601String(),
        'like_count': p.likeCount,
        'comment_count': p.commentCount,
        'share_count': p.shareCount,
        'tags': p.tags,
        'media_type': p.mediaType,
        'visibility': p.visibility,
        'content_type': p.contentType,
        'is_pinned': p.isPinned,
        'page_id': p.contentType == 'page_visitor' ? p.communityId : null,
      };
}

class CachedFeed {
  const CachedFeed({required this.posts, required this.savedAt});
  final List<PostModel> posts;
  final DateTime savedAt;
}
