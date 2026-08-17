import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../data/repositories.dart';
import '../../shared/utils/time_ago.dart';
import '../../shared/widgets/reusables.dart';
import 'pages_theme.dart';

/// A single Page messaging thread.
///
/// Dual mode:
///  - Customer mode (`otherUserId` null): the current user's conversation
///    with the Page.
///  - Team mode (`otherUserId` set): a customer's thread from the Page inbox.
///
/// Page messaging availability is read from the Page itself. The UI is only
/// a convenience; Supabase RLS independently enforces the same boundary.
class PageChatScreen extends StatefulWidget {
  const PageChatScreen({super.key, required this.pageId, this.pageName, this.otherUserId, this.otherUsername});

  final String pageId;
  final String? pageName;
  final String? otherUserId;
  final String? otherUsername;

  @override
  State<PageChatScreen> createState() => _PageChatScreenState();
}

class _PageChatScreenState extends State<PageChatScreen> {
  final _repo = PageRepository();
  final _composerCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = const [];
  List<Map<String, dynamic>> _quickReplies = const [];
  bool _loading = true;
  bool _sending = false;
  bool _messagingEnabled = true;
  String? _error;
  String? _pageName;
  RealtimeChannel? _channel;

  bool get _isTeamMode => widget.otherUserId != null;
  String? get _uid => SupabaseConfig.maybeClient?.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _pageName = widget.pageName;
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) SupabaseConfig.maybeClient?.removeChannel(_channel!);
    _composerCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _subscribe() {
    final client = SupabaseConfig.maybeClient;
    if (client == null) return;
    _channel = client
        .channel('public:page_messages-${widget.pageId}-${widget.otherUserId ?? _uid}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'page_messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'page_id', value: widget.pageId),
          callback: (payload) {
            final row = payload.newRecord;
            final threadUser = widget.otherUserId ?? _uid;
            if (row['user_id'] == threadUser && mounted) _load(silent: true);
          },
        )
        .subscribe();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await _repo.getPage(widget.pageId);
      final messages = await _repo.listPageMessages(widget.pageId, otherUserId: widget.otherUserId);
      final quickReplies = _isTeamMode ? await _repo.listQuickReplies(widget.pageId) : const <Map<String, dynamic>>[];
      if (_isTeamMode && widget.otherUserId != null) {
        await _repo.markPageThreadRead(widget.pageId, widget.otherUserId!);
      }
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _quickReplies = quickReplies;
        _messagingEnabled = page?['messaging_enabled'] as bool? ?? true;
        _pageName = _pageName ?? page?['name'] as String?;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = silent ? _error : 'Could not load this conversation. $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _send([String? textOverride]) async {
    if (!_messagingEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Messaging is currently disabled for this Page.')),
        );
      }
      return;
    }
    final text = (textOverride ?? _composerCtrl.text).trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _repo.sendPageMessage(widget.pageId, otherUserId: widget.otherUserId, content: text);
      _composerCtrl.clear();
      await _load(silent: true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openQuickReplies() async {
    if (!_messagingEnabled) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _QuickRepliesSheet(
        pageId: widget.pageId,
        repo: _repo,
        replies: _quickReplies,
        onChanged: () => _load(silent: true),
      ),
    );
    if (picked != null) _send(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isTeamMode ? '@${widget.otherUsername ?? 'Customer'}' : (_pageName ?? 'Page'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(18),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _isTeamMode
                  ? 'Replying as ${_pageName ?? 'the Page'}'
                  : (_messagingEnabled ? 'Message this Page' : 'Messaging is currently unavailable'),
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (!_messagingEnabled)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(PageTokens.spaceLg, PageTokens.spaceMd, PageTokens.spaceLg, 0),
              padding: const EdgeInsets.all(PageTokens.spaceMd),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(PageTokens.radiusMd),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isTeamMode
                          ? 'Messaging is disabled for this Page. You can read this conversation, but new replies are unavailable until messaging is enabled.'
                          : 'This Page is not accepting messages right now. You can read your previous conversation, but you cannot send a new message.',
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const FeedSkeletonList()
                : _error != null
                    ? ErrorRetryState(title: 'Unable to load', message: _error!, onRetry: _load)
                    : _messages.isEmpty
                        ? EmptyState(
                            icon: Icons.chat_bubble_outline,
                            title: _messagingEnabled ? 'Say hello' : 'No messages yet',
                            message: _messagingEnabled
                                ? (_isTeamMode
                                    ? 'No messages yet in this thread.'
                                    : 'Send ${_pageName ?? 'this Page'} a message and their team will get back to you.')
                                : 'Messaging is currently disabled for this Page.',
                          )
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.all(PageTokens.spaceLg),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) => _MessageBubble(message: _messages[i], mine: _isMine(_messages[i])),
                          ),
          ),
          if (_messagingEnabled)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(PageTokens.spaceSm),
                child: Row(
                  children: [
                    if (_isTeamMode)
                      IconButton(icon: const Icon(Icons.flash_on_outlined), tooltip: 'Quick replies', onPressed: _openQuickReplies),
                    Expanded(
                      child: TextField(
                        controller: _composerCtrl,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: pageFieldDecoration(context, labelText: '', hintText: 'Type a message'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      onPressed: _sending ? null : () => _send(),
                      style: IconButton.styleFrom(backgroundColor: AppColors.brandTeal, foregroundColor: AppColors.onBrandTeal),
                      icon: _sending
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrandTeal))
                          : const Icon(Icons.send, size: 18),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _isMine(Map<String, dynamic> m) {
    final senderType = m['sender_type'] as String;
    return _isTeamMode ? senderType == 'page' : senderType == 'user';
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.mine});
  final Map<String, dynamic> message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final content = message['content'] as String? ?? '';
    final automated = message['sender_type'] == 'page' && message['sent_by'] == null;
    final createdAt = DateTime.parse(message['created_at'] as String);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? AppColors.brandTeal : PageColors.surfaceMuted(context),
          borderRadius: BorderRadius.circular(PageTokens.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (automated) ...[
              Text(
                'Automated reply',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: (mine ? AppColors.onBrandTeal : Theme.of(context).colorScheme.onSurfaceVariant).withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 2),
            ],
            Text(content, style: TextStyle(color: mine ? AppColors.onBrandTeal : Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 4),
            Text(
              timeAgo(createdAt),
              style: TextStyle(fontSize: 10, color: (mine ? AppColors.onBrandTeal : Theme.of(context).colorScheme.onSurfaceVariant).withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickRepliesSheet extends StatefulWidget {
  const _QuickRepliesSheet({required this.pageId, required this.repo, required this.replies, required this.onChanged});
  final String pageId;
  final PageRepository repo;
  final List<Map<String, dynamic>> replies;
  final Future<void> Function() onChanged;

  @override
  State<_QuickRepliesSheet> createState() => _QuickRepliesSheetState();
}

class _QuickRepliesSheetState extends State<_QuickRepliesSheet> {
  late List<Map<String, dynamic>> _replies = widget.replies;
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty || content.isEmpty) return;
    setState(() => _adding = true);
    try {
      await widget.repo.addQuickReply(widget.pageId, title, content);
      await widget.onChanged();
      final refreshed = await widget.repo.listQuickReplies(widget.pageId);
      if (mounted) {
        setState(() {
          _replies = refreshed;
          _titleCtrl.clear();
          _contentCtrl.clear();
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add: $e')));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await widget.repo.deleteQuickReply(id);
      await widget.onChanged();
      if (mounted) setState(() => _replies = _replies.where((r) => r['id'] != id).toList());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(PageTokens.spaceLg),
          children: [
            Text('Quick replies', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Tap to insert into your message. Long-press to delete.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 12),
            if (_replies.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('No quick replies yet — add one below.'))
            else
              for (final r in _replies)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(r['title'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(r['content'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(context, r['content'] as String),
                    onLongPress: () => _delete(r['id'] as String),
                  ),
                ),
            const Divider(height: 24),
            Text('Add a quick reply', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(controller: _titleCtrl, decoration: pageFieldDecoration(context, labelText: 'Title', hintText: 'e.g. Store hours')),
            const SizedBox(height: 8),
            TextField(controller: _contentCtrl, minLines: 2, maxLines: 4, decoration: pageFieldDecoration(context, labelText: 'Message')),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _adding ? null : _add,
                style: FilledButton.styleFrom(backgroundColor: AppColors.brandTeal, foregroundColor: AppColors.onBrandTeal),
                child: _adding
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrandTeal))
                    : const Text('Add'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
