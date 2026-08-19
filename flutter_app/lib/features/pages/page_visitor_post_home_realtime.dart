import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_client.dart';

class PageVisitorHomeRealtimeEvent {
  const PageVisitorHomeRealtimeEvent({required this.postId, required this.pageId});
  final String postId;
  final String pageId;
}

/// Page-only realtime bridge for Command 4. The shared normal-post realtime
/// service is intentionally left untouched.
class PageVisitorPostHomeRealtime {
  final _controller = StreamController<PageVisitorHomeRealtimeEvent>.broadcast();
  RealtimeChannel? _channel;

  Stream<PageVisitorHomeRealtimeEvent> subscribe() {
    final client = SupabaseConfig.maybeClient;
    if (client == null) return _controller.stream;
    _channel = client.channel('public:page-visitor-home-live')
      .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'page_visitor_posts', callback: _handle)
      .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'page_visitor_posts', callback: _handle)
      .subscribe();
    return _controller.stream;
  }

  void _handle(PostgresChangePayload payload) {
    final record = payload.newRecord;
    if (record['status'] != 'published') return;
    final postId = record['id']?.toString();
    final pageId = record['page_id']?.toString();
    if (postId == null || pageId == null) return;
    _controller.add(PageVisitorHomeRealtimeEvent(postId: postId, pageId: pageId));
  }

  void dispose() {
    final channel = _channel;
    if (channel != null) SupabaseConfig.maybeClient?.removeChannel(channel);
    _controller.close();
  }
}
