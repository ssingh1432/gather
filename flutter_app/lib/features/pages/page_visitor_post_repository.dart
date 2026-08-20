import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';

class PageVisitorPostRepository {
  static const bucket = 'page-visitor-media';
  static const maxBytes = 25 * 1024 * 1024;
  SupabaseClient get _c => SupabaseConfig.client;

  Future<int> _countRows(String table, String postId) async {
    final rows = await _c.from(table).select('post_id').eq('post_id', postId);
    return (rows as List).length;
  }

  Future<List<Map<String, dynamic>>> listVisitorPosts(String pageId) async {
    final rows = await _c.from('page_visitor_posts').select('id,page_id,author_id,content,status,content_type,media,event_id,created_at,users!page_visitor_posts_author_id_fkey(username,display_name,profile_photo_url),page_events(id,title,location,start_time)').eq('page_id', pageId).eq('status', 'published').order('created_at', ascending: false);
    final list = (rows as List).cast<Map<String, dynamic>>();
    for (final row in list) {
      row['like_count'] = await _countRows('page_visitor_post_likes', row['id'] as String);
      row['comment_count'] = await _countRows('page_visitor_post_comments', row['id'] as String);
    }
    return list;
  }

  Future<PostModel?> getPublishedPostForHome(String postId) async {
    final row = await _c.from('page_visitor_posts')
        .select('id,page_id,author_id,content,status,content_type,media,created_at,users!page_visitor_posts_author_id_fkey(username,profile_photo_url),pages!page_visitor_posts_page_id_fkey(name)')
        .eq('id', postId).eq('status', 'published').maybeSingle();
    if (row == null) return null;
    final media = (row['media'] as List?) ?? const [];
    final page = row['pages'] as Map<String, dynamic>?;
    final author = row['users'] as Map<String, dynamic>?;
    final mediaItems = media.whereType<Map>().map((item) => PostMediaItem.fromMap({
      'media_url': item['url'],
      'media_type': item['type'] ?? row['content_type'] ?? 'image',
      'thumbnail_url': item['thumbnail_url'],
    })).whereType<PostMediaItem>().toList();
    return PostModel(
      id: row['id'].toString(), authorId: row['author_id'].toString(),
      authorUsername: author?['username'] as String?, authorAvatarUrl: author?['profile_photo_url'] as String?,
      communityId: row['page_id'].toString(), textContent: row['content'] as String? ?? '',
      createdAt: DateTime.parse(row['created_at'].toString()), mediaItems: mediaItems,
      imageUrl: mediaItems.isNotEmpty ? mediaItems.first.mediaUrl : null,
      mediaType: mediaItems.isNotEmpty ? mediaItems.first.mediaType : row['content_type'] as String?,
      location: 'Posted on ${page?['name'] ?? 'Page'}', contentType: 'page_visitor', visibility: 'public',
    );
  }

  Future<List<Map<String, dynamic>>> listEvents(String pageId) async =>
      (await _c.from('page_events').select('id,title,location,start_time,end_time').isFilter('deleted_at', null).eq('page_id', pageId).order('start_time')).cast<Map<String, dynamic>>();

