import 'dart:convert';

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
        .select('*, users!posts_author_id_fkey(username), post_media(media_url, media_type)')
        .eq('is_removed', false)
        .order('created_at', ascending: false)
        .range(page * pageSize, page * pageSize + pageSize - 1);
    return (data as List).map((e) => PostModel.fromMap(e)).toList();
  }

  /// Posts that reply/quote a given post (the reverse of `replyTo` on a
  /// post) — powers the "N replies" list opened from the feed.
  Future<List<PostModel>> repliesTo(String postId, {int limit = 50}) async {
    final data = await _c
        .from('posts')
        .select('*, users!posts_author_id_fkey(username, profile_photo_url), post_media(media_url, media_type)')
        .eq('reply_to_post_id', postId)
        .eq('is_removed', false)
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List).map((e) => PostModel.fromMap(e)).toList();
  }

  /// A user's own published posts, newest first — backs the photo/video
  /// grid on their profile.
  Future<List<PostModel>> postsByUser(String userId, {int limit = 30}) async {
    final data = await _c
        .from('posts')
        .select('*, users!posts_author_id_fkey(username, profile_photo_url), post_media(media_url, media_type)')
        .eq('author_id', userId)
        .eq('is_removed', false)
        .order('created_at', ascending: false)
        .limit(limit);
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
    final data = await _c
        .from('posts')
        .select('*, users!posts_author_id_fkey(username, profile_photo_url), post_media(media_url, media_type)')
        .eq('id', postId)
        .eq('is_removed', false)
        .single();

    final likeCount = await _c.from('post_likes').count(CountOption.exact).eq('post_id', postId);
    final commentCount = await _c.from('post_comments').count(CountOption.exact).eq('post_id', postId);

    final merged = <String, dynamic>{
      ...data,
      'like_count': likeCount,
      'comment_count': commentCount,
    };

    final replyToId = data['reply_to_post_id'];
    if (replyToId != null) {
      final quoted = await _c
          .from('posts')
          .select('id, text_content, created_at, is_removed, users!posts_author_id_fkey(username, profile_photo_url), post_media(media_url, media_type)')
          .eq('id', replyToId)
          .maybeSingle();
      if (quoted == null || quoted['is_removed'] == true) {
        merged['reply_to_removed'] = true;
      } else {
        final quotedMedia = quoted['post_media'] as List?;
        final quotedAuthor = quoted['users'] as Map<String, dynamic>?;
        merged['reply_to_author_username'] = quotedAuthor?['username'];
        merged['reply_to_author_avatar_url'] = quotedAuthor?['profile_photo_url'];
        merged['reply_to_text_content'] = quoted['text_content'];
        merged['reply_to_image_url'] = (quotedMedia != null && quotedMedia.isNotEmpty) ? quotedMedia.first['media_url'] : null;
        merged['reply_to_created_at'] = quoted['created_at'];
        merged['reply_to_removed'] = false;
      }
    }

    return PostModel.fromMap(merged);
  }

  Future<List<CommentModel>> comments(String postId) async {
    final data = await _c
        .from('post_comments')
        .select('*, users!post_comments_user_id_fkey(username, profile_photo_url)')
        .eq('post_id', postId)
        .order('created_at');
    return (data as List).map((e) => CommentModel.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<void> addComment(String postId, String userId, String content, {String? parentCommentId}) async {
    await _c.from('post_comments').insert({
      'post_id': postId,
      'user_id': userId,
      'content': content,
      if (parentCommentId != null) 'parent_comment_id': parentCommentId,
    });
    AnalyticsService.instance.commentCreated(postId: postId);
  }

  /// Logs a share (system share sheet / copy link) so the post's share
  /// counter goes up in the same "loop" way likes and comments do.
  Future<void> sharePost(String postId, String userId, {String target = 'external'}) async {
    await _c.from('post_shares').insert({'post_id': postId, 'user_id': userId, 'target': target});
    AnalyticsService.instance.firstActionCompleted(action: 'post_shared');
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

  /// Who liked this post — powers the "liked by" list opened from the like
  /// count. Newest like first.
  Future<List<RecommendedUser>> likersOf(String postId, {int limit = 50}) async {
    final data = await _c
        .from('post_likes')
        .select('user_id, created_at, users!post_likes_user_id_fkey(id, username, profile_photo_url)')
        .eq('post_id', postId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List)
        .map((row) => row['users'])
        .whereType<Map<String, dynamic>>()
        .map(RecommendedUser.fromMap)
        .toList();
  }

  Future<List<RecommendedUser>> sharersOf(String postId, {int limit = 50}) async {
    final data = await _c
        .from('post_shares')
        .select('user_id, created_at, users!post_shares_user_id_fkey(id, username, profile_photo_url)')
        .eq('post_id', postId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List)
        .map((row) => row['users'])
        .whereType<Map<String, dynamic>>()
        .map(RecommendedUser.fromMap)
        .toList();
  }

  Future<List<RecommendedUser>> downloadersOf(String postId, {int limit = 50}) async {
    final data = await _c
        .from('post_downloads')
        .select('user_id, created_at, users!post_downloads_user_id_fkey(id, username, profile_photo_url)')
        .eq('post_id', postId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List)
        .map((row) => row['users'])
        .whereType<Map<String, dynamic>>()
        .map(RecommendedUser.fromMap)
        .toList();
  }
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
  Future<void> unblock(String targetId, String userId) => _c.from('user_blocks').delete().match({'blocked_id': targetId, 'blocker_id': userId});

  Future<bool> isFollowing(String targetId, String userId) async {
    final row = await _c.from('user_follows').select('follower_id').match({'following_id': targetId, 'follower_id': userId}).maybeSingle();
    return row != null;
  }

  Future<bool> isBlocked(String targetId, String userId) async {
    final row = await _c.from('user_blocks').select('blocker_id').match({'blocked_id': targetId, 'blocker_id': userId}).maybeSingle();
    return row != null;
  }

  /// People the user follows, for the "tag friends" picker default list.
  Future<List<Map<String, dynamic>>> followingUsers(String userId, {int limit = 30}) async {
    final rows = await _c
        .from('user_follows')
        .select('users!user_follows_following_id_fkey(id, username, profile_photo_url)')
        .eq('follower_id', userId)
        .limit(limit);
    return (rows as List).map((r) => Map<String, dynamic>.from(r['users'] as Map)).toList();
  }

  /// Username search for the "tag friends" picker, once the person types.
  Future<List<Map<String, dynamic>>> searchUsersByUsername(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return const [];
    final rows = await _c.from('users').select('id, username, profile_photo_url').ilike('username', '%${query.trim()}%').limit(limit);
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Published (non-removed) post count — the "Posts" stat on a profile.
  Future<int> postCount(String userId) async =>
      await _c.from('posts').count(CountOption.exact).eq('author_id', userId).eq('is_removed', false);

  /// Pin/unpin a post to the top of your own profile grid. Pass null to
  /// unpin. Server-side, a post can only be pinned by its own author (see
  /// guard_user_update trigger).
  Future<void> setPinnedPost(String userId, String? postId) =>
      _c.from('users').update({'pinned_post_id': postId}).eq('id', userId);

  /// Close friends: a private list only the owner can see (not visible to
  /// the friend being added), same as Instagram's close friends list.
  Future<List<String>> closeFriendIds(String userId) async {
    final rows = await _c.from('close_friends').select('friend_id').eq('user_id', userId);
    return (rows as List).map((r) => r['friend_id'] as String).toList();
  }

  Future<void> addCloseFriend(String userId, String friendId) =>
      _c.from('close_friends').upsert({'user_id': userId, 'friend_id': friendId});

  Future<void> removeCloseFriend(String userId, String friendId) =>
      _c.from('close_friends').delete().match({'user_id': userId, 'friend_id': friendId});

  Future<List<RecommendedUser>> followersList(String userId, {int limit = 100}) async {
    final data = await _c
        .from('user_follows')
        .select('users!user_follows_follower_id_fkey(id, username, profile_photo_url)')
        .eq('following_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List).map((row) => row['users']).whereType<Map<String, dynamic>>().map(RecommendedUser.fromMap).toList();
  }

  Future<List<RecommendedUser>> followingList(String userId, {int limit = 100}) async {
    final data = await _c
        .from('user_follows')
        .select('users!user_follows_following_id_fkey(id, username, profile_photo_url)')
        .eq('follower_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List).map((row) => row['users']).whereType<Map<String, dynamic>>().map(RecommendedUser.fromMap).toList();
  }

  Future<String> uploadProfileImage(String userId, XFile file, ProfileImageKind kind) =>
      MediaUploadService().uploadProfileImage(userId: userId, image: file, kind: kind);

  /// People [userId] has blocked — backs the "Blocked accounts" list in
  /// Settings, where they can be unblocked one at a time.
  Future<List<RecommendedUser>> blockedUsersList(String userId, {int limit = 200}) async {
    final data = await _c
        .from('user_blocks')
        .select('users!user_blocks_blocked_id_fkey(id, username, profile_photo_url)')
        .eq('blocker_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (data as List).map((row) => row['users']).whereType<Map<String, dynamic>>().map(RecommendedUser.fromMap).toList();
  }

  /// A small, shuffled batch of people [userId] doesn't already follow (and
  /// isn't blocked by/hasn't blocked) — backs the "You may know these
  /// people" row on the home feed.
  Future<List<RecommendedUser>> recommendedUsers(String userId, {int limit = 10}) async {
    final followingRows = await _c.from('user_follows').select('following_id').eq('follower_id', userId);
    final blockedRows = await _c.from('user_blocks').select('blocker_id, blocked_id').or('blocker_id.eq.$userId,blocked_id.eq.$userId');

    final excludeIds = <String>{userId};
    for (final row in (followingRows as List)) {
      excludeIds.add(row['following_id'].toString());
    }
    for (final row in (blockedRows as List)) {
      excludeIds.add(row['blocker_id'].toString());
      excludeIds.add(row['blocked_id'].toString());
    }

    // Over-fetch a bit so we can shuffle client-side for variety across
    // refreshes instead of always showing the same newest users first.
    final data = await _c
        .from('users')
        .select('id, username, profile_photo_url')
        .not('id', 'in', '(${excludeIds.join(',')})')
        .order('created_at', ascending: false)
        .limit(limit * 3);

    final users = (data as List).map((e) => RecommendedUser.fromMap(e as Map<String, dynamic>)).toList()..shuffle();
    return users.take(limit).toList();
  }

  /// "Add Friend" on the recommendations row. Gather's social graph is a
  /// single-sided follow (no separate accept step), so sending a request
  /// simply follows the person — the button just reads "Requested" until
  /// the row refreshes.
  Future<void> sendFriendRequest(String targetId, String userId) async {
    await follow(targetId, userId);
    AnalyticsService.instance.firstActionCompleted(action: 'friend_request_sent');
  }
}

/// Creator monetization: eligibility check, opt-in toggle, and payout
/// PREFERENCES (never full account numbers — see MonetizationSettingsScreen
/// docs). Actual payouts are a manual, admin-reviewed process for now.
class MonetizationRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  Future<Map<String, dynamic>> checkEligibility() async {
    final result = await _c.rpc('check_monetization_eligibility');
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> setOptIn(bool optIn) => _c.rpc('set_monetization_opt_in', params: {'opt_in': optIn});

  Future<Map<String, dynamic>?> loadPayoutPreference(String userId) =>
      _c.from('user_payout_preferences').select().eq('user_id', userId).maybeSingle();

  Future<void> savePayoutPreference({
    required String userId,
    required String provider,
    required String holderName,
    required String maskedReference,
  }) =>
      _c.from('user_payout_preferences').upsert({
        'user_id': userId,
        'provider': provider,
        'holder_name': holderName,
        'masked_reference': maskedReference,
      });

  /// Admin/mod only (RLS-enforced): payout preferences awaiting manual
  /// review, newest first, with the requesting user's basic info embedded.
  Future<List<Map<String, dynamic>>> pendingPayoutReviews() async {
    final result = await _c
        .from('user_payout_preferences')
        .select('*, users(username, email, monetization_status)')
        .eq('status', 'pending_review')
        .order('updated_at', ascending: true);
    return List<Map<String, dynamic>>.from(result as List);
  }

  /// Admin/mod only: sets the payout preference's review status and, on
  /// approval, flips the user's overall monetization_status to approved so
  /// ads actually start showing. Rejecting a payout leaves opt-in as-is but
  /// marks monetization_status rejected so the UI reflects it needs fixing.
  Future<void> reviewPayout({
    required String userId,
    required String status,
    String? notes,
  }) async {
    await _c.from('user_payout_preferences').update({
      'status': status,
      if (notes != null) 'notes': notes,
    }).eq('user_id', userId);
    await _c.from('users').update({
      'monetization_status': status == 'approved' ? 'approved' : 'rejected',
    }).eq('id', userId);
  }
  /// Server validates eligibility itself (never trusts the client), so
  /// this is safe to call speculatively whenever an ad card actually
  /// renders — it silently no-ops if the post's author turns out not to
  /// be an approved, opted-in creator.
  Future<void> logAdImpression(String postId) =>
      _c.rpc('log_ad_impression', params: {'p_post_id': postId});
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

  Future<String> uploadPostVideo(String postId, XFile file) async {
    final mediaService = MediaUploadService();
    final prepared = await mediaService.preparePostVideo(file);
    return mediaService.uploadPostVideo(postId: postId, video: prepared);
  }

  /// [mediaType] is `'image'` or `'video'` — matches the `post_media`
  /// table's `media_type` enum. A post carries at most one media item, so
  /// this clears any existing row of the same type before inserting (keeps
  /// a retried publish idempotent instead of accumulating duplicates).
  Future<void> addPostMedia(String postId, String mediaUrl, {String mediaType = 'image'}) async {
    await _c.from('post_media').delete().eq('post_id', postId).eq('media_type', mediaType);
    await _c.from('post_media').insert({'post_id': postId, 'media_type': mediaType, 'media_url': mediaUrl});
  }
}

class ModerationRepository {
  SupabaseClient get _c => SupabaseConfig.client;
  Future<void> report(Map<String, dynamic> payload) => _c.from('reports').insert(payload);
  Future<List<Map<String, dynamic>>> openReports() async => ((await _c.from('reports').select().eq('status', 'open').order('created_at')) as List).cast<Map<String, dynamic>>();
  Future<void> removePost(String postId, {String? reportId}) => _c.rpc('soft_remove_post', params: {
        'post_id': postId,
        'report_id': reportId,
      });
  Future<void> suspendUser(String userId, {String? reportId, int? durationDays, String? note}) => _c.rpc('suspend_user', params: {
        'target_user_id': userId,
        'report_id': reportId,
        'note': note,
        'duration_days': durationDays,
      });
  Future<void> resolveReport(String reportId) => _c.rpc('resolve_report', params: {'report_id': reportId});

  // ---- Phase 6: Community Moderation ----

  /// The 14 required report categories, in display order.
  static const List<String> reportCategories = [
    'spam',
    'fake_account',
    'harassment',
    'hate_speech',
    'violence',
    'terrorism',
    'child_abuse',
    'adult_content',
    'copyright',
    'scam',
    'impersonation',
    'self_harm',
    'drugs',
    'other',
  ];

  static const Map<String, String> reportCategoryLabels = {
    'spam': 'Spam',
    'fake_account': 'Fake account',
    'harassment': 'Harassment',
    'hate_speech': 'Hate speech',
    'violence': 'Violence',
    'terrorism': 'Terrorism',
    'child_abuse': 'Child abuse',
    'adult_content': 'Adult content',
    'copyright': 'Copyright',
    'scam': 'Scam',
    'impersonation': 'Impersonation',
    'self_harm': 'Self harm',
    'drugs': 'Drugs',
    'other': 'Other',
  };

  Future<void> issueWarning(String userId, {String? reportId, String? note}) => _c.rpc('issue_warning', params: {
        'target_user_id': userId,
        'report_id': reportId,
        'note': note,
      });

  Future<void> addStrike(String userId, {String? reportId, String? note, int severity = 1}) => _c.rpc('add_strike', params: {
        'target_user_id': userId,
        'report_id': reportId,
        'note': note,
        'severity': severity,
      });

  Future<void> banUser(String userId, {String? reportId, String? note}) => _c.rpc('ban_user', params: {
        'target_user_id': userId,
        'report_id': reportId,
        'note': note,
      });

  Future<void> reinstateUser(String userId, {String? note}) => _c.rpc('reinstate_user', params: {
        'target_user_id': userId,
        'note': note,
      });

  Future<String> submitAppeal(String actionId, String message) async =>
      (await _c.rpc('submit_appeal', params: {'action_id': actionId, 'message': message})).toString();

  Future<void> reviewAppeal(String appealId, String decision, {String? resolutionNote}) => _c.rpc('review_appeal', params: {
        'appeal_id': appealId,
        'decision': decision,
        'resolution_note': resolutionNote,
      });

  Future<List<Map<String, dynamic>>> pendingAppeals() async =>
      ((await _c.from('moderation_appeals').select('*, users!moderation_appeals_user_id_fkey(username, email), moderation_actions!moderation_appeals_action_id_fkey(action, note, created_at)').eq('status', 'pending').order('created_at')) as List).cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> myAppeals() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) return const [];
    return ((await _c.from('moderation_appeals').select().eq('user_id', uid).order('created_at', ascending: false)) as List).cast<Map<String, dynamic>>();
  }

  /// Actions taken against the current user (so they know what they can appeal).
  Future<List<Map<String, dynamic>>> myModerationActions() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) return const [];
    return ((await _c.from('moderation_actions').select().eq('target_user_id', uid).order('created_at', ascending: false)) as List).cast<Map<String, dynamic>>();
  }

  Future<String> addModeratorNote({required String targetType, required String targetId, required String note}) async =>
      (await _c.rpc('add_moderator_note', params: {'target_type': targetType, 'target_id': targetId, 'note': note})).toString();

  Future<List<Map<String, dynamic>>> moderatorNotesFor({String? targetUserId, String? targetPostId}) async {
    var q = _c.from('moderator_notes').select();
    if (targetUserId != null) q = q.eq('target_user_id', targetUserId);
    if (targetPostId != null) q = q.eq('target_post_id', targetPostId);
    return ((await q.order('created_at', ascending: false)) as List).cast<Map<String, dynamic>>();
  }

  Future<String> addEvidence({required String reportId, required String fileUrl, String? fileType, String? description}) async =>
      (await _c.rpc('add_evidence', params: {
        'report_id': reportId,
        'file_url': fileUrl,
        'file_type': fileType,
        'description': description,
      })).toString();

  Future<List<Map<String, dynamic>>> evidenceFor(String reportId) async =>
      ((await _c.from('moderation_evidence').select().eq('report_id', reportId).order('created_at')) as List).cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> keywordFilters() async =>
      ((await _c.from('keyword_filters').select().eq('is_active', true).order('created_at', ascending: false)) as List).cast<Map<String, dynamic>>();

  Future<void> addKeywordFilter({required String keyword, String category = 'other', String severity = 'flag'}) => _c.rpc('add_keyword_filter', params: {
        'keyword': keyword,
        'category': category,
        'severity': severity,
      });

  Future<void> removeKeywordFilter(String filterId) => _c.rpc('remove_keyword_filter', params: {'filter_id': filterId});

  Future<List<Map<String, dynamic>>> flaggedMedia() async =>
      ((await _c.from('media_moderation_flags').select().eq('status', 'flagged').order('created_at')) as List).cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> pendingMediaQueue() async =>
      ((await _c.from('media_moderation_flags').select().eq('status', 'pending').order('created_at')) as List).cast<Map<String, dynamic>>();

  Future<void> recordMediaModerationResult(String flagId, String status, {String? provider}) => _c.rpc('record_media_moderation_result', params: {
        'flag_id': flagId,
        'new_status': status,
        'provider': provider,
      });

  Future<Map<String, dynamic>> dashboardSummary() async {
    final rows = await _c.rpc('moderation_dashboard_summary');
    final list = (rows as List).cast<Map<String, dynamic>>();
    return list.isEmpty
        ? {'open_reports': 0, 'pending_appeals': 0, 'flagged_media': 0, 'suspended_users': 0, 'banned_users': 0}
        : list.first;
  }
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

class StoryRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  Future<List<StoryFeedEntry>> storyFeed(String userId) async {
    final data = await _c.rpc('get_story_feed', params: {'p_user_id': userId});
    return (data as List).map((e) => StoryFeedEntry.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<StoryModel>> storiesFor(String authorId) async {
    final data = await _c
        .from('stories')
        .select()
        .eq('author_id', authorId)
        .gt('expires_at', DateTime.now().toIso8601String())
        .order('created_at', ascending: true);
    return (data as List).map((e) => StoryModel.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> markViewed(String storyId) => _c.rpc('mark_story_viewed', params: {'p_story_id': storyId});

  Future<List<StoryAudioTrack>> audioTracks() async {
    final data = await _c.from('story_audio_tracks').select().eq('is_active', true).order('created_at', ascending: false);
    return (data as List).map((e) => StoryAudioTrack.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  Future<Map<String, dynamic>> createStory({
    required String mediaUrl,
    required String mediaType,
    String? audioTrackId,
    String? audioUrl,
    String? audioTitle,
    bool muteOriginalAudio = false,
  }) =>
      _c
          .from('stories')
          .insert({
            'media_url': mediaUrl,
            'media_type': mediaType,
            'audio_track_id': audioTrackId,
            'audio_url': audioUrl,
            'audio_title': audioTitle,
            'mute_original_audio': muteOriginalAudio,
          })
          .select()
          .single();

  Future<void> deleteStory(String storyId) => _c.from('stories').delete().eq('id', storyId);
}

class PrivacyRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  /// Records a consent decision (privacy policy, terms, cookie/storage,
  /// data processing, marketing). Always inserts a new row — consent
  /// history is append-only so we can prove what was agreed to and when.
  Future<void> recordConsent({
    required String consentType,
    required String policyVersion,
    required bool granted,
    Map<String, dynamic> metadata = const {},
  }) =>
      _c.from('consent_records').insert({
        'user_id': SupabaseConfig.currentUserId,
        'consent_type': consentType,
        'policy_version': policyVersion,
        'granted': granted,
        'metadata': metadata,
      });

  Future<List<Map<String, dynamic>>> consentHistory() async =>
      ((await _c.from('consent_records').select().order('recorded_at', ascending: false)) as List)
          .cast<Map<String, dynamic>>();

  /// Latest decision per consent type, e.g. to check whether the user has
  /// already accepted the current privacy policy version.
  Future<Map<String, dynamic>?> latestConsent(String consentType) async {
    final rows = await _c
        .from('latest_consent')
        .select()
        .eq('user_id', SupabaseConfig.currentUserId!)
        .eq('consent_type', consentType)
        .limit(1);
    final list = rows as List;
    return list.isEmpty ? null : Map<String, dynamic>.from(list.first as Map);
  }

  /// Triggers the `data-export` edge function, which assembles the bundle
  /// synchronously and returns the updated request row (status 'ready' with
  /// a signed download URL in file_path, or 'failed' with error_message).
  /// Falls back to the request_data_export() RPC (fire-and-forget, status
  /// stays 'pending') if the function call itself fails — the request is
  /// still recorded either way.
  Future<Map<String, dynamic>> requestDataExport() async {
    try {
      final res = await _c.functions.invoke('data-export');
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      if (data is String) return Map<String, dynamic>.from(jsonDecode(data) as Map);
    } catch (_) {
      // Fall through to the RPC below — the export can be retried/picked
      // up later even if the synchronous call failed (e.g. cold start
      // timeout on a large account).
    }
    final id = await _c.rpc('request_data_export');
    return {'id': id, 'status': 'pending'};
  }

  Future<List<Map<String, dynamic>>> exportRequests() async =>
      ((await _c.from('data_export_requests').select().order('requested_at', ascending: false)) as List)
          .cast<Map<String, dynamic>>();

  Future<String> requestAccountDeletion({String? reason, int graceDays = 14}) async {
    final id = await _c.rpc('request_account_deletion', params: {
      'p_reason': reason,
      'p_grace_days': graceDays,
    });
    return id as String;
  }

  Future<void> cancelAccountDeletion() => _c.rpc('cancel_account_deletion');

  Future<void> updatePrivacySettings(Map<String, dynamic> fields) =>
      _c.from('users').update(fields).eq('id', SupabaseConfig.currentUserId!);

  // Mute list — one-directional, not disclosed to the muted user.
  Future<void> muteUser(String userId) => _c.from('user_mutes').insert({
        'muter_id': SupabaseConfig.currentUserId,
        'muted_id': userId,
      });

  Future<void> unmuteUser(String userId) => _c
      .from('user_mutes')
      .delete()
      .eq('muter_id', SupabaseConfig.currentUserId!)
      .eq('muted_id', userId);

  Future<List<Map<String, dynamic>>> mutedUsers() async {
    final data = await _c
        .from('user_mutes')
        .select('muted_id, created_at, users!user_mutes_muted_id_fkey(username, profile_photo_url)')
        .eq('muter_id', SupabaseConfig.currentUserId!)
        .order('created_at', ascending: false);
    return (data as List).cast<Map<String, dynamic>>();
  }
}

class LegalRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  Future<List<Map<String, dynamic>>> legalFrameworks() async =>
      ((await _c.from('legal_frameworks').select().eq('active', true)) as List).cast<Map<String, dynamic>>();

  /// Files a formal grievance/legal complaint — distinct from the
  /// lightweight peer-to-peer `reports` flow. Used for illegal content,
  /// privacy violations, defamation, etc.
  Future<String> fileComplaint({
    required String complaintType,
    required String description,
    String? legalBasisCode,
    String? targetPostId,
    String? targetUserId,
    List<String> evidenceUrls = const [],
  }) async {
    final row = await _c
        .from('legal_complaints')
        .insert({
          'complainant_id': SupabaseConfig.currentUserId,
          'complaint_type': complaintType,
          'legal_basis_code': legalBasisCode,
          'description': description,
          'target_post_id': targetPostId,
          'target_user_id': targetUserId,
          'evidence_urls': evidenceUrls,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<List<Map<String, dynamic>>> myComplaints() async =>
      ((await _c.from('legal_complaints').select().order('created_at', ascending: false)) as List)
          .cast<Map<String, dynamic>>();

  Future<String> fileAppeal({
    required String statement,
    String? moderationActionId,
    String? contentRemovalActionId,
    String? legalComplaintId,
  }) async {
    final row = await _c
        .from('user_appeals')
        .insert({
          'appellant_id': SupabaseConfig.currentUserId,
          'statement': statement,
          'moderation_action_id': moderationActionId,
          'content_removal_action_id': contentRemovalActionId,
          'legal_complaint_id': legalComplaintId,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<List<Map<String, dynamic>>> myAppeals() async =>
      ((await _c.from('user_appeals').select().order('created_at', ascending: false)) as List)
          .cast<Map<String, dynamic>>();

  Future<String> submitVerification({required String idDocumentType, required String idDocumentUrl}) async {
    final row = await _c
        .from('user_verification_requests')
        .insert({
          'user_id': SupabaseConfig.currentUserId,
          'id_document_type': idDocumentType,
          'id_document_url': idDocumentUrl,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  // --- Admin legal dashboard ---
  Future<List<Map<String, dynamic>>> adminComplaints({String? status}) async {
    var q = _c.from('legal_complaints').select('*, users!legal_complaints_complainant_id_fkey(username)');
    final data = await (status == null ? q : q.eq('status', status)).order('created_at', ascending: false);
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<void> updateComplaintStatus(String complaintId, {required String status, String? resolutionNotes, String? assignedAdminId}) =>
      _c.from('legal_complaints').update({
        'status': status,
        if (resolutionNotes != null) 'resolution_notes': resolutionNotes,
        if (assignedAdminId != null) 'assigned_admin_id': assignedAdminId,
      }).eq('id', complaintId);

  /// Removes a post for a legal reason and logs it to content_removal_actions
  /// (the legal-specific audit trail — distinct from moderation_actions,
  /// since this needs a legal_basis_code and is reportable to regulators).
  /// Reuses the existing soft_remove_post RPC to actually flag the post,
  /// rather than duplicating that logic.
  Future<void> recordContentRemoval({
    String? complaintId,
    required String postId,
    required String reason,
    String? legalBasisCode,
  }) async {
    await _c.rpc('soft_remove_post', params: {
      'post_id': postId,
      'report_id': null,
      'note': complaintId == null ? reason : 'Legal complaint $complaintId: $reason',
    });
    await _c.from('content_removal_actions').insert({
      'complaint_id': complaintId,
      'post_id': postId,
      'removed_by': SupabaseConfig.currentUserId,
      'reason': reason,
      'legal_basis_code': legalBasisCode,
    });
  }

  Future<List<Map<String, dynamic>>> adminAppeals({String? status}) async {
    var q = _c.from('user_appeals').select('*, users!user_appeals_appellant_id_fkey(username)');
    final data = await (status == null ? q : q.eq('status', status)).order('created_at', ascending: false);
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<void> resolveAppeal(String appealId, {required String status, String? reviewNotes}) =>
      _c.from('user_appeals').update({
        'status': status,
        'review_notes': reviewNotes,
        'reviewed_by': SupabaseConfig.currentUserId,
        'resolved_at': DateTime.now().toIso8601String(),
      }).eq('id', appealId);

  Future<List<Map<String, dynamic>>> legalDataRequests({String? status}) async {
    var q = _c.from('legal_data_requests').select();
    final data = await (status == null ? q : q.eq('status', status)).order('received_at', ascending: false);
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<void> logLegalDataRequest({
    required String requestingAuthority,
    required String requestDetails,
    String? authorityContact,
    String? legalBasisCode,
    String? referenceNumber,
    String? targetUserId,
  }) =>
      _c.from('legal_data_requests').insert({
        'requesting_authority': requestingAuthority,
        'authority_contact': authorityContact,
        'legal_basis_code': legalBasisCode,
        'reference_number': referenceNumber,
        'target_user_id': targetUserId,
        'request_details': requestDetails,
      });

  Future<void> respondToLegalDataRequest(String requestId, {required String status, String? responseNotes}) =>
      _c.from('legal_data_requests').update({
        'status': status,
        'response_notes': responseNotes,
        'handled_by': SupabaseConfig.currentUserId,
        'responded_at': DateTime.now().toIso8601String(),
      }).eq('id', requestId);

  Future<List<Map<String, dynamic>>> adminVerificationRequests({String? status}) async {
    var q = _c.from('user_verification_requests').select('*, users!user_verification_requests_user_id_fkey(username)');
    final data = await (status == null ? q : q.eq('status', status)).order('submitted_at', ascending: false);
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<void> reviewVerification(String requestId, {required String status, String? notes}) =>
      _c.from('user_verification_requests').update({
        'status': status,
        'review_notes': notes,
        'reviewed_by': SupabaseConfig.currentUserId,
        'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', requestId);
}
