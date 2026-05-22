class PostModel {
  final String id;
  final String? communityId;
  final String userId;
  final String content;
  final String? imageUrl;
  final DateTime createdAt;

  PostModel({required this.id, required this.userId, required this.content, required this.createdAt, this.communityId, this.imageUrl});

  factory PostModel.fromMap(Map<String, dynamic> map) => PostModel(
        id: map['id'].toString(),
        userId: map['user_id'].toString(),
        content: map['content'] ?? '',
        imageUrl: map['image_url'],
        communityId: map['community_id']?.toString(),
        createdAt: DateTime.parse(map['created_at']),
      );
}