  Future<String> createVisitorPost({required String pageId, required String content, required String contentType, List<Map<String, dynamic>> media = const [], String? eventId}) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) throw const PageVisitorMediaException('Sign in to post on a Page.');
    final trimmed = content.trim();
    if (trimmed.length > 5000) throw const PageVisitorMediaException('Post is too long.');
    if (trimmed.isEmpty && media.isEmpty && eventId == null) throw const PageVisitorMediaException('Add text, media, or an event.');
    try {
      final row = await _c.from('page_visitor_posts').insert({
        'page_id': pageId,
        'content': trimmed,
        'content_type': contentType,
        'media': media,
        'event_id': eventId,
      }).select('id').single();
      return row['id'] as String;
    } on PostgrestException catch (e) {
      throw PageVisitorMediaException(_friendlyPostError(e));
    }
  }

  Future<String> uploadMedia({required String pageId, required String postId, required List<int> bytes, required String mimeType, required String fileName}) async {
    if (bytes.isEmpty) throw const PageVisitorMediaException('The selected file is empty.');
    if (bytes.length > maxBytes) throw const PageVisitorMediaException('File must be 25 MB or smaller.');
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$pageId/$postId/$safe';
    try {
      await _c.storage.from(bucket).uploadBinary(path, Uint8List.fromList(bytes), fileOptions: FileOptions(contentType: mimeType, cacheControl: '31536000', upsert: false));
      return _c.storage.from(bucket).getPublicUrl(path);
    } on StorageException catch (e) {
      throw PageVisitorMediaException('${_friendlyStorageError(e)} ($mimeType)');
    }
  }

  Future<void> updateMedia(String postId, List<Map<String, dynamic>> media) async {
    try {
      await _c.from('page_visitor_posts').update({'media': media}).eq('id', postId).select('id').single();
    } on PostgrestException catch (e) {
      throw PageVisitorMediaException(_friendlyPostError(e));
    }
  }

  Future<void> deleteVisitorPost(String postId) => _c.from('page_visitor_posts').delete().eq('id', postId);

  Future<void> deleteVisitorPostWithMedia({required String pageId, required String postId}) async {
    try {
      final files = await _c.storage.from(bucket).list(path: '$pageId/$postId');
      if (files.isNotEmpty) await _c.storage.from(bucket).remove([for (final file in files) '$pageId/$postId/${file.name}']);
    } catch (_) {}
    await deleteVisitorPost(postId);
  }

  Future<bool> getLikeState(String postId, String userId) async => (await _c.from('page_visitor_post_likes').select('post_id').match({'post_id': postId, 'user_id': userId}).maybeSingle()) != null;
  Future<void> setLike(String postId, bool liked) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) throw StateError('Sign in to like posts.');
    if (liked) await _c.from('page_visitor_post_likes').upsert({'post_id': postId, 'user_id': uid});
    else await _c.from('page_visitor_post_likes').delete().match({'post_id': postId, 'user_id': uid});
  }

  Future<List<Map<String, dynamic>>> listComments(String postId) async {
    final rows = await _c.from('page_visitor_post_comments')
        .select('id,post_id,user_id,parent_comment_id,content,created_at,updated_at,users!page_visitor_post_comments_user_id_fkey(username,display_name,profile_photo_url)')
        .eq('post_id', postId)
        .order('created_at', ascending: true);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> addComment(String postId, String pageId, String content, {String? parentCommentId}) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) throw StateError('Sign in to comment.');
    final text = content.trim();
    if (text.isEmpty || text.length > 2000) throw ArgumentError('Comment must be 1–2000 characters.');
    if (parentCommentId != null) {
      final parent = await _c.from('page_visitor_post_comments').select('id,post_id').eq('id', parentCommentId).maybeSingle();
      if (parent == null || parent['post_id'] != postId) throw ArgumentError('Invalid comment reply.');
    }
    await _c.from('page_visitor_post_comments').insert({'post_id': postId, 'user_id': uid, 'content': text, 'parent_comment_id': parentCommentId});
  }

  Future<int> commentCount(String postId) async => _countRows('page_visitor_post_comments', postId);
  Future<void> deleteComment(String commentId) => _c.from('page_visitor_post_comments').delete().eq('id', commentId);
  Future<void> recordShare(String postId, String userId) => _c.from('page_visitor_post_shares').insert({'post_id': postId, 'user_id': userId});

  static String _friendlyPostError(PostgrestException e) {
    final message = e.message.toLowerCase();
    if (message.contains('page managers must publish page-authored posts')) return 'This account manages the Page. Use a Page-authored post instead of a visitor post.';
    if (message.contains('visitor posts are not enabled')) return 'Visitor posts are disabled for this Page.';
    if (message.contains('you must follow this page')) return 'Follow this Page before posting on it.';
    if (message.contains('authentication is required')) return 'Sign in to post on a Page.';
    if (message.contains('row-level') || message.contains('permission') || message.contains('policy') || message.contains('not authorized')) return 'You do not have permission to create or update this Page post. Make sure you follow the Page.';
    if (message.contains('content_type') || message.contains('check constraint')) return 'This Page post contains an unsupported content combination.';
    if (message.contains('event_id') || message.contains('foreign key')) return 'The selected Page event is no longer available.';
    if (message.contains('duplicate') || message.contains('already exists')) return 'One of the selected attachments is already being used by this Page post.';
    return 'The Page post could not be saved. Please try again.';
  }

  static String _friendlyStorageError(StorageException e) {
    final message = e.message.toLowerCase();
    if (message.contains('row-level') || message.contains('permission') || message.contains('unauthorized') || message.contains('forbidden')) return 'You do not have permission to upload media to this Page. Make sure you follow the Page.';
    if (message.contains('too large') || message.contains('entitytoolarge') || message.contains('size')) return 'This file is larger than the 25 MB limit.';
    if (message.contains('mime') || message.contains('type') || message.contains('content type')) return 'This file type is not supported by Page media.';
    if (message.contains('already exists') || message.contains('duplicate')) return 'A file with this name is already attached to this Page post. Rename the file and try again.';
    return 'The media upload failed. Please try again.';
  }

  static String friendlyUnexpectedError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('permission') || message.contains('unauthorized') || message.contains('forbidden') || message.contains('row-level')) return 'You do not have permission to create this Page post. Make sure you follow the Page.';
    if (message.contains('too large') || message.contains('entitytoolarge') || message.contains('size')) return 'One of the selected files is larger than the 25 MB limit.';
    if (message.contains('mime') || message.contains('content type') || message.contains('unsupported')) return 'One of the selected files is not supported by Page media.';
    if (message.contains('event') && message.contains('foreign key')) return 'The selected Page event is no longer available.';
    if (message.contains('network') || message.contains('socket') || message.contains('connection')) return 'The network connection failed while saving the Page post. Please try again.';
    if (message.contains('out of memory') || message.contains('memory')) return 'The selected media is too large to process on this device. Remove a large file and try again.';
    return 'The Page post could not be saved. Please try again.';
  }
}

class PageVisitorMediaException implements Exception {
  const PageVisitorMediaException(this.message);
  final String message;
  @override
  String toString() => message;
}
