import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';
import '../../shared/services/analytics_service.dart';
import '../../shared/services/media_upload_service.dart';

class FeedRepository {
  SupabaseClient get _c => SupabaseConfig.client;


  Future<List<PostModel>> publicFeed({int page = 0, int pageSize = 20}) async {
    final data = await _c
        .from('posts')
        .select('*, users!posts_author_id_fkey(username), post_media(media_url)')
        .eq('is_removed', false)
        .order('created_at', ascending: false)
        .range(page * pageSize, page * pageSize + pageSize - 1);
    return (data as List).map((e) => PostModel.fromMap(e)).toList();
  }

  Future<List<PostModel>> homeFeed(String userId, {int page = 0, int pageSize = 20}) async {
    final data = await _c.rpc('get_home_feed', params: {
      'user_id': userId,
      'page_size': pageSize,
      'page_offset': page * pageSize,
    });
    return (data as List).map((e) => PostModel.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<PostModel> getPost(String postId) async {
    final data = await _c.from('posts').select('*, users!posts_author_id_fkey(username), post_media(media_url)').eq('id', postId).eq('is_removed', false).single();
    return PostModel.fromMap(data);
  }

  Future<List<Map<String, dynamic>>> comments(String postId) async =>
      ((await _c.from('post_comments').select('*, users!post_comments_user_id_fkey(username)').eq('post_id', postId).order('created_at')) as List).cast<Map<String, dynamic>>();

  Future<void> addComment(String postId, String userId, String content) async {
    await _c.from('post_comments').insert({'post_id': postId, 'user_id': userId, 'content': content});
    AnalyticsService.instance.commentCreated(postId: postId);
  }

  Future<List<PostModel>> communityFeed(String communityId, {String? userId, int page = 0, int pageSize = 20}) async {
    final data = await _c.rpc('get_community_feed', params: {
      'community_id': communityId,
      'user_id': userId,
      'page_size': pageSize,
      'page_offset': page * pageSize,
    });
    return (data as List).map((e) => PostModel.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<Set<String>> likedPostIds(String userId, List<String> postIds) async {
    if (postIds.isEmpty) return {};
    final data = await _c.from('post_likes').select('post_id').eq('user_id', userId).inFilter('post_id', postIds);
    return (data as List).map((e) => e['post_id'].toString()).toSet();
  }

  Future<Set<String>> bookmarkedPostIds(String userId, List<String> postIds) async {
    if (postIds.isEmpty) return {};
    final data = await _c.from('bookmarks').select('post_id').eq('user_id', userId).inFilter('post_id', postIds);
    return (data as List).map((e) => e['post_id'].toString()).toSet();
  }

  Future<void> likePost(String postId, String userId) => _c.from('post_likes').upsert({'post_id': postId, 'user_id': userId});
  Future<void> unlikePost(String postId, String userId) => _c.from('post_likes').delete().match({'post_id': postId, 'user_id': userId});
  Future<void> bookmarkPost(String postId, String userId) => _c.from('bookmarks').upsert({'post_id': postId, 'user_id': userId});
  Future<void> unbookmarkPost(String postId, String userId) => _c.from('bookmarks').delete().match({'post_id': postId, 'user_id': userId});
}

class CommunityRepository {
  SupabaseClient get _c => SupabaseConfig.client;
  Future<List<Map<String, dynamic>>> listCommunities([String query = '']) async {
    var req = _c.from('communities').select();
    if (query.isNotEmpty) req = req.ilike('name', '%$query%');
    final data = await req.order('name');
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<bool> isJoined(String communityId, String userId) async => (await _c.from('community_memberships').select('community_id').match({'community_id': communityId, 'user_id': userId}).maybeSingle()) != null;
  Future<Map<String, bool>> joinedStates(List<String> communityIds, String userId) async {
    if (communityIds.isEmpty) return {};
    final rows = await _c.from('community_memberships').select('community_id').eq('user_id', userId).inFilter('community_id', communityIds);
    final joined = (rows as List).map((e) => e['community_id'].toString()).toSet();
    return {for (final id in communityIds) id: joined.contains(id)};
  }

  Future<Map<String, dynamic>> createCommunity(Map<String, dynamic> payload) async => await _c.from('communities').insert(payload).select().single();
  Future<void> joinCommunity(String communityId, String userId) async {
    await _c.from('community_memberships').upsert({'community_id': communityId, 'user_id': userId});
    AnalyticsService.instance.communityJoined(communityId: communityId);
  }
  Future<void> leaveCommunity(String communityId, String userId) => _c.from('community_memberships').delete().match({'community_id': communityId, 'user_id': userId});
}

class ProfileRepository {
  SupabaseClient get _c => SupabaseConfig.client;
  Future<Map<String, dynamic>?> loadProfile(String userId) async => await _c.from('users').select().eq('id', userId).maybeSingle();
  Future<int> followers(String userId) async => await _c.from('user_follows').count(CountOption.exact).eq('following_id', userId);
  Future<int> following(String userId) async => await _c.from('user_follows').count(CountOption.exact).eq('follower_id', userId);
  Future<void> updateProfile(String userId, Map<String, dynamic> payload) => _c.from('users').update(payload).eq('id', userId);
  Future<void> follow(String targetId, String userId) => _c.from('user_follows').upsert({'following_id': targetId, 'follower_id': userId});
  Future<void> unfollow(String targetId, String userId) => _c.from('user_follows').delete().match({'following_id': targetId, 'follower_id': userId});
  Future<void> block(String targetId, String userId) => _c.from('user_blocks').upsert({'blocked_id': targetId, 'blocker_id': userId});
  Future<String> uploadProfileImage(String userId, XFile file, ProfileImageKind kind) =>
      MediaUploadService().uploadProfileImage(userId: userId, image: file, kind: kind);
}

class PostRepository {
  SupabaseClient get _c => SupabaseConfig.client;
  Future<Map<String, dynamic>> createPost(Map<String, dynamic> payload) async {
    final created = await _c.from('posts').insert(payload).select().single();
    AnalyticsService.instance.postCreated(
      postId: created['id'].toString(),
      communityId: created['community_id']?.toString(),
    );
    return created;
  }
  Future<void> addComment(Map<String, dynamic> payload) async {
    await _c.from('post_comments').insert(payload);
    final postId = payload['post_id']?.toString();
    if (postId != null) AnalyticsService.instance.commentCreated(postId: postId);
  }
  Future<UploadedPostImage> uploadPostImage(String postId, XFile file) async {
    final mediaService = MediaUploadService();
    final prepared = await mediaService.preparePostImage(file);
    return mediaService.uploadPostImage(postId: postId, image: prepared);
  }

  Future<void> addPostMedia(String postId, String mediaUrl) async {
    await _c.from('post_media').delete().eq('post_id', postId).eq('media_type', 'image');
    await _c.from('post_media').insert({'post_id': postId, 'media_type': 'image', 'media_url': mediaUrl});
  }
}

class ModerationRepository {
  SupabaseClient get _c => SupabaseConfig.client;
  Future<void> report(Map<String, dynamic> payload) => _c.from('reports').insert(payload);
  Future<List<Map<String, dynamic>>> openReports() async => ((await _c.from('reports').select().eq('status', 'open')) as List).cast<Map<String, dynamic>>();
  Future<void> removePost(String postId, {String? reportId}) => _c.rpc('soft_remove_post', params: {
        'post_id': postId,
        'report_id': reportId,
      });
  Future<void> suspendUser(String userId, {String? reportId}) => _c.rpc('suspend_user', params: {
        'target_user_id': userId,
        'report_id': reportId,
      });
  Future<void> resolveReport(String reportId) => _c.rpc('resolve_report', params: {'report_id': reportId});
}

class BetaOpsRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  Future<List<Map<String, dynamic>>> feedback() async {
    final rows = await _c.from('beta_feedback').select('*, users!beta_feedback_user_id_fkey(username, email)').order('created_at', ascending: false).limit(100);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> reviewFeedback(String feedbackId, {required String tag, required String status, String? notes}) => _c.rpc('review_beta_feedback', params: {
        'feedback_id': feedbackId,
        'feedback_tag': tag,
        'feedback_status': status,
        'notes': notes,
      });
}
