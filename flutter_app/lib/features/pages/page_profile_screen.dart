import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase_client.dart';
import '../../shared/utils/external_link.dart';
import '../../shared/utils/time_ago.dart';
import '../../shared/widgets/reusables.dart';
import '../data/repositories.dart';
import 'donate_sheet.dart';
import 'page_chat_screen.dart';
import 'page_local_repository.dart';
import 'page_manage_screen.dart';
import 'page_preview_screen.dart' show PageInfoRow;
import 'pages_theme.dart';

class PageProfileScreen extends StatefulWidget {
  const PageProfileScreen({super.key, required this.pageId});

  final String pageId;

  @override
  State<PageProfileScreen> createState() => _PageProfileScreenState();
}

/// A single visitor-post media attachment picked on-device but not yet
/// uploaded. `mediaType` matches the values `VisitorPostMediaUpload`
/// accepts on the repository side (image/video/document).
class _PickedVisitorMedia {
  _PickedVisitorMedia({required this.bytes, required this.filename, required this.mimeType, required this.mediaType});

  final Uint8List bytes;
  final String filename;
  final String mimeType;
  final String mediaType;
}

/// A small removable thumbnail/chip for a picked-but-not-yet-uploaded
/// attachment in the visitor-post composer.
class _PickedMediaChip extends StatelessWidget {
  const _PickedMediaChip({required this.item, required this.onRemove});

  final _PickedVisitorMedia item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 72,
          height: 72,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: item.mediaType == 'image'
              ? Image.memory(item.bytes, fit: BoxFit.cover)
              : Center(
                  child: Icon(
                    item.mediaType == 'video' ? Icons.videocam_outlined : Icons.description_outlined,
                    size: 28,
                  ),
                ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _PageProfileScreenState extends State<PageProfileScreen> {
  final _repo = PageRepository();
  final _localRepo = PageLocalRepository();

  Map<String, dynamic>? _page;
  bool _loading = true;
  bool _following = false;
  bool _followBusy = false;
  bool _favorite = false;
  bool _canManage = false;
  bool _canViewFollowers = false;
  bool _hasSubscriptionTiers = false;
  bool _hasMarketplaceItems = false;
  bool _allowVisitorPosts = false;
  bool _visitorPostsRequireApproval = false;
  List<Map<String, dynamic>> _posts = const [];
  List<Map<String, dynamic>> _visitorPosts = const [];
  List<Map<String, dynamic>> _events = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final page = await _repo.getPage(widget.pageId);
      final uid = SupabaseConfig.currentUserId;
      final followState = uid == null ? null : await _repo.getFollowState(widget.pageId);
      final role = uid == null ? null : await _repo.currentUserPageRole(widget.pageId);
      final canViewFollowers = uid == null
          ? false
          : await _repo.hasPagePermission(widget.pageId, 'view_analytics');
      final posts = await _repo.listPagePosts(widget.pageId, status: 'published');
      final events = await _repo.listPageEvents(widget.pageId);
      final hasTiers = await _repo.hasVisibleSubscriptionTiers(widget.pageId);
      final hasItems = await _repo.hasVisibleMarketplaceItems(widget.pageId);
      final visitorSettings = await _localRepo.getVisitorPostingSettings(widget.pageId);
      final visitorPosts = await _localRepo.listVisitorPosts(widget.pageId);

      if (!mounted) return;

      setState(() {
        _page = page;
        _following = followState != null;
        _favorite = followState?['favorite'] as bool? ?? false;
        _canManage = role != null;
        _canViewFollowers = canViewFollowers;
        _hasSubscriptionTiers = hasTiers;
        _hasMarketplaceItems = hasItems;
        _allowVisitorPosts = visitorSettings['allow_visitor_posts'] == true;
        _visitorPostsRequireApproval = visitorSettings['visitor_posts_require_approval'] == true;
        _posts = posts;
        _visitorPosts = visitorPosts;
        _events = events
            .where(
              (event) => DateTime.parse(event['start_time'] as String).isAfter(
                DateTime.now().subtract(const Duration(days: 1)),
              ),
            )
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this Page. $e';
        _loading = false;
      });
    }
  }

