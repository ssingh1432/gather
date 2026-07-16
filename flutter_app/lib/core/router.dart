import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/admin_moderation_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/auth/verify_phone_screen.dart';
import '../features/beta/beta_feedback_button.dart';
import '../features/beta/beta_gate.dart';
import '../features/bookmarks/bookmarks_screen.dart';
import '../features/communities/communities_screen.dart';
import '../features/communities/community_detail_screen.dart';
import '../features/communities/create_community_screen.dart';
import '../features/home/home_feed_screen.dart';
import '../features/home/post_detail_screen.dart';
import '../features/home/post_replies_screen.dart';
import '../features/media/media_viewer_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/posts/create_post_screen.dart';
import '../features/profile/edit_profile_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/user_profile_screen.dart';
import '../features/profile/monetization_settings_screen.dart';
import '../features/profile/close_friends_screen.dart';
import 'responsive.dart';
import '../features/reports/report_screen.dart';
import '../features/search/search_screen.dart';
import 'supabase_client.dart';

final appRouter = GoRouter(
  // GoRouter's default error screen shows the raw exception text (e.g.
  // "GoException: no routes for location: error=access_denied&..."). That
  // exact case happens whenever an expired/invalid Supabase auth link
  // (signup confirmation, password reset) redirects back with an
  // "#error=..." fragment that doesn't match any route. Recognize that
  // pattern and show something a person can actually act on.
  errorBuilder: (context, state) {
    final text = state.error?.toString() ?? '';
    final isAuthLinkError = text.contains('otp_expired') ||
        text.contains('access_denied') ||
        text.contains('invalid_request');
    return Scaffold(
      appBar: AppBar(title: const Text('Gather')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isAuthLinkError
                    ? 'This link has expired or was already used.'
                    : "That page doesn't exist.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 20),
              if (isAuthLinkError)
                FilledButton(
                  onPressed: () => context.go('/forgot'),
                  child: const Text('Request a new link'),
                )
              else
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Go home'),
                ),
            ],
          ),
        ),
      ),
    );
  },
  redirect: (context, state) {
    final authed = SupabaseConfig.maybeClient?.auth.currentUser != null;
    final path = state.uri.path;
    final onAuth = _authRoutes.contains(path);
    final protected = _protectedRoutes.contains(path);

    if (!authed && protected) {
      return _loginLocation(redirect: state.uri.toString());
    }

    if (authed && onAuth) {
      return _safeRedirect(state.uri.queryParameters['redirect']) ?? '/';
    }

    return null;
  },
  routes: [
    ShellRoute(
      builder: (_, state, child) => MainNav(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const HomeFeedScreen()),
        GoRoute(path: '/communities', builder: (_, __) => const CommunitiesScreen()),
        GoRoute(
          path: '/create-post',
          builder: (_, s) => CreatePostScreen(
            communityId: s.uri.queryParameters['communityId'],
            quotePostId: s.uri.queryParameters['quotePostId'],
          ),
        ),
        GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
        GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      ],
    ),
    GoRoute(path: '/login', builder: (_, s) => LoginScreen(redirect: s.uri.queryParameters['redirect'])),
    GoRoute(path: '/signup', builder: (_, s) => SignupScreen(redirect: s.uri.queryParameters['redirect'])),
    GoRoute(path: '/register', builder: (_, s) => SignupScreen(redirect: s.uri.queryParameters['redirect'])),
    GoRoute(path: '/forgot', builder: (_, __) => ForgotPasswordScreen()),
    // Deliberately not in _authRoutes/_protectedRoutes: the recovery link
    // lands here with a fresh recovery session that supabase_flutter is
    // still parsing from the URL fragment on the very first frame, so it
    // must never be bounced by the authed/protected redirect check above.
    GoRoute(path: '/reset-password', builder: (_, __) => const ResetPasswordScreen()),
    GoRoute(path: '/verify-phone', builder: (_, s) => VerifyPhoneScreen(phone: s.uri.queryParameters['phone'] ?? '')),
    GoRoute(path: '/community', builder: (_, s) => CommunityDetailScreen(communityId: s.uri.queryParameters['id'] ?? '')),
    GoRoute(path: '/create-community', builder: (_, __) => const CreateCommunityScreen()),
    GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
    GoRoute(path: '/user', builder: (_, s) => UserProfileScreen(userId: s.uri.queryParameters['id'] ?? '')),
    GoRoute(path: '/bookmarks', builder: (_, __) => const BookmarksScreen()),
    GoRoute(path: '/edit-profile', builder: (_, __) => const EditProfileScreen()),
    GoRoute(path: '/monetization', builder: (_, __) => const MonetizationSettingsScreen()),
    GoRoute(path: '/close-friends', builder: (_, __) => const CloseFriendsScreen()),
    GoRoute(path: '/post', builder: (_, s) => PostDetailScreen(postId: s.uri.queryParameters['id'] ?? '')),
    GoRoute(path: '/post/replies', builder: (_, s) => PostRepliesScreen(postId: s.uri.queryParameters['id'] ?? '')),
    GoRoute(
      path: '/media',
      builder: (_, s) => MediaViewerScreen(
        url: s.uri.queryParameters['url'] ?? '',
        isVideo: s.uri.queryParameters['type'] == 'video',
      ),
    ),
    GoRoute(
      path: '/report',
      builder: (_, s) => ReportScreen(
        postId: s.uri.queryParameters['postId'],
        userId: s.uri.queryParameters['userId'],
      ),
    ),
    GoRoute(path: '/admin', builder: (_, __) => const AdminModerationScreen()),
  ],
);

