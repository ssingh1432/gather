/// Guards against out-of-order async search responses — the actual bug
/// behind "Tag Friends is unreliable" (requirement #10): if the user
/// types "a", "al", "ali", "alic", "alice" quickly, each keystroke
/// (after debouncing) kicks off its own search, and slower networks make
/// no guarantee they resolve in the order they were sent. Without this,
/// a slow "a" response landing after a fast "alice" response would
/// silently replace the correct results with a page of everyone whose
/// name contains "a".
///
/// Pulled out of create_post_screen.dart's _pickFriends() into its own
/// file specifically so this piece of logic — the one with an actual
/// race condition to get right — is unit-testable without a Flutter
/// widget harness or a Supabase mock. See tag_friend_search_controller_test.dart.
class TagFriendSearchController {
  int _generation = 0;

  /// Runs [fetch] for [query]. Returns its result only if no newer
  /// [search] call has been started by the time [fetch] resolves;
  /// returns null if this call has been superseded, so the caller knows
  /// to discard it rather than render stale results. A superseded call
  /// that *fails* is also swallowed (returns null, doesn't throw) for
  /// the same reason — a slow "a" request erroring out after "alice"
  /// already resolved successfully must not clobber those results with
  /// a spurious error state.
  Future<List<Map<String, dynamic>>?> search(
    String query,
    Future<List<Map<String, dynamic>>> Function(String query) fetch,
  ) async {
    final myGeneration = ++_generation;
    try {
      final results = await fetch(query);
      if (myGeneration != _generation) return null; // superseded — discard
      return results;
    } catch (_) {
      if (myGeneration != _generation) return null; // superseded — swallow the stale error too
      rethrow;
    }
  }
}
