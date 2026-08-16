import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../data/repositories.dart';
import '../../shared/utils/time_ago.dart';
import '../../shared/widgets/reusables.dart';
import 'page_chat_screen.dart';
import 'page_messaging_settings_screen.dart';
import 'pages_theme.dart';

/// Team-facing customer-chat inbox. Messaging settings are intentionally
/// exposed as a visible action when the user can edit them; they are not
/// hidden behind an unlabeled/undiscoverable icon.
class PageInboxScreen extends StatefulWidget {
  const PageInboxScreen({super.key, required this.pageId, this.pageName});
  final String pageId;
  final String? pageName;

  @override
  State<PageInboxScreen> createState() => _PageInboxScreenState();
}

class _PageInboxScreenState extends State<PageInboxScreen> {
  final _repo = PageRepository();
  List<Map<String, dynamic>> _threads = const [];
  bool _loading = true;
  bool _canEditSettings = false;
  String? _error;
  String? _pageName;

  @override
  void initState() {
    super.initState();
    _pageName = widget.pageName;
    _load();
    _loadPermission();
    if (_pageName == null) _loadPageName();
  }

  Future<void> _loadPageName() async {
    final page = await _repo.getPage(widget.pageId);
    if (mounted && page != null) setState(() => _pageName = page['name'] as String?);
  }

  Future<void> _loadPermission() async {
    final canEdit = await _repo.hasPagePermission(widget.pageId, 'manage_settings');
    if (mounted) setState(() => _canEditSettings = canEdit);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final threads = await _repo.listPageMessageThreads(widget.pageId);
      if (mounted) setState(() { _threads = threads; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load the inbox. $e'; _loading = false; });
    }
  }

  Future<void> _openThread(Map<String, dynamic> t) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PageChatScreen(
        pageId: widget.pageId,
        pageName: _pageName ?? 'Page',
        otherUserId: t['user_id'] as String,
        otherUsername: t['username'] as String?,
      ),
    ));
    _load();
  }

  Future<void> _openMessagingSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PageMessagingSettingsScreen(pageId: widget.pageId),
      ),
    );
    if (mounted) _loadPermission();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_canEditSettings)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Messaging settings',
              onPressed: _openMessagingSettings,
            ),
        ],
      ),
      body: _loading
          ? const FeedSkeletonList()
          : _error != null
              ? ErrorRetryState(title: 'Unable to load', message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: [
                      if (_canEditSettings)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            PageTokens.spaceLg,
                            PageTokens.spaceMd,
                            PageTokens.spaceLg,
                            PageTokens.spaceSm,
                          ),
                          child: OutlinedButton.icon(
                            onPressed: _openMessagingSettings,
                            icon: const Icon(Icons.settings_outlined),
                            label: const Text('Messaging settings'),
                          ),
                        ),
                      if (_threads.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 96),
                          child: EmptyState(
                            icon: Icons.inbox_outlined,
                            title: 'No messages yet',
                            message: 'Customer conversations will show up here.',
                          ),
                        )
                      else
                        ..._threads.map((t) {
                          final unread = (t['unread_count'] as int?) ?? 0;
                          final fromPage = t['last_sender_type'] == 'page';
                          return Column(
                            children: [
                              ListTile(
                                onTap: () => _openThread(t),
                                leading: CircleAvatar(
                                  backgroundImage: (t['profile_photo_url'] as String?) != null
                                      ? NetworkImage(t['profile_photo_url'] as String)
                                      : null,
                                  child: (t['profile_photo_url'] as String?) == null
                                      ? const Icon(Icons.person_outline)
                                      : null,
                                ),
                                title: Text(
                                  (t['display_name'] as String?)?.isNotEmpty == true
                                      ? t['display_name'] as String
                                      : '@${t['username']}',
                                  style: TextStyle(fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600),
                                ),
                                subtitle: Text(
                                  '${fromPage ? 'You: ' : ''}${t['last_message'] ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400),
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      t['last_message_at'] != null
                                          ? timeAgo(DateTime.parse(t['last_message_at'] as String))
                                          : '',
                                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    ),
                                    if (unread > 0) ...[
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.brandTeal,
                                          borderRadius: BorderRadius.circular(PageTokens.radiusPill),
                                        ),
                                        child: Text(
                                          '$unread',
                                          style: const TextStyle(
                                            color: AppColors.onBrandTeal,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                            ],
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}