class MainNav extends StatelessWidget {
  const MainNav({super.key, required this.child, required this.location});
  final Widget child;
  final String location;

  static const _tabs = ['/', '/communities', '/create-post', '/search', '/profile'];
  static const _icons = [
    Icons.home_outlined,
    Icons.groups_outlined,
    Icons.add_box_outlined,
    Icons.search,
    Icons.person_outline,
  ];
  static const _labels = ['Home', 'Communities', 'Create Post', 'Search', 'Profile'];

  int _indexFor(String location) {
    if (location.startsWith('/communities')) return 1;
    if (location.startsWith('/create-post')) return 2;
    if (location.startsWith('/search')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final index = _indexFor(location);

    if (Breakpoints.isDesktop(context)) {
      return Scaffold(
        floatingActionButton: const BetaFeedbackButton(),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: (i) => context.go(_tabs[i]),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (int i = 0; i < _labels.length; i++)
                  NavigationRailDestination(icon: Icon(_icons[i]), label: Text(_labels[i])),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: BetaGate(
                child: ResponsiveCenter(child: child),
              ),
            ),
          ],
        ),
      );
    }

    // Mobile & tablet: keep the familiar bottom nav; cap content width on
    // tablet so cards/forms don't stretch uncomfortably wide before the
    // desktop breakpoint kicks in.
    return Scaffold(
      body: BetaGate(
        child: Breakpoints.isTablet(context) ? ResponsiveCenter(child: child) : child,
      ),
      floatingActionButton: const BetaFeedbackButton(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => context.go(_tabs[i]),
        type: BottomNavigationBarType.fixed,
        items: [
          for (int i = 0; i < _labels.length; i++)
            BottomNavigationBarItem(icon: Icon(_icons[i]), label: _labels[i]),
        ],
      ),
    );
  }
}

const _authRoutes = {'/login', '/signup', '/register', '/forgot'};
const _protectedRoutes = {
  '/',
  '/communities',
  '/community',
  '/post',
  '/media',
  '/search',
  '/user',
  '/create-post',
  '/create-community',
  '/profile',
  '/edit-profile',
  '/verify-phone',
  '/monetization',
  '/close-friends',
  '/bookmarks',
  '/notifications',
  '/report',
  '/admin',
};

String _loginLocation({required String redirect}) =>
    '/login?redirect=${Uri.encodeComponent(redirect)}';

String? _safeRedirect(String? redirect) {
  if (redirect == null || redirect.isEmpty) return null;
  final uri = Uri.tryParse(redirect);
  if (uri == null || !uri.hasAbsolutePath || uri.hasScheme || uri.hasAuthority) {
    return null;
  }
  return uri.toString();
}
