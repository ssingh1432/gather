import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';

class FeedRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  Future<List<PostModel>> homeFeed({int page = 0, int pageSize = 20}) async {
    final from = page * pageSize;
    final to = from + pageSize - 1;
    final data = await _c
        .from('posts')
        .select('*, users(username), post_media(media_url)')
        .eq('is_removed', false)
        .order('created_at', ascending: false)
        .range(from, to);
    return (data as List).map((e) => PostModel.fromMap(e)).toList();
  }

  Future<List<PostModel>> communityFeed(String communityId, {int page = 0, int pageSize = 20}) async {
    final data = await _c.from('posts').select('*, users(username), post_media(media_url)').eq('community_id', communityId).order('created_at', ascending: false).range(page * pageSize, page * pageSize + pageSize - 1);
    return (data as List).map((e) => PostModel.fromMap(e)).toList();
  }

  Future<void> likePost(String postId, String userId) => _c.from('post_likes').insert({'post_id': postId, 'user_id': userId});
  Future<void> unlikePost(String postId, String userId) => _c.from('post_likes').delete().match({'post_id': postId, 'user_id': userId});
  Future<void> bookmarkPost(String postId, String userId) => _c.from('bookmarks').insert({'post_id': postId, 'user_id': userId});
}

class CommunityRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  Future<List<Map<String, dynamic>>> listCommunities([String query = '']) async {
    var req = _c.from('communities').select();
    if (query.isNotEmpty) req = req.ilike('name', '%$query%');
    final data = await req.order('name');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createCommunity(Map<String, dynamic> payload) async =>
      await _c.from('communities').insert(payload).select().single();

  Future<void> joinCommunity(String communityId, String userId) => _c.from('community_memberships').insert({'community_id': communityId, 'user_id': userId});
  Future<void> leaveCommunity(String communityId, String userId) => _c.from('community_memberships').delete().match({'community_id': communityId, 'user_id': userId});
}

class ProfileRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  Future<Map<String, dynamic>?> loadProfile(String userId) async => await _c.from('users').select().eq('id', userId).maybeSingle();

  Future<void> updateProfile(String userId, Map<String, dynamic> payload) => _c.from('users').update(payload).eq('id', userId);

  Future<void> follow(String targetId, String userId) => _c.from('user_follows').insert({'following_id': targetId, 'follower_id': userId});
  Future<void> unfollow(String targetId, String userId) => _c.from('user_follows').delete().match({'following_id': targetId, 'follower_id': userId});
  Future<void> block(String targetId, String userId) => _c.from('user_blocks').insert({'blocked_id': targetId, 'blocker_id': userId});
}

class PostRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  Future<void> createPost(Map<String, dynamic> payload) => _c.from('posts').insert(payload);
  Future<void> addComment(Map<String, dynamic> payload) => _c.from('post_comments').insert(payload);

  Future<String?> uploadPostImage(String userId, XFile file) async {
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
    await _c.storage.from('post-media').upload(path, File(file.path));
    return _c.storage.from('post-media').getPublicUrl(path);
  }

  Future<void> addPostMedia(String postId, String mediaUrl) => _c.from('post_media').insert({'post_id': postId, 'media_type': 'image', 'media_url': mediaUrl});
}

class ModerationRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  Future<void> report(Map<String, dynamic> payload) => _c.from('reports').insert(payload);
  Future<List<Map<String, dynamic>>> openReports() async => ((await _c.from('reports').select().eq('status', 'open')) as List).cast<Map<String, dynamic>>();
  Future<void> removePost(String postId) => _c.from('posts').update({'is_removed': true}).eq('id', postId);
  Future<void> banUser(String userId) => _c.from('users').update({'status': 'banned'}).eq('id', userId);
}
