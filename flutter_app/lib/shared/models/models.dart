class PostModel {
  final String id;
  final String authorId;
  final String? authorUsername;
  final String? communityId;
  final String textContent;
  final String? imageUrl;
  final DateTime createdAt;

  PostModel({
    required this.id,
    required this.authorId,
    required this.textContent,
    required this.createdAt,
    this.authorUsername,
    this.communityId,
    this.imageUrl,
  });

  factory PostModel.fromMap(Map<String, dynamic> map) {
    final author = map['users'];
    final media = map['post_media'] as List?;
    return PostModel(
      id: map['id'].toString(),
      authorId: map['author_id'].toString(),
      textContent: map['text_content'] ?? '',
      createdAt: DateTime.parse(map['created_at']),
      communityId: map['community_id']?.toString(),
      authorUsername: author is Map<String, dynamic> ? author['username'] : null,
      imageUrl: media != null && media.isNotEmpty ? media.first['media_url'] as String? : null,
    );
  }
}
