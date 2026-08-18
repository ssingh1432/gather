import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_client.dart';

class PageVisitorPostRepository {
  static const bucket = 'page-visitor-media';
  static const maxBytes = 25 * 1024 * 1024;
  SupabaseClient get _c => SupabaseConfig.client;

  Future<int> _countRows(String table, String postId) async {
    final rows = await _c.from(table).select('post_id').eq('post_id', postId);
    return (rows as List).length;
  }

  Future<List<Map<String, dynamic>>> listVisitorPosts(String pageId) async {
    final rows = await _c
        .from('page_visitor_posts')
        .select('id,page_id,author_id,content,status,content_type,media,event_id,created_at,users!page_visitor_posts_author_id_fkey(username,display_name,profile_photo_url),page_events(id,title,location,start_time)')
        .eq('page_id', pageId)
        .eq('status', 'published')
        .order('created_at', ascending: false);
    final list = (rows as List).cast<Map<String, dynamic>>();
    for (final row in list) {
      row['like_count'] = await _countRows('page_visitor_post_likes', row['id'] as String);
      row['comment_count'] = await _countRows('page_visitor_post_comments', row['id'] as String);
    }
    return list;
  }

  Future<List<Map<String, dynamic>>> listEvents(String pageId) async =>
      (await _c.from('page_events').select('id,title,location,start_time,end_time').eq('page_id', pageId).isFilter('deleted_at', null).order('start_time')).cast<Map<String, dynamic>>();

  Future<String> createVisitorPost({required String pageId, required String content, required String contentType, List<Map<String, dynamic>> media = const [], String? eventId}) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) throw StateError('Sign in to post on a Page.');
    final trimmed = content.trim();
    if (trimmed.length > 5000) throw ArgumentError('Post is too long.');
    if (trimmed.isEmpty && media.isEmpty && eventId == null) throw ArgumentError('Add text, media, or an event.');
    final row = await _c.from('page_visitor_posts').insert({'page_id': pageId, 'author_id': uid, 'content': trimmed, 'content_type': contentType, 'media': media, 'event_id': eventId}).select('id').single();
    return row['id'] as String;
  }

  Future<String> uploadMedia({required String pageId, required String postId, required List<int> bytes, required String mimeType, required String fileName}) async {
    if (bytes.length > maxBytes) throw const PageVisitorMediaException('File must be 25 MB or smaller.');
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$pageId/$postId/$safe';
    try {
      await _c.storage.from(bucket).uploadBinary(
        path,
        Uint8List.fromList(bytes),
        fileOptions: FileOptions(contentType: mimeType, cacheControl: '31536000', upsert: false),
      );
      return _c.storage.from(bucket).getPublicUrl(path);
    } on StorageException catch (e) {
      throw PageVisitorMediaException(_friendlyStorageError(e));
    }
  }

  Future<void> updateMedia(String postId, List<Map<String, dynamic>> media) => _c.from('page_visitor_posts').update({'media': media}).eq('id', postId);

  Future<void> deleteVisitorPost(String postId) => _c.from('page_visitor_posts').delete().eq('id', postId);

  Future<void> deleteVisitorPostWithMedia({required String pageId, required String postId}) async {
    try {
      final files = await _c.storage.from(bucket).list(path: '$pageId/$postId');
      if (files.isNotEmpty) {
        await _c.storage.from(bucket).remove([
          for (final file in files) '$pageId/$postId/${file.name}',
        ]);
      }
    } catch (_) {
      // Cleanup is best-effort; never expose storage details to users.
    }
    await deleteVisitorPost(postId);
  }

  Future<bool> getLikeState(String postId, String userId) async => (await _c.from('page_visitor_post_likes').select('post_id').match({'post_id': postId, 'user_id': userId}).maybeSingle()) != null;

  Future<void> setLike(String postId, bool liked) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) throw StateError('Sign in to like posts.');
    if (liked) {
      await _c.from('page_visitor_post_likes').upsert({'post_id': postId, 'user_id': uid});
    } else {
      await _c.from('page_visitor_post_likes').delete().match({'post_id': postId, 'user_id': uid});
    }
  }

  Future<List<Map<String, dynamic>>> listComments(String postId) async =>
      (await _c.from('page_visitor_post_comments').select('id,post_id,user_id,content,created_at,users!page_visitor_post_comments_user_id_fkey(username,display_name,profile_photo_url)').eq('post_id', postId).order('created_at')).cast<Map<String, dynamic>>();

  Future<void> addComment(String postId, String pageId, String content) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) throw StateError('Sign in to comment.');
    final text = content.trim();
    if (text.isEmpty || text.length > 2000) throw ArgumentError('Comment must be 1–2000 characters.');
    await _c.from('page_visitor_post_comments').insert({'post_id': postId, 'user_id': uid, 'content': text});
  }

  Future<int> commentCount(String postId) async => await _countRows('page_visitor_post_comments', postId);
  Future<void> deleteComment(String commentId) => _c.from('page_visitor_post_comments').delete().eq('id', commentId);
  Future<void> recordShare(String postId, String userId) => _c.from('page_visitor_post_shares').insert({'post_id': postId, 'user_id': userId});

  static String _friendlyStorageError(StorageException e) {
    final message = e.message.toLowerCase();
    if (message.contains('row-level') || message.contains('permission') || message.contains('unauthorized') || message.contains('forbidden')) {
      return 'You do not have permission to upload media to this Page. Make sure you follow the Page.';
    }
    if (message.contains('too large') || message.contains('entitytoolarge') || message.contains('size')) {
      return 'This file is larger than the 25 MB limit.';
    }
    if (message.contains('mime') || message.contains('type')) {
      return 'This file type is not supported.';
    }
    return 'The media upload failed. Please try again.';
  }
}

class PageVisitorMediaException implements Exception {
  const PageVisitorMediaException(this.message);
  final String message;

  @override
  String toString() => message;
}