  Future<void> _createVisitorPost() async {
    if (SupabaseConfig.currentUserId == null) {
      context.push('/login');
      return;
    }

    final controller = TextEditingController();
    final media = <_PickedVisitorMedia>[];
    Map<String, dynamic>? selectedEvent;

    try {
      final submitted = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              final user = SupabaseConfig.maybeClient?.auth.currentUser;
              final displayName = user?.userMetadata?['display_name']?.toString().trim();
              final username = user?.userMetadata?['username']?.toString().trim();
              final authorLabel = displayName?.isNotEmpty == true
                  ? displayName!
                  : username?.isNotEmpty == true
                      ? '@$username'
                      : 'Your Gather account';
              final pageName = _page?['name']?.toString() ?? 'this Page';
              final hasMedia = media.isNotEmpty;
              final hasEvent = selectedEvent != null;

              Future<void> pickImages() async {
                final picked = await ImagePicker().pickMultiImage(imageQuality: 90, limit: 10 - media.length);
                if (picked.isEmpty) return;
                for (final file in picked) {
                  final bytes = await file.readAsBytes();
                  media.add(_PickedVisitorMedia(
                    bytes: bytes,
                    filename: file.name,
                    mimeType: file.mimeType ?? 'image/jpeg',
                    mediaType: 'image',
                  ));
                }
                setSheetState(() {});
              }

              Future<void> pickVideo() async {
                final picked = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
                if (picked == null) return;
                final bytes = await picked.readAsBytes();
                media
                  ..clear()
                  ..add(_PickedVisitorMedia(bytes: bytes, filename: picked.name, mimeType: picked.mimeType ?? 'video/mp4', mediaType: 'video'));
                setSheetState(() {});
              }

              Future<void> pickDocument() async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: const ['pdf', 'doc', 'docx'],
                  withData: true,
                );
                final picked = result?.files.single;
                if (picked == null || picked.bytes == null) return;
                media
                  ..clear()
                  ..add(_PickedVisitorMedia(
                    bytes: picked.bytes!,
                    filename: picked.name,
                    mimeType: picked.extension == 'pdf' ? 'application/pdf' : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                    mediaType: 'document',
                  ));
                setSheetState(() {});
              }

