/// A lightweight, embeddable preview of a post that another [PostModel] is
/// quoting/replying to (the "share as a post" flow). Kept intentionally
/// small — just enough to render a quoted-post card inside the feed.
class QuotedPostPreview {
  final String id;
  final String? authorUsername;
  final String? authorAvatarUrl;
  final String textContent;
  final String? imageUrl;
  final DateTime createdAt;
  final bool removed;

  QuotedPostPreview({
    required this.id,
    required this.textContent,
    required this.createdAt,
    this.authorUsername,
    this.authorAvatarUrl,
    this.imageUrl,
    this.removed = false,
  });

  static QuotedPostPreview? fromMap(Map<String, dynamic> map) {
    final id = map['reply_to_post_id'];
    if (id == null) return null;
    final removed = map['reply_to_removed'] == true;
    final createdAtValue = map['reply_to_created_at'];
    return QuotedPostPreview(
      id: id.toString(),
      authorUsername: map['reply_to_author_username'] as String?,
      authorAvatarUrl: map['reply_to_author_avatar_url'] as String?,
      textContent: map['reply_to_text_content'] as String? ?? '',
      imageUrl: map['reply_to_image_url'] as String?,
      createdAt: createdAtValue is String ? (DateTime.tryParse(createdAtValue) ?? DateTime.now()) : DateTime.now(),
      removed: removed,
    );
  }
}

class PostModel {
  final String id;
  final String authorId;
  final String? authorUsername;
  final String? authorAvatarUrl;
  final String? communityId;
  final String textContent;
  final String? imageUrl;
  final String? thumbnailUrl;
  final DateTime createdAt;
  final int likeCount;
  final int commentCount;
  final int shareCount;
  final bool isLiked;
  final bool isBookmarked;
  final DateTime? mediaUpdatedAt;
  final String? location;
  final String? feeling;
  final List<String> tags;
  final QuotedPostPreview? replyTo;

  PostModel({
    required this.id,
    required this.authorId,
    required this.textContent,
    required this.createdAt,
    this.authorUsername,
    this.authorAvatarUrl,
    this.communityId,
    this.imageUrl,
    this.thumbnailUrl,
    this.likeCount = 0,
    this.commentCount = 0,
    this.shareCount = 0,
    this.isLiked = false,
    this.isBookmarked = false,
    this.mediaUpdatedAt,
    this.location,
    this.feeling,
    this.tags = const [],
    this.replyTo,
  });

  factory PostModel.fromMap(Map<String, dynamic> map) {
    final author = map['users'];
    final media = map['post_media'] as List?;
    final flatImageUrl = map['image_url'] as String?;
    final flatThumbnailUrl = map['thumbnail_url'] as String?;
    final mediaUpdatedAtValue = map['media_updated_at'] ?? (media != null && media.isNotEmpty ? media.first['updated_at'] : null);
    return PostModel(
      id: map['id'].toString(),
      authorId: map['author_id'].toString(),
      textContent: map['text_content'] ?? '',
      createdAt: DateTime.parse(map['created_at']),
      communityId: map['community_id']?.toString(),
      authorUsername: author is Map<String, dynamic> ? author['username'] : map['author_username'] as String?,
      authorAvatarUrl: author is Map<String, dynamic> ? author['profile_photo_url'] as String? : map['author_avatar_url'] as String?,
      imageUrl: flatImageUrl ?? (media != null && media.isNotEmpty ? media.first['media_url'] as String? : null),
      thumbnailUrl: flatThumbnailUrl ?? (media != null && media.isNotEmpty ? media.first['thumbnail_url'] as String? : null),
      likeCount: _intFromMap(map, 'like_count'),
      commentCount: _intFromMap(map, 'comment_count'),
      shareCount: _intFromMap(map, 'share_count'),
      isLiked: map['is_liked'] == true,
      isBookmarked: map['is_bookmarked'] == true,
      mediaUpdatedAt: mediaUpdatedAtValue is String ? DateTime.tryParse(mediaUpdatedAtValue) : null,
      location: map['location'] as String?,
      feeling: map['feeling'] as String?,
      tags: ((map['tags'] as List?) ?? const []).map((e) => e.toString()).toList(),
      replyTo: QuotedPostPreview.fromMap(map),
    );
  }

  String? get displayImageUrl => thumbnailUrl ?? _derivedThumbnailUrl ?? imageUrl;

  String get imageCacheKey => '$id:${(mediaUpdatedAt ?? createdAt).millisecondsSinceEpoch}:${displayImageUrl ?? ''}';

  String? get _derivedThumbnailUrl {
    final url = imageUrl;
    if (url == null || !url.contains('/posts/') || !url.contains('/original')) return null;
    return url.replaceFirst('/original', '/thumb');
  }

  static int _intFromMap(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

/// A minimal user shape for lightweight lists (recommendations, search
/// results) that don't need the full profile payload.
class RecommendedUser {
  final String id;
  final String username;
  final String? avatarUrl;

  RecommendedUser({required this.id, required this.username, this.avatarUrl});

  factory RecommendedUser.fromMap(Map<String, dynamic> map) => RecommendedUser(
        id: map['id'].toString(),
        username: map['username'] as String? ?? 'user',
        avatarUrl: map['profile_photo_url'] as String?,
      );
}


/// A single comment (or reply-to-comment) on a post. [parentCommentId] is
/// null for a top-level comment; when set, the comment nests one level
/// under the comment it replies to. [replyCount] is denormalized server
/// side so the UI can show "View N replies" without an extra query.
class CommentModel {
  final String id;
  final String postId;
  final String userId;
  final String? username;
  final String? avatarUrl;
  final String content;
  final DateTime createdAt;
  final String? parentCommentId;
  final int replyCount;

  CommentModel({
    required this.id,
    required this.postId,
    required this.userId,
    required this.content,
    required this.createdAt,
    this.username,
    this.avatarUrl,
    this.parentCommentId,
    this.replyCount = 0,
  });

  factory CommentModel.fromMap(Map<String, dynamic> map) {
    final author = map['users'];
    return CommentModel(
      id: map['id'].toString(),
      postId: map['post_id'].toString(),
      userId: map['user_id'].toString(),
      content: map['content'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at']),
      username: author is Map<String, dynamic> ? author['username'] as String? : null,
      avatarUrl: author is Map<String, dynamic> ? author['profile_photo_url'] as String? : null,
      parentCommentId: map['parent_comment_id']?.toString(),
      replyCount: PostModel._intFromMap(map, 'reply_count'),
    );
  }
}
