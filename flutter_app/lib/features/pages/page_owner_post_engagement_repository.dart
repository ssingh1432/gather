import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_client.dart';

class PageOwnerPostEngagementRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  Future<Map<String, dynamic>> getEngagement(String postId) async {
    final likes = await _c.from('page_post_likes').select('user_id').eq('post_id', postId);
    final comments = await _c.from('page_post_comments').select('id').eq('post_id', postId);
    final shares = await _c.from('page_post_shares').select('id').eq('post_id', postId);
    final uid = SupabaseConfig.currentUserId;
    return {
      'likes': (likes as List).length,
      'comments': (comments as List).length,
      'shares': (shares as List).length,
      'liked': uid != null && (likes as List).any((r) => (r as Map)['user_id'] == uid),
    };
  }

  Future<void> setLike(String postId, bool liked) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) throw StateError('Sign in to like posts.');
    if (liked) {
      try {
        await _c.from('page_post_likes').insert({'post_id': postId, 'user_id': uid});
      } on PostgrestException catch (e) {
        final m = e.message.toLowerCase();
        if (!m.contains('duplicate') && !m.contains('unique')) rethrow;
      }
    } else {
      await _c.from('page_post_likes').delete().match({'post_id': postId, 'user_id': uid});
    }
  }

  Future<List<Map<String, dynamic>>> listComments(String postId) async {
    final rows = await _c.from('page_post_comments').select('id,post_id,user_id,parent_comment_id,content,created_at,updated_at,users!page_post_comments_user_id_fkey(username,display_name,profile_photo_url)').eq('post_id', postId).order('created_at', ascending: true);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> addComment(String postId, String content, {String? parentCommentId}) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) throw StateError('Sign in to comment.');
    final text = content.trim();
    if (text.isEmpty || text.length > 2000) throw ArgumentError('Comment must be 1–2000 characters.');
    await _c.from('page_post_comments').insert({'post_id': postId, 'user_id': uid, 'content': text, 'parent_comment_id': parentCommentId});
  }

  Future<void> recordShare(String postId) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) throw StateError('Sign in to share posts.');
    await _c.from('page_post_shares').insert({'post_id': postId, 'user_id': uid});
  }

  Future<void> report(String postId, String category, {String? reason}) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) throw StateError('Sign in to report posts.');
    await _c.from('page_post_reports').insert({
      'post_id': postId,
      'reporter_id': uid,
      'category': category,
      'reason': reason?.trim().isEmpty == true ? null : reason?.trim(),
    });
  }
}
