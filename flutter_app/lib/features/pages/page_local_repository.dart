import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

/// A single visitor-post media attachment selected on-device, pending
/// upload. `mediaType` must be one of the shared `media_type` enum values:
/// image, video, document.
class VisitorPostMediaUpload {
  const VisitorPostMediaUpload({
    required this.bytes,
    required this.filename,
    required this.mimeType,
    required this.mediaType,
  });

  final Uint8List bytes;
  final String filename;
  final String mimeType;
  final String mediaType;
}

/// Page-only data access for visitor posts (including their media, likes,
/// comments, and shares), Page rules, audience moderation, and owner
/// lifecycle actions.
class PageLocalRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  static const _visitorPostSelect =
      'id, page_id, author_id, content, content_type, media, event_id, status, created_at, '
      'users!page_visitor_posts_author_id_fkey(username, display_name, profile_photo_url), '
      'pages!page_visitor_posts_page_id_fkey(logo_url), '
      'page_events!page_visitor_posts_event_id_fkey(id, title, start_time, location, cover_url), '
      'like_count:page_visitor_post_likes(count), '
      'comment_count:page_visitor_post_comments(count), '
      'share_count:page_visitor_post_shares(count)';

  Future<List<Map<String, dynamic>>> listVisitorPosts(String pageId) async {
    final rows = await _c
        .from('page_visitor_posts')
        .select(_visitorPostSelect)
        .eq('page_id', pageId)
        .eq('status', 'published')
        .order('created_at', ascending: false);
    final posts = (rows as List).cast<Map<String, dynamic>>();
    await _attachLikedByMe(posts);
    return posts;
  }

  Future<List<Map<String, dynamic>>> listPendingVisitorPosts(String pageId) async {
    final rows = await _c.from('page_visitor_posts').select('id, page_id, author_id, content, content_type, media, event_id, status, created_at, users!page_visitor_posts_author_id_fkey(username, display_name, profile_photo_url)').eq('page_id', pageId).eq('status', 'pending').order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Marks each post with whether the current user has liked it. Supabase's
  /// nested-select count aggregates can't also be filtered per-user, so
  /// "did I like this" is resolved with one extra targeted query rather than
  /// per-post round trips.
  Future<void> _attachLikedByMe(List<Map<String, dynamic>> posts) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null || posts.isEmpty) {
      for (final p in posts) {
        p['liked_by_me'] = false;
      }
      return;
    }
    final ids = posts.map((p) => p['id'] as String).toList();
    final liked = await _c.from('page_visitor_post_likes').select('post_id').eq('user_id', uid).inFilter('post_id', ids);
    final likedIds = (liked as List).map((r) => (r as Map)['post_id'] as String).toSet();
    for (final p in posts) {
      p['liked_by_me'] = likedIds.contains(p['id']);
    }
  }

  /// Creates a visitor post. At most one of `media` (image/video/document
  /// attachments, all the same [VisitorPostMediaUpload.mediaType]) or
  /// `eventId` (an existing Page event to attach) should be provided,
  /// matching the single `content_type` the row is tagged with.
  ///
  /// Media uploads happen in two steps: the post row is created first
  /// (initially with an empty `media` array), because the storage bucket's
  /// RLS policy requires a page_visitor_posts row to already exist at the
  /// `{page_id}/{post_id}/...` path before it will accept an upload. Once
  /// the files are uploaded, the row is updated with their public URLs.
  Future<void> createVisitorPost(
    String pageId,
    String content, {
    List<VisitorPostMediaUpload> media = const [],
    String? eventId,
  }) async {
    final uid = SupabaseConfig.currentUserId;
    final trimmed = content.trim();
    if (uid == null) throw StateError('Sign in to post on a Page.');
    if (trimmed.isEmpty && media.isEmpty && eventId == null) {
      throw ArgumentError('Post cannot be empty.');
    }
    if (trimmed.length > 5000) throw ArgumentError('Post is too long.');
    if (media.length > 10) throw ArgumentError('You can attach up to 10 files.');

    final contentType = eventId != null ? 'event' : (media.isNotEmpty ? media.first.mediaType : 'text');

    final inserted = await _c.from('page_visitor_posts').insert({
      'page_id': pageId,
      'author_id': uid,
      'content': trimmed,
      'content_type': contentType,
      'event_id': eventId,
    }).select('id').single();
    final postId = inserted['id'] as String;

    if (media.isEmpty) return;

    try {
      final uploaded = <Map<String, String>>[];
      for (var i = 0; i < media.length; i++) {
        final item = media[i];
        final path = '$pageId/$postId/${DateTime.now().microsecondsSinceEpoch}_$i-${item.filename}';
        await _c.storage.from('page-visitor-media').uploadBinary(
              path,
              item.bytes,
              fileOptions: FileOptions(contentType: item.mimeType, upsert: false),
            );
        final publicUrl = _c.storage.from('page-visitor-media').getPublicUrl(path);
        uploaded.add({'url': publicUrl, 'type': item.mediaType});
      }
      await _c.from('page_visitor_posts').update({'media': uploaded}).eq('id', postId);
    } catch (e) {
      // Best-effort cleanup: an author-owned post with a failed attachment
      // is more confusing than no post at all, so remove it and surface
      // the failure instead of leaving a half-uploaded post behind.
      await _c.from('page_visitor_posts').delete().eq('id', postId);
      rethrow;
    }
  }

  Future<bool> toggleVisitorPostLike(String postId, {required bool currentlyLiked}) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) throw StateError('Sign in to like posts.');
    if (currentlyLiked) {
      await _c.from('page_visitor_post_likes').delete().eq('post_id', postId).eq('user_id', uid);
      return false;
    } else {
      await _c.from('page_visitor_post_likes').insert({'post_id': postId, 'user_id': uid});
      return true;
    }
  }

  Future<List<Map<String, dynamic>>> listVisitorPostComments(String postId) async {
    final rows = await _c
        .from('page_visitor_post_comments')
        .select('id, post_id, user_id, content, created_at, users!page_visitor_post_comments_user_id_fkey(username, display_name, profile_photo_url)')
        .eq('post_id', postId)
        .order('created_at');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> addVisitorPostComment(String postId, String content) async {
    final uid = SupabaseConfig.currentUserId;
    final trimmed = content.trim();
    if (uid == null) throw StateError('Sign in to comment.');
    if (trimmed.isEmpty) throw ArgumentError('Comment cannot be empty.');
    if (trimmed.length > 2000) throw ArgumentError('Comment is too long.');
    await _c.from('page_visitor_post_comments').insert({'post_id': postId, 'user_id': uid, 'content': trimmed});
  }

  Future<void> recordVisitorPostShare(String postId) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) return;
    await _c.from('page_visitor_post_shares').insert({'post_id': postId, 'user_id': uid});
  }

  Future<void> moderateVisitorPost(String postId, String status) async {
    if (!{'published', 'hidden', 'removed'}.contains(status)) throw ArgumentError('Invalid visitor post status.');
    await _c.from('page_visitor_posts').update({'status': status}).eq('id', postId);
  }

  Future<List<Map<String, dynamic>>> listRules(String pageId) async {
    final rows = await _c.from('page_rules').select().eq('page_id', pageId).eq('active', true).order('sort_order').order('created_at');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> saveRule({String? id, required String pageId, required String title, required String body, required int sortOrder}) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) throw StateError('Sign in to manage Page rules.');
    final payload = {'page_id': pageId, 'title': title.trim(), 'body': body.trim(), 'sort_order': sortOrder, 'active': true, 'created_by': uid};
    if (id == null) {
      await _c.from('page_rules').insert(payload);
    } else {
      await _c.from('page_rules').update(payload).eq('id', id);
    }
  }

  Future<void> deactivateRule(String id) async => _c.from('page_rules').update({'active': false}).eq('id', id);

  Future<Map<String, dynamic>> getVisitorPostingSettings(String pageId) async => _c.from('pages').select('allow_visitor_posts, visitor_posts_require_approval').eq('id', pageId).single();

  Future<void> updateVisitorPostingSettings(String pageId, {required bool enabled, required bool requireApproval}) async {
    await _c.from('pages').update({'allow_visitor_posts': enabled, 'visitor_posts_require_approval': requireApproval}).eq('id', pageId);
  }

  /// Removes a follower through the server-side Page permission check.
  /// Only users with manage_roles (owner/manager by default) can perform it.
  Future<void> removeFollower(String pageId, String userId) async {
    await _c.rpc('remove_page_follower', params: {
      'p_page_id': pageId,
      'p_user_id': userId,
    });
  }

  Future<bool> isPageOwner(String pageId) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) return false;
    final row = await _c.from('page_roles').select('role').eq('page_id', pageId).eq('user_id', uid).maybeSingle();
    return row?['role'] == 'owner';
  }

  /// Owner-only lifecycle actions. These stay Page-local so no shared Gather
  /// repository needs to know about Page-specific destructive operations.
  Future<void> deactivatePage(String pageId) => _c.rpc('deactivate_page', params: {'p_page_id': pageId});

  Future<void> reactivatePage(String pageId) => _c.rpc('reactivate_page', params: {'p_page_id': pageId});

  Future<void> deletePagePermanently(String pageId) => _c.rpc('delete_page_permanently', params: {'p_page_id': pageId});
}