              Future<void> pickEvent() async {
                if (_events.isEmpty) {
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    const SnackBar(content: Text('This Page has no upcoming events to attach.')),
                  );
                  return;
                }
                final chosen = await showModalBottomSheet<Map<String, dynamic>>(
                  context: sheetContext,
                  showDragHandle: true,
                  builder: (eventSheetContext) => SafeArea(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final event in _events)
                          ListTile(
                            leading: const Icon(Icons.event_outlined),
                            title: Text(event['title'] as String? ?? 'Event'),
                            subtitle: event['start_time'] != null ? Text(timeAgo(DateTime.parse(event['start_time'] as String))) : null,
                            onTap: () => Navigator.pop(eventSheetContext, event),
                          ),
                      ],
                    ),
                  ),
                );
                if (chosen != null) {
                  selectedEvent = chosen;
                  setSheetState(() {});
                }
              }

              return Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Post on $pageName', style: Theme.of(sheetContext).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(sheetContext).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.person_outline),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      const TextSpan(text: 'Posting as '),
                                      TextSpan(text: authorLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      const TextSpan(text: ' on '),
                                      TextSpan(text: pageName, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_visitorPostsRequireApproval) ...[
                          const SizedBox(height: 10),
                          Text(
                            'This Page reviews visitor posts before they become public.',
                            style: Theme.of(sheetContext).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: controller,
                          autofocus: true,
                          maxLines: 6,
                          minLines: 3,
                          maxLength: 5000,
                          decoration: const InputDecoration(
                            hintText: 'Write something for this Page…',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        if (hasMedia) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (var i = 0; i < media.length; i++)
                                _PickedMediaChip(
                                  item: media[i],
                                  onRemove: () {
                                    media.removeAt(i);
                                    setSheetState(() {});
                                  },
                                ),
                            ],
                          ),
                        ],
                        if (hasEvent) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              border: Border.all(color: PageColors.border(sheetContext)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.event_outlined, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    selectedEvent!['title'] as String? ?? 'Event',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    selectedEvent = null;
                                    setSheetState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Add photos',
                              onPressed: hasEvent || media.any((m) => m.mediaType != 'image') ? null : pickImages,
                              icon: const Icon(Icons.image_outlined),
                            ),
                            IconButton(
                              tooltip: 'Add a video',
                              onPressed: hasEvent || hasMedia ? null : pickVideo,
                              icon: const Icon(Icons.videocam_outlined),
                            ),
                            IconButton(
                              tooltip: 'Add a document',
                              onPressed: hasEvent || hasMedia ? null : pickDocument,
                              icon: const Icon(Icons.description_outlined),
                            ),
                            IconButton(
                              tooltip: 'Attach an event',
                              onPressed: hasMedia ? null : pickEvent,
                              icon: const Icon(Icons.event_outlined),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.pop(sheetContext, false),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: () async {
                                  final content = controller.text.trim();
                                  if (content.isEmpty && media.isEmpty && selectedEvent == null) return;
                                  try {
                                    await _localRepo.createVisitorPost(
                                      widget.pageId,
                                      content,
                                      media: media
                                          .map((m) => VisitorPostMediaUpload(bytes: m.bytes, filename: m.filename, mimeType: m.mimeType, mediaType: m.mediaType))
                                          .toList(),
                                      eventId: selectedEvent?['id'] as String?,
                                    );
                                    if (sheetContext.mounted) Navigator.pop(sheetContext, true);
                                  } catch (e) {
                                    if (sheetContext.mounted) {
                                      final message = e.toString().toLowerCase().contains('row-level security') ||
                                              e.toString().toLowerCase().contains('policy')
                                          ? 'Follow this Page to post.'
                                          : 'Could not post: $e';
                                      ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text(message)));
                                    }
                                  }
                                },
                                child: Text(_visitorPostsRequireApproval ? 'Submit for review' : 'Post'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

      if (submitted == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _visitorPostsRequireApproval
                  ? 'Your post was sent to ${_page?['name'] ?? 'this Page'} for review.'
                  : 'Your post is now visible on ${_page?['name'] ?? 'this Page'}.',
            ),
          ),
        );
        await _load();
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _toggleFollow() async {
    if (SupabaseConfig.currentUserId == null) {
      context.push('/login');
      return;
    }

    final wasFollowing = _following;
    setState(() {
      _followBusy = true;
      _following = !wasFollowing;
      final count = (_page?['follower_count'] as int?) ?? 0;
      _page = {
        ..._page!,
        'follower_count': wasFollowing ? count - 1 : count + 1,
      };
    });

    try {
      if (wasFollowing) {
        await _repo.unfollowPage(widget.pageId);
      } else {
        await _repo.followPage(widget.pageId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _following = wasFollowing;
        final count = (_page?['follower_count'] as int?) ?? 0;
        _page = {
          ..._page!,
          'follower_count': wasFollowing ? count + 1 : count - 1,
        };
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update follow status: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _followBusy = false;
          if (!_following) _favorite = false;
        });
      }
    }
  }

  Future<void> _toggleFavorite() async {
    if (!_following) return;

    final wasFavorite = _favorite;
    setState(() => _favorite = !wasFavorite);
    try {
      await _repo.setPageFavorite(widget.pageId, !wasFavorite);
    } catch (e) {
      if (!mounted) return;
      setState(() => _favorite = wasFavorite);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update favorite: $e')),
      );
    }
  }

  String get _pageTypeLabel {
    final type = _page?['page_type'] as String?;
    return kPageTypes[type] ?? type ?? 'Other';
  }

  String? get _businessHoursNote {
    final hours = _page?['business_hours'];
    if (hours is Map) {
      final note = hours['note'];
      if (note is String && note.isNotEmpty) return note;
    }
    return null;
  }

  Future<void> _launchOrSnack(Uri uri) async {
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this link.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this link.')),
        );
      }
    }
  }

  Map<String, String> get _socialLinks {
    final links = _page?['social_links'];
    if (links is Map) {
      final result = <String, String>{};
      for (final entry in links.entries) {
        final value = entry.value?.toString() ?? '';
        if (value.isNotEmpty) result[entry.key.toString()] = value;
      }
      return result;
    }
    return const {};
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          page?['name'] as String? ?? 'Page',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_canManage)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Manage Page',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PageManageScreen(pageId: widget.pageId),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const FeedSkeletonList()
          : _error != null
              ? ErrorRetryState(
                  title: 'Unable to load Page',
                  message: _error!,
                  onRetry: _load,
                )
              : page == null
                  ? const Center(child: Text('Page not found'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.only(
                          bottom: PageTokens.spaceXxl,
                        ),
                        children: [
                          PageCoverAndLogo(page: page),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: PageTokens.spaceLg,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 40),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        page['name'] as String,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                    if (page['verification_status'] == 'verified') ...[
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.verified,
                                        color: AppColors.brandTeal,
                                        size: 20,
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  '@${page['username']}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                                const SizedBox(height: PageTokens.spaceSm),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    PageStatChip(
                                      icon: Icons.category_outlined,
                                      label: _pageTypeLabel,
                                    ),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(
                                        PageTokens.radiusPill,
                                      ),
                                      onTap: _canViewFollowers
                                          ? () => context.push(
                                                '/page-followers?id=${widget.pageId}',
                                              )
                                          : null,
                                      child: PageStatChip(
                                        icon: Icons.people_alt_outlined,
                                        label:
                                            '${page['follower_count'] ?? 0} follower${(page['follower_count'] ?? 0) == 1 ? '' : 's'}',
                                      ),
                                    ),
                                    if (page['location'] != null)
                                      PageStatChip(
                                        icon: Icons.place_outlined,
                                        label: page['location'] as String,
                                      ),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(
                                        PageTokens.radiusPill,
                                      ),
                                      onTap: () => context.push(
                                        '/page-reviews?id=${widget.pageId}',
                                      ),
                                      child: PageStatChip(
                                        icon: Icons.star_outline,
                                        color: (page['rating_count'] ?? 0) > 0
                                            ? AppColors.brandTeal
                                            : null,
                                        label: (page['rating_count'] ?? 0) > 0
                                            ? '${((page['rating_avg'] as num?) ?? 0).toStringAsFixed(1)} (${page['rating_count']})'
                                            : 'No reviews yet',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: PageTokens.spaceLg),
                                _CtaRow(
                                  following: _following,
                                  favorite: _favorite,
                                  busy: _followBusy,
                                  onFollow: _toggleFollow,
                                  onFavorite: _following ? _toggleFavorite : null,
                                  onMessage: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => PageChatScreen(
                                        pageId: widget.pageId,
                                        pageName: page['name'] as String? ?? 'Page',
                                      ),
                                    ),
                                  ),
                                ),
                                if (_allowVisitorPosts) ...[
                                  const SizedBox(height: PageTokens.spaceMd),
                                  if (_canManage || _following)
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: _createVisitorPost,
                                        icon: const Icon(Icons.edit_outlined),
                                        label: const Text('Post on this Page'),
                                      ),
                                    )
                                  else
                                    PageVisitorPostFollowGate(
                                      busy: _followBusy,
                                      onFollow: _toggleFollow,
                                    ),
                                ],
                                if (_hasSubscriptionTiers || _hasMarketplaceItems) ...[
                                  const SizedBox(height: PageTokens.spaceSm),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      if (_hasSubscriptionTiers)
                                        TextButton.icon(
                                          onPressed: () => context.push(
                                            '/page-subscriptions?id=${widget.pageId}&name=${Uri.encodeComponent(page['name'] as String? ?? 'Page')}',
                                          ),
                                          icon: const Icon(Icons.workspace_premium_outlined, size: 16),
                                          label: const Text('Subscriptions'),
                                        ),
                                      if (_hasMarketplaceItems)
                                        TextButton.icon(
                                          onPressed: () => context.push(
                                            '/page-marketplace?id=${widget.pageId}&name=${Uri.encodeComponent(page['name'] as String? ?? 'Page')}',
                                          ),
                                          icon: const Icon(Icons.storefront_outlined, size: 16),
                                          label: const Text('Shop'),
                                        ),
                                    ],
                                  ),
                                ],
                                if (page['monetization_enabled'] == true) ...[
                                  const SizedBox(height: PageTokens.spaceMd),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () => showDonateSheet(
                                        context,
                                        pageId: widget.pageId,
                                        pageName: page['name'] as String? ?? 'this Page',
                                      ),
                                      icon: const Icon(Icons.volunteer_activism_outlined, size: 18),
                                      label: const Text('Support this Page'),
                                    ),
                                  ),
                                ],
                                if ((page['description'] as String?)?.isNotEmpty ?? false) ...[
                                  const SizedBox(height: PageTokens.spaceLg),
                                  Text(page['description'] as String),
                                ],
                                const SizedBox(height: PageTokens.spaceLg),
                                const Divider(),
                                const SizedBox(height: PageTokens.spaceSm),
                                if (page['website'] != null)
                                  InkWell(
                                    onTap: () => openExternalLink(context, page['website'] as String),
                                    child: PageInfoRow(icon: Icons.link, text: page['website'] as String),
                                  ),
                                if (page['phone'] != null)
                                  InkWell(
                                    onTap: () => _launchOrSnack(Uri(scheme: 'tel', path: page['phone'] as String)),
                                    child: PageInfoRow(icon: Icons.phone_outlined, text: page['phone'] as String),
                                  ),
                                if (page['email'] != null)
                                  InkWell(
                                    onTap: () => _launchOrSnack(Uri(scheme: 'mailto', path: page['email'] as String)),
                                    child: PageInfoRow(icon: Icons.email_outlined, text: page['email'] as String),
                                  ),
                                if (page['country'] != null)
                                  PageInfoRow(icon: Icons.public, text: page['country'] as String),
                                if (_businessHoursNote != null)
                                  PageInfoRow(icon: Icons.schedule_outlined, text: _businessHoursNote!),
                                if (_socialLinks.isNotEmpty) ...[
                                  const SizedBox(height: PageTokens.spaceMd),
                                  Text(
                                    'Social',
                                    style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final entry in _socialLinks.entries)
                                        ActionChip(
                                          avatar: const Icon(Icons.public, size: 16),
                                          label: Text(entry.key),
                                          onPressed: () => openExternalLink(context, entry.value),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (_events.isNotEmpty) ...[
                            const Divider(height: PageTokens.spaceXl),
                            const PageSectionHeader(title: 'Upcoming events'),
                            for (final event in _events)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: PageTokens.spaceLg,
                                  vertical: 4,
                                ),
                                child: _ProfileEventCard(event: event),
                              ),
                          ],
                          if (_posts.isNotEmpty) ...[
                            const Divider(height: PageTokens.spaceXl),
                            const PageSectionHeader(title: 'Posts'),
                            for (final post in _posts)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: PageTokens.spaceLg,
                                  vertical: 4,
                                ),
                                child: _ProfilePostCard(post: post),
                              ),
                          ],
                          if (_visitorPosts.isNotEmpty) ...[
                            const Divider(height: PageTokens.spaceXl),
                            const PageSectionHeader(title: 'Posts by visitors'),
                            for (final post in _visitorPosts)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: PageTokens.spaceLg,
                                  vertical: 4,
                                ),
                                child: _VisitorPostCard(post: post),
                              ),
                          ],
                        ],
                      ),
                    ),
    );
  }
}

