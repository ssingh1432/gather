import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

/// Page-only data access for visitor posts, Page rules, and audience moderation.
class PageLocalRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  Future<List<Map<String, dynamic>>> listVisitorPosts(String pageId) async {
    final rows = await _c.from('page_visitor_posts').select('id, page_id, author_id, content, status, created_at, users!page_visitor_posts_author_id_fkey(username, display_name, profile_photo_url)').eq('page_id', pageId).eq('status', 'published').order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> listPendingVisitorPosts(String pageId) async {
    final rows = await _c.from('page_visitor_posts').select('id, page_id, author_id, content, status, created_at, users!page_visitor_posts_author_id_fkey(username, display_name, profile_photo_url)').eq('page_id', pageId).eq('status', 'pending').order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> createVisitorPost(String pageId, String content) async {
    final uid = SupabaseConfig.currentUserId;
    final trimmed = content.trim();
    if (uid == null) throw StateError('Sign in to post on a Page.');
    if (trimmed.isEmpty) throw ArgumentError('Post cannot be empty.');
    if (trimmed.length > 5000) throw ArgumentError('Post is too long.');
    await _c.from('page_visitor_posts').insert({'page_id': pageId, 'author_id': uid, 'content': trimmed});
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
}
