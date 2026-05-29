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
  final client = SupabaseConfig.maybeClient;
  if (client == null) return [];

  final uid = client.auth.currentUser?.id;
  final repo = ref.watch(feedRepositoryProvider);
  if (uid == null) return repo.publicFeed(page: page);
  return repo.homeFeed(uid, page: page);
});