class _CtaRow extends StatelessWidget {
  const _CtaRow({
    required this.following,
    required this.favorite,
    required this.busy,
    required this.onFollow,
    required this.onFavorite,
    required this.onMessage,
  });

  final bool following;
  final bool favorite;
  final bool busy;
  final VoidCallback onFollow;
  final VoidCallback? onFavorite;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: following
              ? OutlinedButton.icon(
                  onPressed: busy ? null : onFollow,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Following'),
                )
              : FilledButton.icon(
                  onPressed: busy ? null : onFollow,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Follow'),
                ),
        ),
        if (following) ...[
          const SizedBox(width: 8),
          IconButton(
            onPressed: onFavorite,
            icon: Icon(favorite ? Icons.star : Icons.star_border),
            tooltip: favorite ? 'Unfavorite' : 'Favorite',
          ),
        ],
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onMessage,
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('Message'),
          ),
        ),
      ],
    );
  }
}

/// Shown in place of the visitor-post composer when the current user does
/// not yet follow this Page. Supabase requires a follow before a
/// `page_visitor_posts` INSERT succeeds, so the UI surfaces that
/// requirement up front instead of letting the composer fail silently.
class PageVisitorPostFollowGate extends StatelessWidget {
  const PageVisitorPostFollowGate({super.key, required this.busy, required this.onFollow});

