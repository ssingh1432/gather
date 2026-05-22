import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../../features/data/repositories.dart';

final authServiceProvider = Provider((_) => AuthService());
final authStateProvider = StreamProvider<AuthState>((ref) => ref.watch(authServiceProvider).authChanges());
final feedRepositoryProvider = Provider((_) => FeedRepository());

final homeFeedProvider = FutureProvider.family<List<PostModel>, int>((ref, page) async {
  final uid = SupabaseConfig.client.auth.currentUser?.id;
  if (uid == null) return [];
  return ref.watch(feedRepositoryProvider).homeFeed(uid, page: page);
});
