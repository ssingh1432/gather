import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';

class FeedRepository {
  Future<List<PostModel>> homeFeed({int page = 0, int pageSize = 20}) async {
    final from = page * pageSize;
    final to = from + pageSize - 1;
    final data = await SupabaseConfig.client
        .from('posts')
        .select()
        .order('created_at', ascending: false)
        .range(from, to);
    return (data as List).map((e) => PostModel.fromMap(e)).toList();
  }

  Future<List<PostModel>> communityFeed(String communityId, {int page = 0, int pageSize = 20}) async {
    final from = page * pageSize;
    final to = from + pageSize - 1;
    final data = await SupabaseConfig.client
        .from('posts')
        .select()
        .eq('community_id', communityId)
        .order('created_at', ascending: false)
        .range(from, to);
    return (data as List).map((e) => PostModel.fromMap(e)).toList();
  }

  Future<void> likePost(String postId, String userId) => SupabaseConfig.client.from('post_likes').insert({'post_id': postId, 'user_id': userId});
  Future<void> unlikePost(String postId, String userId) => SupabaseConfig.client.from('post_likes').delete().match({'post_id': postId, 'user_id': userId});
  Future<void> bookmarkPost(String postId, String userId) => SupabaseConfig.client.from('bookmarks').insert({'post_id': postId, 'user_id': userId});
}

class CommunityRepository {
  Future<void> createCommunity(Map<String, dynamic> payload) => SupabaseConfig.client.from('communities').insert(payload);
  Future<void> joinCommunity(String communityId, String userId) => SupabaseConfig.client.from('community_members').insert({'community_id': communityId, 'user_id': userId});
  Future<void> leaveCommunity(String communityId, String userId) => SupabaseConfig.client.from('community_members').delete().match({'community_id': communityId, 'user_id': userId});
}

class ProfileRepository {
  Future<Map<String, dynamic>?> loadProfile(String userId) async {
    final data = await SupabaseConfig.client.from('profiles').select().eq('id', userId).maybeSingle();
    return data;
  }

  Future<void> updateProfile(String userId, Map<String, dynamic> payload) =>
      SupabaseConfig.client.from('profiles').update(payload).eq('id', userId);

  Future<void> follow(String targetId, String userId) => SupabaseConfig.client.from('follows').insert({'following_id': targetId, 'follower_id': userId});
  Future<void> unfollow(String targetId, String userId) => SupabaseConfig.client.from('follows').delete().match({'following_id': targetId, 'follower_id': userId});
  Future<void> block(String targetId, String userId) => SupabaseConfig.client.from('blocks').insert({'blocked_id': targetId, 'blocker_id': userId});
}

class PostRepository {
  Future<void> createPost(Map<String, dynamic> payload) => SupabaseConfig.client.from('posts').insert(payload);
  Future<void> addComment(Map<String, dynamic> payload) => SupabaseConfig.client.from('comments').insert(payload);
}

class ModerationRepository {
  Future<void> report(Map<String, dynamic> payload) => SupabaseConfig.client.from('reports').insert(payload);
  Future<void> removePost(String postId) => SupabaseConfig.client.from('posts').delete().eq('id', postId);
  Future<void> banUser(String userId) => SupabaseConfig.client.from('profiles').update({'is_banned': true}).eq('id', userId);
}