  final bool busy;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PageTokens.spaceMd),
      decoration: BoxDecoration(
        color: PageColors.surfaceMuted(context),
        borderRadius: BorderRadius.circular(PageTokens.radiusMd),
        border: Border.all(color: PageColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Follow this Page to post',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: PageTokens.spaceSm),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : onFollow,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Follow'),
            ),
          ),
        ],
      ),
    );
  }
}

int _pgCount(dynamic value) {
  if (value is List && value.isNotEmpty) {
    final c = (value.first as Map)['count'];
    if (c is num) return c.toInt();
  }
  return 0;
}

class _VisitorPostCard extends StatefulWidget {
  const _VisitorPostCard({required this.post});

  final Map<String, dynamic> post;

  @override
  State<_VisitorPostCard> createState() => _VisitorPostCardState();
}

class _VisitorPostCardState extends State<_VisitorPostCard> {
  final _localRepo = PageLocalRepository();

  late bool _liked;
  late int _likeCount;
  late int _commentCount;
  late int _shareCount;
  bool _likeBusy = false;

  Map<String, dynamic> get post => widget.post;

  @override
  void initState() {
    super.initState();
    _liked = post['liked_by_me'] == true;
    _likeCount = _pgCount(post['like_count']);
    _commentCount = _pgCount(post['comment_count']);
    _shareCount = _pgCount(post['share_count']);
  }

