import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import '../../features/data/repositories.dart';
import '../../shared/models/models.dart';
import '../../shared/services/community_chat_realtime_service.dart';
import '../../shared/services/media_upload_service.dart';
import '../../shared/utils/time_ago.dart';
import '../../shared/widgets/reusables.dart';

/// Step 10 — Community Chat: a single realtime group chat per community.
/// Members can send text/media/replies; manage_chat holders can pin
/// messages, post announcements, and delete anyone's message.
class CommunityChatScreen extends StatefulWidget {
  const CommunityChatScreen({super.key, required this.communityId, this.communityName});

  final String communityId;
  final String? communityName;

  @override
  State<CommunityChatScreen> createState() => _CommunityChatScreenState();
}

class _CommunityChatScreenState extends State<CommunityChatScreen> {
  final _communityRepo = CommunityRepository();
  final _profileRepo = ProfileRepository();
  final _mediaService = MediaUploadService();
  final _composerCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late final CommunityChatRealtimeService _realtime;

  List<ChatMessageModel> _messages = []; // newest first, matches RPC order
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _sending = false;
  bool _canManageChat = false;
  bool _isAnnouncementMode = false;
  ChatMessageModel? _replyTo;
  String? _error;

  Timer? _typingStoppedTimer;
  final Map<String, String> _typingUsers = {}; // userId -> username

  String? get _uid => SupabaseConfig.maybeClient?.auth.currentUser?.id;
  String _username = 'Someone'; // resolved in _load() via ProfileRepository — auth user_metadata isn't reliably in sync with public.users.username

  @override
  void initState() {
    super.initState();
    _realtime = CommunityChatRealtimeService(widget.communityId);
    _realtime.subscribe();
    _realtime.messages.listen(_onRealtimeEvent);
    _realtime.typing.listen(_onTypingSignal);
    _scrollCtrl.addListener(_maybeLoadMore);
    _load();
  }

