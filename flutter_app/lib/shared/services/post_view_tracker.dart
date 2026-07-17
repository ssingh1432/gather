import '../../core/supabase_client.dart';

/// Fires `increment_post_view` at most once per post per app session
/// (matches how view counts work everywhere — repeatedly scrolling past
/// the same post shouldn't inflate its count).
class PostViewTracker {
  PostViewTracker._();
  static final PostViewTracker instance = PostViewTracker._();

  final Set<String> _counted = {};

  void maybeCount(String postId) {
    if (_counted.contains(postId)) return;
    _counted.add(postId);
    SupabaseConfig.maybeClient?.rpc('increment_post_view', params: {'p_post_id': postId}).catchError((_) {
      // Best-effort — a missed view count is not worth surfacing an error.
      _counted.remove(postId);
    });
  }
}
