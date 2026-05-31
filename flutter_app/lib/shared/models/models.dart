class PostModel {
  final String id;
  final String authorId;
  final String? authorUsername;
  final String? communityId;
  final String textContent;
  final String? imageUrl;
  final String? thumbnailUrl;
  final DateTime createdAt;
  final int likeCount;
  final int commentCount;
  final bool isLiked;
  final bool isBookmarked;
  final DateTime? mediaUpdatedAt;

  PostModel({
    required this.id,
    required this.authorId,
    required this.textContent,
    required this.createdAt,
    this.authorUsername,
    this.communityId,
    this.imageUrl,
    this.thumbnailUrl,
    this.likeCount = 0,
    this.commentCount = 0,
    this.isLiked = false,
    this.isBookmarked = false,
    this.mediaUpdatedAt,
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
      imageUrl: flatImageUrl ?? (media != null && media.isNotEmpty ? media.first['media_url'] as String? : null),
      thumbnailUrl: flatThumbnailUrl ?? (media != null && media.isNotEmpty ? media.first['thumbnail_url'] as String? : null),
      likeCount: _intFromMap(map, 'like_count'),
      commentCount: _intFromMap(map, 'comment_count'),
      isLiked: map['is_liked'] == true,
      isBookmarked: map['is_bookmarked'] == true,
      mediaUpdatedAt: mediaUpdatedAtValue is String ? DateTime.tryParse(mediaUpdatedAtValue) : null,
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
