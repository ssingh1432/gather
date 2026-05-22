import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/admin_moderation_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/bookmarks/bookmarks_screen.dart';
import '../features/communities/communities_screen.dart';
import '../features/communities/community_detail_screen.dart';
import '../features/communities/create_community_screen.dart';
import '../features/home/home_feed_screen.dart';
import '../features/home/post_detail_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/posts/create_post_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/user_profile_screen.dart';
import '../features/reports/report_screen.dart';
import '../features/search/search_screen.dart';
import 'supabase_client.dart';

final appRouter = GoRouter(
  redirect: (context, state) {
    final authed = SupabaseConfig.client.auth.currentUser != null;
    final onAuth = ['/login', '/signup', '/forgot'].contains(state.uri.path);
    if (!authed && !onAuth) return '/login';
    if (authed && onAuth) return '/';
    return null;
  },
  routes: [
    ShellRoute(
      builder: (_, state, child) => MainNav(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const HomeFeedScreen()),
        GoRoute(path: '/communities', builder: (_, __) => const CommunitiesScreen()),
        GoRoute(path: '/create-post', builder: (_, s) => CreatePostScreen(communityId: s.uri.queryParameters['communityId'])),
        GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
        GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      ],
    ),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (_, __) => SignupScreen()),
    GoRoute(path: '/forgot', builder: (_, __) => ForgotPasswordScreen()),
    GoRoute(path: '/community', builder: (_, s) => CommunityDetailScreen(communityId: s.uri.queryParameters['id'] ?? '')),
    GoRoute(path: '/create-community', builder: (_, __) => const CreateCommunityScreen()),
    GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
    GoRoute(path: '/user', builder: (_, s) => UserProfileScreen(userId: s.uri.queryParameters['id'] ?? '')),
    GoRoute(path: '/bookmarks', builder: (_, __) => const BookmarksScreen()),
    GoRoute(path: '/post', builder: (_, s) => PostDetailScreen(postId: s.uri.queryParameters['id'] ?? '')),
    GoRoute(path: '/report', builder: (_, __) => const ReportScreen()),
    GoRoute(path: '/admin', builder: (_, __) => const AdminModerationScreen()),
  ],
);

class MainNav extends StatelessWidget {
  const MainNav({super.key, required this.child, required this.location});
  final Widget child;
  final String location;

  @override
  Widget build(BuildContext context) {
    int index = 0;
    if (location.startsWith('/communities')) index = 1;
    if (location.startsWith('/create-post')) index = 2;
    if (location.startsWith('/search')) index = 3;
    if (location.startsWith('/profile')) index = 4;
    const tabs = ['/', '/communities', '/create-post', '/search', '/profile'];

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => context.go(tabs[i]),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.groups_outlined), label: 'Communities'),
          BottomNavigationBarItem(icon: Icon(Icons.add_box_outlined), label: 'Create Post'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}