  Future<void> _toggleLike() async {
    if (SupabaseConfig.currentUserId == null) {
      context.push('/login');
      return;
    }
    if (_likeBusy) return;
    setState(() {
      _likeBusy = true;
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
    });
    try {
      await _localRepo.toggleVisitorPostLike(post['id'] as String, currentlyLiked: !_liked);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liked = !_liked;
        _likeCount += _liked ? 1 : -1;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update like: $e')));
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }
  }

  Future<void> _openComments() async {
    if (SupabaseConfig.currentUserId == null) {
      context.push('/login');
      return;
    }
    final postId = post['id'] as String;
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _VisitorPostCommentsSheet(postId: postId),
    );
    if (added == true && mounted) setState(() => _commentCount += 1);
  }

  Future<void> _openShareSheet() async {
    final postId = post['id'] as String;
    final pageId = post['page_id'] as String;
    final shareUrl = 'https://eiquoab.xyz/page?id=$pageId';
    final shareText = (post['content'] as String?)?.trim().isNotEmpty == true ? (post['content'] as String).trim() : 'Check out this post on Gather';

    Future<void> recordShare() async {
      try {
        await _localRepo.recordVisitorPostShare(postId);
        if (mounted) setState(() => _shareCount += 1);
      } catch (_) {
        // Sharing already happened from the user's point of view; a failed
        // share-count write shouldn't surface as an error.
      }
    }

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Copy link'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await Clipboard.setData(ClipboardData(text: shareUrl));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied.')));
                await recordShare();
              },
            ),
            ListTile(
              leading: const Icon(Icons.more_horiz),
              title: const Text('More apps'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await Share.share('$shareText\n\n$shareUrl');
                await recordShare();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final author = post['users'] is Map ? Map<String, dynamic>.from(post['users'] as Map) : <String, dynamic>{};
    final pageInfo = post['pages'] is Map ? Map<String, dynamic>.from(post['pages'] as Map) : <String, dynamic>{};
    final eventInfo = post['page_events'] is Map ? Map<String, dynamic>.from(post['page_events'] as Map) : null;
    final name = (author['display_name'] as String?)?.trim();
    final username = (author['username'] as String?)?.trim();
    final label = name?.isNotEmpty == true
        ? name!
        : username?.isNotEmpty == true
            ? '@$username'
            : 'Gather user';
    final created = post['created_at'] as String?;
    final avatarUrl = author['profile_photo_url'] as String?;
    final pageLogoUrl = pageInfo['logo_url'] as String?;
    final media = (post['media'] is List) ? List<Map<String, dynamic>>.from((post['media'] as List).map((m) => Map<String, dynamic>.from(m as Map))) : const <Map<String, dynamic>>[];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Both the poster's own avatar and this Page's avatar are shown
                // together — this is a post made by a follower, not the Page
                // owner, so it's important both identities stay visible.
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipOval(
                      child: avatarUrl?.isNotEmpty == true
                          ? Image.network(
                              avatarUrl!,
                              width: 36,
                              height: 36,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 36,
                                height: 36,
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                alignment: Alignment.center,
                                child: const Icon(Icons.person_outline, size: 18),
                              ),
                            )
                          : Container(
                              width: 36,
                              height: 36,
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: const Icon(Icons.person_outline, size: 18),
                            ),
                    ),
                    if (pageLogoUrl?.isNotEmpty == true)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.all(1.5),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            shape: BoxShape.circle,
                          ),
                          child: ClipOval(
                            child: Image.network(
                              pageLogoUrl!,
                              width: 16,
                              height: 16,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox(width: 16, height: 16),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              label,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.person_outline, size: 14),
                        ],
                      ),
                      if (username?.isNotEmpty == true && name?.isNotEmpty == true)
                        Text(
                          '@$username',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                if (created != null)
                  Text(
                    timeAgo(DateTime.parse(created)),
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
            if ((post['content'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(post['content'] as String? ?? ''),
            ],
            if (media.isNotEmpty) ...[
              const SizedBox(height: 10),
              _VisitorPostMediaGrid(media: media),
            ],
            if (eventInfo != null) ...[
              const SizedBox(height: 10),
              _VisitorPostEventChip(event: eventInfo),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                _VisitorPostAction(
                  icon: _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  iconColor: _liked ? Colors.redAccent : null,
                  count: _likeCount,
                  onTap: _toggleLike,
                ),
                const SizedBox(width: 16),
                _VisitorPostAction(
                  icon: Icons.chat_bubble_outline_rounded,
                  count: _commentCount,
                  onTap: _openComments,
                ),
                const SizedBox(width: 16),
                _VisitorPostAction(
                  icon: Icons.send_outlined,
                  count: _shareCount,
                  onTap: _openShareSheet,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon + count as one tappable unit, matching the visual language of the
/// main feed's post action bar (see `_CountedAction` in reusables.dart).
class _VisitorPostAction extends StatelessWidget {
  const _VisitorPostAction({required this.icon, required this.count, required this.onTap, this.iconColor});

  final IconData icon;
  final int count;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: iconColor),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text('$count', style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _VisitorPostMediaGrid extends StatelessWidget {
  const _VisitorPostMediaGrid({required this.media});

  final List<Map<String, dynamic>> media;

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final images = media.where((m) => m['type'] == 'image').toList();
    if (images.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: images.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: images.length == 1 ? 1 : 2,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
            childAspectRatio: images.length == 1 ? 16 / 10 : 1,
          ),
          itemBuilder: (_, i) => Image.network(
            images[i]['url'] as String,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
      );
    }

    final video = media.firstWhere((m) => m['type'] == 'video', orElse: () => const {});
    if (video.isNotEmpty) {
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openUrl(video['url'] as String),
        child: Container(
          height: 160,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.play_circle_fill_rounded, size: 48),
        ),
      );
    }

    final doc = media.firstWhere((m) => m['type'] == 'document', orElse: () => const {});
    if (doc.isNotEmpty) {
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openUrl(doc['url'] as String),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: PageColors.border(context)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: const [
              Icon(Icons.description_outlined),
              SizedBox(width: 8),
              Expanded(child: Text('Open attached document', overflow: TextOverflow.ellipsis)),
              Icon(Icons.open_in_new, size: 16),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _VisitorPostEventChip extends StatelessWidget {
  const _VisitorPostEventChip({required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final start = event['start_time'] as String?;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: PageColors.border(context)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event['title'] as String? ?? 'Event', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (start != null)
                  Text(
                    timeAgo(DateTime.parse(start)),
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                if ((event['location'] as String?)?.isNotEmpty == true)
                  Text(
                    event['location'] as String,
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VisitorPostCommentsSheet extends StatefulWidget {
  const _VisitorPostCommentsSheet({required this.postId});

  final String postId;

  @override
  State<_VisitorPostCommentsSheet> createState() => _VisitorPostCommentsSheetState();
}

class _VisitorPostCommentsSheetState extends State<_VisitorPostCommentsSheet> {
  final _localRepo = PageLocalRepository();
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _comments = const [];
  bool _loading = true;
  bool _sending = false;
  bool _added = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final comments = await _localRepo.listVisitorPostComments(widget.postId);
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load comments: $e')));
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _localRepo.addVisitorPostComment(widget.postId, text);
      _controller.clear();
      _added = true;
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not comment: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Align(alignment: Alignment.centerLeft, child: Text('Comments', style: TextStyle(fontWeight: FontWeight.w700))),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _comments.isEmpty
                          ? const Center(child: Text('No comments yet.'))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _comments.length,
                              itemBuilder: (_, i) {
                                final c = _comments[i];
                                final author = c['users'] is Map ? Map<String, dynamic>.from(c['users'] as Map) : <String, dynamic>{};
                                final name = (author['display_name'] as String?)?.trim();
                                final username = (author['username'] as String?)?.trim();
                                final label = name?.isNotEmpty == true ? name! : (username?.isNotEmpty == true ? '@$username' : 'Gather user');
                                final avatarUrl = author['profile_photo_url'] as String?;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ClipOval(
                                        child: avatarUrl?.isNotEmpty == true
                                            ? Image.network(avatarUrl!, width: 28, height: 28, fit: BoxFit.cover)
                                            : Container(
                                                width: 28,
                                                height: 28,
                                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                                child: const Icon(Icons.person_outline, size: 14),
                                              ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                            Text(c['content'] as String? ?? ''),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: const InputDecoration(hintText: 'Write a comment…', border: OutlineInputBorder()),
                          minLines: 1,
                          maxLines: 4,
                        ),
                      ),
                      IconButton(
                        onPressed: _sending ? null : _send,
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }
}

class _ProfilePostCard extends StatefulWidget {
  const _ProfilePostCard({required this.post});

  final Map<String, dynamic> post;

  @override
  State<_ProfilePostCard> createState() => _ProfilePostCardState();
}

class _ProfilePostCardState extends State<_ProfilePostCard> {
  final _analytics = PageAnalyticsRepository();

  Map<String, dynamic> get post => widget.post;

  @override
  void initState() {
    super.initState();
    final id = post['id'] as String?;
    if (id != null) _analytics.recordImpression(id);
  }

  @override
  Widget build(BuildContext context) {
    final type = post['post_type'] as String? ?? 'post';
    final pinned = post['pinned'] as bool? ?? false;
    final content = post['content'] as String? ?? '';
    final media = post['media'];
    final imageUrl = media is List && media.isNotEmpty && media.first is Map
        ? (media.first as Map)['url'] as String?
        : null;
    final publishedAt = post['published_at'] as String? ?? post['created_at'] as String?;

    return Container(
      padding: const EdgeInsets.all(PageTokens.spaceMd),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: PageColors.surfaceCard(context),
        borderRadius: BorderRadius.circular(PageTokens.radiusMd),
        border: Border.all(color: PageColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (pinned)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.push_pin, size: 14, color: AppColors.brandTeal),
                ),
              PageStatChip(
                icon: kPagePostTypeIcons[type] ?? Icons.article_outlined,
                label: kPagePostTypes[type] ?? type,
              ),
              const Spacer(),
              if (publishedAt != null)
                Text(
                  timeAgo(DateTime.parse(publishedAt)),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (content.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(content),
          ],
          if (imageUrl != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(PageTokens.radiusSm),
              child: Image.network(
                imageUrl,
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: double.infinity,
                  height: 180,
                  color: PageColors.surfaceMuted(context),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.broken_image_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Image unavailable',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileEventCard extends StatelessWidget {
  const _ProfileEventCard({required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.parse(event['start_time'] as String).toLocal();

    return Container(
      padding: const EdgeInsets.all(PageTokens.spaceMd),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: PageColors.surfaceCard(context),
        borderRadius: BorderRadius.circular(PageTokens.radiusMd),
        border: Border.all(color: PageColors.border(context)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.brandTeal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(PageTokens.radiusSm),
            ),
            child: const Icon(Icons.event, color: AppColors.brandTeal, size: 20),
          ),
          const SizedBox(width: PageTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event['title'] as String? ?? 'Event',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${start.day}/${start.month}/${start.year} · ${TimeOfDay.fromDateTime(start).format(context)}${event['location'] != null ? ' · ${event['location']}' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