  @override
  void dispose() {
    _typingStoppedTimer?.cancel();
    _realtime.dispose();
    _composerCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = _uid;
      final canManage = await _communityRepo.hasPermission(widget.communityId, 'manage_chat');
      final messages = await _communityRepo.fetchChatMessages(widget.communityId);
      final myProfile = uid != null ? await _profileRepo.loadProfile(uid) : null;
      if (!mounted) return;
      setState(() {
        _canManageChat = canManage;
        _messages = messages;
        _hasMore = messages.length >= 40;
        _loading = false;
        if (myProfile?['username'] is String) _username = myProfile!['username'] as String;
      });
      _markRead();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load chat. Pull down to retry.';
        _loading = false;
      });
    }
  }

  Future<void> _maybeLoadMore() async {
    if (_loadingMore || !_hasMore) return;
    // Reversed ListView: "load more" (older history) triggers near the
    // bottom of the scroll extent, since position 0 is the newest message.
    if (_scrollCtrl.position.pixels < _scrollCtrl.position.maxScrollExtent - 400) return;
    setState(() => _loadingMore = true);
    try {
      final oldest = _messages.isEmpty ? null : _messages.last.createdAt;
      final more = await _communityRepo.fetchChatMessages(widget.communityId, before: oldest);
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, ...more];
        _hasMore = more.length >= 40;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _markRead() {
    if (_messages.isEmpty) return;
    _communityRepo.markChatRead(widget.communityId, lastMessageId: _messages.first.id).catchError((_) {});
  }

  void _onRealtimeEvent(CommunityChatRealtimeEvent event) {
    // Simplest correct approach for a group chat at this scale: any insert
    // or update triggers a targeted refetch of the latest page rather than
    // hand-patching the joined RPC shape (sender/media/reply preview) from
    // a raw Postgres Changes payload, which only ever contains the bare
    // row. This keeps the client's view always in sync with what RLS and
    // the RPC actually compute (e.g. blocked-user filtering).
    if (!mounted) return;
    _refreshLatest();
  }

  Future<void> _refreshLatest() async {
    try {
      final latest = await _communityRepo.fetchChatMessages(widget.communityId);
      if (!mounted) return;
      final wasAtTop = _scrollCtrl.hasClients && _scrollCtrl.position.pixels < 80;
      setState(() {
        // Merge: keep any older pages already loaded beyond what "latest" covers.
        final latestIds = latest.map((m) => m.id).toSet();
        final olderTail = _messages.where((m) => !latestIds.contains(m.id)).toList();
        _messages = [...latest, ...olderTail];
      });
      if (wasAtTop) _markRead();
    } catch (_) {
      // Realtime is best-effort; the next pull-to-refresh or reopen will catch up.
    }
  }

  void _onTypingSignal(TypingSignal signal) {
    if (signal.userId == _uid) return;
    if (!mounted) return;
    setState(() {
      if (signal.isTyping) {
        _typingUsers[signal.userId] = signal.username;
      } else {
        _typingUsers.remove(signal.userId);
      }
    });
  }

  void _onComposerChanged(String _) {
    _realtime.sendTyping(userId: _uid ?? '', username: _username, isTyping: true);
    _typingStoppedTimer?.cancel();
    _typingStoppedTimer = Timer(const Duration(seconds: 2), () {
      _realtime.sendTyping(userId: _uid ?? '', username: _username, isTyping: false);
    });
  }

  Future<void> _send() async {
    final uid = _uid;
    final text = _composerCtrl.text.trim();
    if (uid == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _communityRepo.sendChatMessage(
        communityId: widget.communityId,
        senderId: uid,
        content: text,
        replyToId: _replyTo?.id,
        isAnnouncement: _isAnnouncementMode,
      );
      _composerCtrl.clear();
      _typingStoppedTimer?.cancel();
      _realtime.sendTyping(userId: uid, username: _username, isTyping: false);
      setState(() {
        _replyTo = null;
        _isAnnouncementMode = false;
      });
      await _refreshLatest();
      if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send message: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attachImage() async {
    final uid = _uid;
    if (uid == null) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    await _sendWithAttachment(() => _mediaService.uploadChatImage(communityId: widget.communityId, senderId: uid, image: picked), 'image');
  }

  Future<void> _attachVideo() async {
    final uid = _uid;
    if (uid == null) return;
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    await _sendWithAttachment(() => _mediaService.uploadChatVideo(communityId: widget.communityId, senderId: uid, video: picked), 'video');
  }

  Future<void> _attachFile() async {
    final uid = _uid;
    if (uid == null) return;
    final result = await FilePicker.platform.pickFiles(withData: true);
    final file = result?.files.isNotEmpty == true ? result!.files.first : null;
    if (file == null) return;
    await _sendWithAttachment(
      () => _mediaService.uploadChatDocument(communityId: widget.communityId, senderId: uid, file: file),
      'file',
      fileName: file.name,
      fileSizeBytes: file.size,
    );
  }

  Future<void> _sendWithAttachment(Future<String> Function() upload, String mediaType, {String? fileName, int? fileSizeBytes}) async {
    final uid = _uid;
    if (uid == null || _sending) return;
    setState(() => _sending = true);
    try {
      final path = await upload();
      await _communityRepo.sendChatMessage(
        communityId: widget.communityId,
        senderId: uid,
        content: _composerCtrl.text.trim().isEmpty ? null : _composerCtrl.text.trim(),
        replyToId: _replyTo?.id,
        mediaAttachments: [
          {'media_url': path, 'media_type': mediaType, 'file_name': fileName, 'file_size_bytes': fileSizeBytes},
        ],
      );
      _composerCtrl.clear();
      setState(() => _replyTo = null);
      await _refreshLatest();
      if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
    } on MediaUploadException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attachment failed to send.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _togglePin(ChatMessageModel m) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _communityRepo.setChatMessagePinned(m.id, !m.isPinned, actorId: uid);
      await _refreshLatest();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update pin.')));
    }
  }

  Future<void> _delete(ChatMessageModel m) async {
    final uid = _uid;
    if (uid == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This removes the message for everyone in the chat.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _communityRepo.deleteChatMessage(m.id, uid);
      await _refreshLatest();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete message.')));
    }
  }

  Future<void> _showPinnedMessages() async {
    final pinned = await _communityRepo.fetchChatMessages(widget.communityId, pinnedOnly: true, limit: 100);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Pinned messages', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            Expanded(
              child: pinned.isEmpty
                  ? const EmptyState(icon: Icons.push_pin_outlined, title: 'No pinned messages', message: 'Pinned messages will show up here.')
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: pinned.length,
                      itemBuilder: (ctx, i) => _MessageBubble(
                        message: pinned[i],
                        isMine: pinned[i].senderId == _uid,
                        canManage: _canManageChat,
                        onReply: null,
                        onPin: null,
                        onDelete: null,
                        mediaService: _mediaService,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typingNames = _typingUsers.values.toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.communityName != null ? '${widget.communityName} · Chat' : 'Community Chat'),
        actions: [
          IconButton(icon: const Icon(Icons.push_pin_outlined), tooltip: 'Pinned messages', onPressed: _showPinnedMessages),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorRetryState(title: 'Could not load chat', message: _error!, onRetry: _load)
                    : _messages.isEmpty
                        ? const EmptyState(icon: Icons.forum_outlined, title: 'No messages yet', message: 'Say hello to get the conversation started.')
                        : RefreshIndicator(
                            onRefresh: _refreshLatest,
                            child: ListView.builder(
                              controller: _scrollCtrl,
                              reverse: true,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: _messages.length + (_loadingMore ? 1 : 0),
                              itemBuilder: (ctx, i) {
                                if (i >= _messages.length) {
                                  return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                                }
                                final m = _messages[i];
                                return _MessageBubble(
                                  message: m,
                                  isMine: m.senderId == _uid,
                                  canManage: _canManageChat,
                                  mediaService: _mediaService,
                                  onReply: () => setState(() => _replyTo = m),
                                  onPin: _canManageChat ? () => _togglePin(m) : null,
                                  onDelete: (m.senderId == _uid || _canManageChat) ? () => _delete(m) : null,
                                );
                              },
                            ),
                          ),
          ),
          if (typingNames.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${typingNames.join(', ')} ${typingNames.length == 1 ? 'is' : 'are'} typing…',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                ),
              ),
            ),
          if (_replyTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Expanded(
                    child: Text('Replying to ${_replyTo!.senderUsername}: ${_replyTo!.content ?? '[attachment]'}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                  ),
                  IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _replyTo = null)),
                ],
              ),
            ),
          if (_canManageChat)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.campaign_outlined, size: 18),
                  const SizedBox(width: 6),
                  const Text('Announcement', style: TextStyle(fontSize: 13)),
                  Switch(value: _isAnnouncementMode, onChanged: (v) => setState(() => _isAnnouncementMode = v)),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.attach_file),
                    enabled: !_sending,
                    onSelected: (v) {
                      if (v == 'image') _attachImage();
                      if (v == 'video') _attachVideo();
                      if (v == 'file') _attachFile();
                    },
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(value: 'image', child: Text('Photo')),
                      PopupMenuItem(value: 'video', child: Text('Video')),
                      PopupMenuItem(value: 'file', child: Text('File')),
                    ],
                  ),
                  Expanded(
                    child: TextField(
                      controller: _composerCtrl,
                      onChanged: _onComposerChanged,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 4000,
                      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                      decoration: InputDecoration(
                        hintText: _isAnnouncementMode ? 'Write an announcement…' : 'Message…',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _sending
                      ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(icon: const Icon(Icons.send), onPressed: _send),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.canManage,
    required this.mediaService,
    this.onReply,
    this.onPin,
    this.onDelete,
  });

  final ChatMessageModel message;
  final bool isMine;
  final bool canManage;
  final MediaUploadService mediaService;
  final VoidCallback? onReply;
  final VoidCallback? onPin;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAnnouncement = message.isAnnouncement;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMine) Padding(padding: const EdgeInsets.only(right: 8, top: 4), child: ProfileAvatar(url: message.senderAvatarUrl, radius: 14)),
          Flexible(
            child: GestureDetector(
              onLongPress: (onReply == null && onPin == null && onDelete == null) ? null : () => _showActions(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isAnnouncement
                      ? theme.colorScheme.tertiaryContainer
                      : isMine
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                  border: isAnnouncement ? Border.all(color: theme.colorScheme.tertiary) : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isMine || isAnnouncement)
                      Row(
                        children: [
                          if (isAnnouncement) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.campaign, size: 14)),
                          Text(message.senderUsername, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
                          if (message.isPinned) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.push_pin, size: 12)),
                        ],
                      ),
                    if (message.replyToId != null)
                      Container(
                        margin: const EdgeInsets.only(top: 2, bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: theme.colorScheme.surface.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          message.replyToRemoved
                              ? 'Original message removed'
                              : '${message.replyToSenderUsername ?? ''}: ${message.replyToContent ?? '[attachment]'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (message.isDeleted)
                      Text('Message deleted', style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: theme.colorScheme.outline))
                    else ...[
                      if (message.content != null && message.content!.isNotEmpty) Text(message.content!, style: theme.textTheme.bodyMedium),
                      for (final media in message.media) _ChatMediaThumb(media: media, mediaService: mediaService),
                    ],
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(timeAgo(message.createdAt), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                        if (message.editedAt != null)
                          Text('  ·  edited', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            if (onReply != null)
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(ctx);
                  onReply!();
                },
              ),
            if (onPin != null)
              ListTile(
                leading: Icon(message.isPinned ? Icons.push_pin_outlined : Icons.push_pin),
                title: Text(message.isPinned ? 'Unpin' : 'Pin'),
                onTap: () {
                  Navigator.pop(ctx);
                  onPin!();
                },
              ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete'),
                onTap: () {
                  Navigator.pop(ctx);
                  onDelete!();
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Resolves a private chat attachment's signed URL on demand (the stored
/// `media_url` is a storage path, not a public URL — see
/// `MediaUploadService.createChatMediaSignedUrl`) and renders it.
class _ChatMediaThumb extends StatefulWidget {
  const _ChatMediaThumb({required this.media, required this.mediaService});
  final ChatMediaModel media;
  final MediaUploadService mediaService;

  @override
  State<_ChatMediaThumb> createState() => _ChatMediaThumbState();
}

class _ChatMediaThumbState extends State<_ChatMediaThumb> {
  String? _signedUrl;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final url = await widget.mediaService.createChatMediaSignedUrl(widget.media.mediaUrl);
      if (mounted) setState(() => _signedUrl = url);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.media.mediaType == 'file') {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_outlined, size: 18),
            const SizedBox(width: 6),
            Flexible(child: Text(widget.media.fileName ?? 'File', overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
    }

    if (_failed) return const Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.broken_image_outlined));
    if (_signedUrl == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 4),
        child: SizedBox(width: 120, height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: widget.media.mediaType == 'image'
            ? Image.network(_signedUrl!, width: 200, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined))
            : Container(
                width: 200,
                height: 120,
                color: Colors.black12,
                child: const Center(child: Icon(Icons.play_circle_outline, size: 40)),
              ),
      ),
    );
  }
}
