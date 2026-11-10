import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../shared/utils/time_ago.dart';
import '../../shared/widgets/reusables.dart';
import 'dm_e2ee_session.dart';
import 'dm_models.dart';
import 'dm_realtime_service.dart';
import 'dm_repository.dart';

/// Phase 11 — 1:1 message inbox: pinned chats first, unread badges, mute and
/// archive, plus the "who can message me" privacy setting.
class DmInboxScreen extends StatefulWidget {
  const DmInboxScreen({super.key});

  @override
  State<DmInboxScreen> createState() => _DmInboxScreenState();
}

class _DmInboxScreenState extends State<DmInboxScreen> {
  final _repo = DmRepository();
  final _e2ee = DmE2eeSession();
  DmInboxRealtime? _realtime;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _debounce;

  List<DmConversation> _conversations = const [];
  final Map<String, String> _previews = {};
  bool _loading = true;
  bool _showArchived = false;
  String? _error;

  String? get _uid => SupabaseConfig.currentUserId;

  @override
  void initState() {
    super.initState();
    final uid = _uid;
    if (uid != null) {
      // Registers this account's public key so others can encrypt to us.
      _e2ee.prepare(uid);
      _realtime = DmInboxRealtime(uid)..subscribe();
      _sub = _realtime!.events.listen(_onEvent);
    }
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    _realtime?.dispose();
    super.dispose();
  }

  void _onEvent(Map<String, dynamic> record) {
    final uid = _uid;
    final conv = record['conversation_id']?.toString();
    if (uid != null && conv != null && record['sender_id']?.toString() != uid) {
      _repo.markDelivered(conv).catchError((_) {});
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _load(silent: true);
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final list = await _repo.listConversations(archived: _showArchived);
      final previews = <String, String>{};
      for (final c in list) {
        previews[c.id] = await _previewFor(c);
      }
      if (!mounted) return;
      setState(() {
        _conversations = list;
        _previews
          ..clear()
          ..addAll(previews);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = 'Could not load messages.';
      });
    }
  }

  Future<String> _previewFor(DmConversation c) async {
    if (c.lastKind == null) return 'Say hello';
    if (c.lastDeleted) return 'Message deleted';
    final prefix = c.lastSenderId == _uid ? 'You: ' : '';
    final label = dmKindLabel(c.lastKind!);
    if (label != null) return '$prefix$label';
    if (c.lastEncVersion == 1) {
      final uid = _uid;
      if (uid == null) return '$prefix🔒 Encrypted message';
      final key = await _e2ee.keyFor(userId: uid, conversationId: c.id, otherUserId: c.otherUserId);
      final text = await _e2ee.decrypt(key: key, conversationId: c.id, ciphertext: c.lastCiphertext, nonce: c.lastNonce);
      return text == null ? '$prefix🔒 Encrypted message' : '$prefix$text';
    }
    return '$prefix${c.lastBody ?? ''}';
  }

  Future<void> _openChat(DmConversation c) async {
    await context.push(
      '/dm-chat?id=${Uri.encodeComponent(c.id)}&user=${Uri.encodeComponent(c.otherUserId)}&name=${Uri.encodeComponent(c.otherUsername)}',
    );
    if (mounted) _load(silent: true);
  }

  Future<void> _showActions(DmConversation c) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(c.isPinned ? Icons.push_pin_outlined : Icons.push_pin),
              title: Text(c.isPinned ? 'Unpin chat' : 'Pin chat'),
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
            ListTile(
              leading: Icon(c.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
              title: Text(c.isArchived ? 'Unarchive chat' : 'Archive chat'),
              onTap: () => Navigator.pop(ctx, 'archive'),
            ),
            ListTile(
              leading: Icon(c.isMutedAt(DateTime.now()) ? Icons.notifications_active_outlined : Icons.notifications_off_outlined),
              title: Text(c.isMutedAt(DateTime.now()) ? 'Unmute' : 'Mute notifications'),
              onTap: () => Navigator.pop(ctx, 'mute'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    try {
      switch (choice) {
        case 'pin':
          await _repo.setFlags(c.id, pinned: !c.isPinned);
        case 'archive':
          await _repo.setFlags(c.id, archived: !c.isArchived);
        case 'mute':
          if (c.isMutedAt(DateTime.now())) {
            await _repo.setFlags(c.id, unmute: true);
          } else {
            await _repo.setFlags(c.id, mutedUntil: DateTime.now().add(const Duration(days: 3650)));
          }
      }
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(dmErrorMessage(e))));
    }
  }

  Future<void> _openPrivacy() async {
    final uid = _uid;
    if (uid == null) return;
    var current = 'everyone';
    try {
      current = await _repo.getMyDmPrivacy(uid);
    } catch (_) {}
    if (!mounted) return;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Who can message you'),
        children: [
          for (final o in const [
            ('everyone', 'Everyone'),
            ('following', 'People I follow'),
            ('nobody', 'No one'),
          ])
            ListTile(
              leading: Icon(current == o.$1 ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(o.$2),
              onTap: () => Navigator.pop(ctx, o.$1),
            ),
        ],
      ),
    );
    if (picked == null || picked == current) return;
    try {
      await _repo.setMyDmPrivacy(uid, picked);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message privacy updated.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update privacy setting.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? 'Archived chats' : 'Messages'),
        actions: [
          IconButton(
            tooltip: _showArchived ? 'Show chats' : 'Archived',
            icon: Icon(_showArchived ? Icons.inbox_outlined : Icons.archive_outlined),
            onPressed: () {
              setState(() => _showArchived = !_showArchived);
              _load();
            },
          ),
          IconButton(tooltip: 'Message privacy', icon: const Icon(Icons.lock_outline), onPressed: _openPrivacy),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetryState(title: 'Unable to load messages', message: _error!, onRetry: _load)
              : _conversations.isEmpty
                  ? EmptyState(
                      icon: Icons.chat_bubble_outline,
                      title: _showArchived ? 'No archived chats' : 'No messages yet',
                      message: _showArchived ? null : 'Open someone\'s profile and tap Message to start a conversation.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _conversations.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final c = _conversations[i];
                          final muted = c.isMutedAt(DateTime.now());
                          return ListTile(
                            leading: ProfileAvatar(url: c.otherAvatarUrl, radius: 22),
                            title: Text(c.otherUsername, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: c.unreadCount > 0 ? FontWeight.w700 : FontWeight.w500)),
                            subtitle: Text(_previews[c.id] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: c.unreadCount > 0 ? FontWeight.w600 : FontWeight.normal)),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(timeAgo(c.lastMessageAt), style: Theme.of(context).textTheme.bodySmall),
                                const SizedBox(height: 4),
                                Row(mainAxisSize: MainAxisSize.min, children: [
                                  if (c.isPinned) Icon(Icons.push_pin, size: 14, color: scheme.outline),
                                  if (muted) Icon(Icons.notifications_off, size: 14, color: scheme.outline),
                                  if (c.unreadCount > 0)
                                    Container(
                                      margin: const EdgeInsets.only(left: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(10)),
                                      child: Text('${c.unreadCount}', style: TextStyle(color: scheme.onPrimary, fontSize: 11)),
                                    ),
                                ]),
                              ],
                            ),
                            onTap: () => _openChat(c),
                            onLongPress: () => _showActions(c),
                          );
                        },
                      ),
                    ),
    );
  }
}
