# Flutter App Scaffold

## Screen structure
- Auth
  - `LoginScreen`
  - `SignupScreen`
  - `ForgotPasswordScreen`
- App shell
  - `HomeFeedScreen`
  - `CommunitiesScreen`
  - `CreatePostScreen`
  - `NotificationsScreen`
  - `ProfileScreen`
- Communities
  - `CommunityDetailScreen`
  - `CreateCommunityScreen`
- Social
  - `UserProfileScreen`
  - `BookmarksScreen`
  - `SearchScreen`
- Moderation/Admin
  - `ReportScreen`
  - `AdminModerationScreen`

## Core flows
- On launch: restore session, route to auth or app shell.
- Home feed: merged chronological feed from followed users + joined communities.
- Community feed: posts scoped by community.
- Moderation: report/block actions always available in post/user menus.

## Suggested packages
- `supabase_flutter`
- `go_router`
- `flutter_riverpod` (or Bloc)
- `image_picker`
- `cached_network_image`
- `firebase_messaging`
