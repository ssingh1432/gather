import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

/// Performs Page post writes that must prove the target row was actually
/// updated. PostgREST UPDATE without select() can otherwise return normally
/// when zero rows match, which made Page publishing appear successful while
/// leaving a draft behind.
class PagePostPublishService {
  SupabaseClient get _client => SupabaseConfig.client;

  Future<Map<String, dynamic>> updatePagePost(
    String postId,
    Map<String, dynamic> patch,
  ) async {
    try {
      return await _client
          .from('page_posts')
          .update(patch)
          .eq('id', postId)
          .select()
          .single();
    } on PostgrestException {
      rethrow;
    }
  }
}
