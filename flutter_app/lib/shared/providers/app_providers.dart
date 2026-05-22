import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../../features/data/repositories.dart';

final authServiceProvider = Provider((_) => AuthService());

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).authChanges();
});

final feedRepositoryProvider = Provider((_) => FeedRepository());

final homeFeedProvider = FutureProvider.family<List<PostModel>, int>((ref, page) async {
  return ref.watch(feedRepositoryProvider).homeFeed(page: page);
});
