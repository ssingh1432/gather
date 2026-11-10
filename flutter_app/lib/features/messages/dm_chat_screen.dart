import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase_client.dart';
import '../../shared/utils/time_ago.dart';
import 'dm_e2ee_session.dart';
import 'dm_models.dart';
import 'dm_realtime_service.dart';
import 'dm_repository.dart';
import 'dm_voice_recorder.dart';

const _reactionChoices = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

String dmMimeForName(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  const map = {
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'webp': 'image/webp', 'gif': 'image/gif',
    'mp4': 'video/mp4', 'mov': 'video/quicktime', 'webm': 'video/webm',
    'pdf': 'application/pdf', 'txt': 'text/plain', 'zip': 'application/zip',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  };
  return map[ext] ?? 'application/octet-stream';
}

DmKind dmKindForMime(String mime) {
  if (mime.startsWith('image/')) return DmKind.image;
  if (mime.startsWith('video/')) return DmKind.video;
  return DmKind.file;
}

/// Phase 11 — 1:1 chat: text (end-to-end encrypted when both sides have
/// keys), images, video, files, voice notes, replies, forwards, reactions,
/// typing indicator, delivered/read ticks, delete for me / for everyone.
class DmChatScreen extends StatefulWidget {
  const DmChatScreen({super.key, required this.conversationId, required this.otherUserId, this.otherUsername});

  final String conversationId;
  final String otherUserId;
  final String? otherUsername;

  @override
  State<DmChatScreen> createState() => _DmChatScreenState();
}

class _DmChatScreenState extends State<DmChatScreen> {
  final _repo = DmRepository();
  final _e2ee = DmE2eeSession();
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = DmVoiceRecorder();
  late final DmRealtimeService _realtime;
  final List<StreamSubscription<Object?>> _subs = [];

  List<DmMessage> _messages = []; // newest first
  final Map<String, String> _plain = {}; // message id -> decrypted text
  final Map<String, String> _replyPlain = {}; // reply-target id -> decrypted text
  DateTime? _otherReadAt;
  DateTime? _otherDeliveredAt;
  DmMessage? _replyTo;
  SecretKey? _key;
  DmKeyState? _keyState;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _sending = false;
  bool _recording = false;
  bool _otherTyping = false;
  Timer? _typingStop;
  Timer? _otherTypingExpire;
  Timer? _recordTick;
  Duration _recordElapsed = Duration.zero;
  String? _error;

  String? get _uid => SupabaseConfig.currentUserId;

  /// True only when we hold a usable shared key, i.e. new text is encrypted.
  bool get _encryptedActive => _key != null && _keyState == DmKeyState.ready;

  @override
  void initState() {
    super.initState();
    _realtime = DmRealtimeService(widget.conversationId)..subscribe();
    _subs.add(_realtime.messages.listen((_) => _refreshLatest()));
    _subs.add(_realtime.reactions.listen((_) => _refreshLatest()));
    _subs.add(_realtime.memberState.listen(_onMemberState));
    _subs.add(_realtime.typing.listen(_onTyping));
    _scroll.addListener(_maybeLoadMore);
    _load();
  }

  @override
  void dispose() {
    _typingStop?.cancel();
    _otherTypingExpire?.cancel();
    _recordTick?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _realtime.dispose();
    _recorder.dispose();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---- loading -----------------------------------------------------------

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _keyState = await _e2ee.prepare(uid);
      _key = _keyState == DmKeyState.unavailable
          ? null
          : await _e2ee.keyFor(userId: uid, conversationId: widget.conversationId, otherUserId: widget.otherUserId);
      final msgs = await _repo.fetchMessages(widget.conversationId);
      final state = await _repo.otherMemberState(widget.conversationId, uid);
      await _decryptInto(msgs);
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _hasMore = msgs.length >= 40;
        _otherReadAt = state.lastReadAt;
        _otherDeliveredAt = state.lastDeliveredAt;
        _loading = false;
      });
      _repo.markRead(widget.conversationId).catchError((_) {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = dmErrorMessage(e);
      });
    }
  }

  Future<void> _decryptInto(List<DmMessage> msgs) async {
    for (final m in msgs) {
      if (m.isEncrypted && !m.isDeleted && !_plain.containsKey(m.id)) {
        final t = await _e2ee.decrypt(key: _key, conversationId: m.conversationId, ciphertext: m.ciphertext, nonce: m.nonce);
        if (t != null) _plain[m.id] = t;
      }
      final r = m.replyTo;
      if (r != null && r.encVersion == 1 && !r.deleted && !_replyPlain.containsKey(r.id)) {
        final t = await _e2ee.decrypt(key: _key, conversationId: m.conversationId, ciphertext: r.ciphertext, nonce: r.nonce);
        if (t != null) _replyPlain[r.id] = t;
      }
    }
  }

  Future<void> _refreshLatest() async {
    try {
      final latest = await _repo.fetchMessages(widget.conversationId);
      await _decryptInto(latest);
      if (!mounted) return;
      final ids = latest.map((m) => m.id).toSet();
      // Keep older pages already loaded; replace everything the latest page covers.
      final oldestLatest = latest.isEmpty ? null : latest.last.createdAt;
      final tail = _messages.where((m) => !ids.contains(m.id) && (oldestLatest == null || m.createdAt.isBefore(oldestLatest))).toList();
      setState(() => _messages = [...latest, ...tail]);
      _repo.markRead(widget.conversationId).catchError((_) {});
    } catch (_) {
      // Realtime is best-effort; pull-to-reopen catches up.
    }
  }

  Future<void> _maybeLoadMore() async {
    if (_loadingMore || !_hasMore || !_scroll.hasClients) return;
    if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 400) return;
    setState(() => _loadingMore = true);
    try {
      final more = await _repo.fetchMessages(widget.conversationId, before: _messages.last.createdAt);
      await _decryptInto(more);
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, ...more];
        _hasMore = more.length >= 40;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onMemberState(Map<String, dynamic> record) {
    if (record['user_id']?.toString() == _uid) return;
    final read = record['last_read_at'] as String?;
    final delivered = record['last_delivered_at'] as String?;
    setState(() {
      if (read != null) _otherReadAt = DateTime.parse(read);
      if (delivered != null) _otherDeliveredAt = DateTime.parse(delivered);
    });
  }

  void _onTyping(({String userId, bool isTyping}) s) {
    if (s.userId == _uid || !mounted) return;
    _otherTypingExpire?.cancel();
    setState(() => _otherTyping = s.isTyping);
    if (s.isTyping) {
      // Safety net if the "stopped" broadcast is lost.
      _otherTypingExpire = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _otherTyping = false);
      });
    }
  }

  void _onComposerChanged(String _) {
    final uid = _uid;
    if (uid == null) return;
    _realtime.sendTyping(userId: uid, isTyping: true);
    _typingStop?.cancel();
    _typingStop = Timer(const Duration(seconds: 2), () => _realtime.sendTyping(userId: uid, isTyping: false));
  }

  // ---- sending -----------------------------------------------------------

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _sendText() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    if (_keyState == DmKeyState.mismatch) {
      _toast('Encryption keys for this account are on another device. Reset keys from the ⋮ menu to continue.');
      return;
    }
    setState(() => _sending = true);
    try {
      if (_key == null) {
        // Recipient has no key yet (hasn't opened Messages): send unencrypted
        // — the header shows this state — rather than blocking the chat.
        _key = await _e2ee.keyFor(userId: _uid ?? '', conversationId: widget.conversationId, otherUserId: widget.otherUserId);
      }
      final key = _key;
      if (key != null && _keyState == DmKeyState.ready) {
        final c = await _e2ee.encrypt(key: key, conversationId: widget.conversationId, plaintext: text);
        await _repo.send(
          conversationId: widget.conversationId,
          ciphertext: c.ciphertext,
          nonce: c.nonce,
          encVersion: 1,
          replyToId: _replyTo?.id,
        );
      } else {
        await _repo.send(conversationId: widget.conversationId, body: text, replyToId: _replyTo?.id);
      }
      _composer.clear();
      _typingStop?.cancel();
      final uid = _uid;
      if (uid != null) _realtime.sendTyping(userId: uid, isTyping: false);
      setState(() => _replyTo = null);
      await _refreshLatest();
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (e) {
      _toast(dmErrorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendMedia({
    required Uint8List bytes,
    required String fileName,
    required String mime,
    DmKind? kind,
    int? durationMs,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _sending = true);
    try {
      final path = await _repo.uploadMedia(
        conversationId: widget.conversationId,
        userId: uid,
        bytes: bytes,
        fileName: fileName,
        mime: mime,
      );
      await _repo.send(
        conversationId: widget.conversationId,
        kind: kind ?? dmKindForMime(mime),
        mediaPath: path,
        mediaName: fileName,
        mediaSizeBytes: bytes.length,
        mediaMime: mime,
        durationMs: durationMs,
        replyToId: _replyTo?.id,
      );
      setState(() => _replyTo = null);
      await _refreshLatest();
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } on StateError catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast(dmErrorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 2048);
    if (file == null) return;
    final mime = dmMimeForName(file.name);
    if (!mime.startsWith('image/')) {
      _toast('Only JPG, PNG, WebP or GIF images can be sent.');
      return;
    }
    await _sendMedia(bytes: await file.readAsBytes(), fileName: file.name, mime: mime);
  }

  Future<void> _pickVideo() async {
    final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    final mime = dmMimeForName(file.name);
    if (!mime.startsWith('video/')) {
      _toast('Unsupported video format.');
      return;
    }
    await _sendMedia(bytes: await file.readAsBytes(), fileName: file.name, mime: mime);
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    final f = res?.files.single;
    if (f == null || f.bytes == null) return;
    final mime = dmMimeForName(f.name);
    if (mime == 'application/octet-stream') {
      _toast('That file type is not supported.');
      return;
    }
    await _sendMedia(bytes: f.bytes!, fileName: f.name, mime: mime);
  }

  Future<void> _showAttachMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.image_outlined), title: const Text('Photo'), onTap: () => Navigator.pop(ctx, 'image')),
          ListTile(leading: const Icon(Icons.videocam_outlined), title: const Text('Video'), onTap: () => Navigator.pop(ctx, 'video')),
          ListTile(leading: const Icon(Icons.attach_file), title: const Text('File'), onTap: () => Navigator.pop(ctx, 'file')),
        ]),
      ),
    );
    switch (choice) {
      case 'image':
        await _pickImage();
      case 'video':
        await _pickVideo();
      case 'file':
        await _pickFile();
    }
  }

  // ---- voice -------------------------------------------------------------

  Future<void> _startRecording() async {
    try {
      final ok = await _recorder.start();
      if (!ok) {
        _toast('Microphone permission is required to record voice messages.');
        return;
      }
      setState(() {
        _recording = true;
        _recordElapsed = Duration.zero;
      });
      _recordTick = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        setState(() => _recordElapsed = _recorder.elapsed);
        if (_recorder.elapsed.inMilliseconds >= DmVoiceRecorder.maxDurationMs) _finishRecording();
      });
    } catch (_) {
      _toast('Could not start recording.');
    }
  }

  Future<void> _finishRecording() async {
    _recordTick?.cancel();
    if (!_recording) return;
    setState(() => _recording = false);
    try {
      final voice = await _recorder.stop();
      if (voice == null || voice.durationMs < 700) return; // accidental tap
      await _sendMedia(
        bytes: voice.bytes,
        fileName: 'voice.${voice.extension}',
        mime: voice.mime,
        kind: DmKind.voice,
        durationMs: voice.durationMs,
      );
    } catch (_) {
      _toast('Could not send voice message.');
    }
  }

  Future<void> _cancelRecording() async {
    _recordTick?.cancel();
    setState(() => _recording = false);
    await _recorder.cancel();
  }

  // ---- message actions ---------------------------------------------------

  String? _textOf(DmMessage m) => m.isEncrypted ? _plain[m.id] : m.body;

  Future<void> _showMessageActions(DmMessage m) async {
    if (m.isDeleted) {
      await _confirmHide(m);
      return;
    }
    final mine = m.senderId == _uid;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (final e in _reactionChoices)
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.pop(ctx, 'react:$e'),
                  child: Padding(padding: const EdgeInsets.all(8), child: Text(e, style: const TextStyle(fontSize: 26))),
                ),
            ]),
          ),
          const Divider(height: 1),
          ListTile(leading: const Icon(Icons.reply), title: const Text('Reply'), onTap: () => Navigator.pop(ctx, 'reply')),
          ListTile(leading: const Icon(Icons.forward), title: const Text('Forward'), onTap: () => Navigator.pop(ctx, 'forward')),
          if (m.kind == DmKind.text && _textOf(m) != null)
            ListTile(leading: const Icon(Icons.copy), title: const Text('Copy'), onTap: () => Navigator.pop(ctx, 'copy')),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete for me'), onTap: () => Navigator.pop(ctx, 'hide')),
          if (mine)
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: Theme.of(ctx).colorScheme.error),
              title: Text('Delete for everyone', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
        ]),
      ),
    );
    if (choice == null) return;
    try {
      if (choice.startsWith('react:')) {
        await _repo.toggleReaction(m.id, choice.substring(6));
        await _refreshLatest();
      } else if (choice == 'reply') {
        setState(() => _replyTo = m);
      } else if (choice == 'forward') {
        await _forward(m);
      } else if (choice == 'copy') {
        await Clipboard.setData(ClipboardData(text: _textOf(m) ?? ''));
        _toast('Copied');
      } else if (choice == 'hide') {
        await _repo.hideForMe(m.id);
        await _refreshLatest();
      } else if (choice == 'delete') {
        await _repo.deleteForEveryone(m.id);
        await _refreshLatest();
      }
    } catch (e) {
      _toast(dmErrorMessage(e));
    }
  }

  Future<void> _confirmHide(DmMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this deleted message?'),
        content: const Text('It will be removed from your view of the chat.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.hideForMe(m.id);
      await _refreshLatest();
    } catch (e) {
      _toast(dmErrorMessage(e));
    }
  }

  Future<void> _forward(DmMessage m) async {
    final uid = _uid;
    if (uid == null) return;
    final convs = await _repo.listConversations();
    if (!mounted) return;
    final targets = convs.where((c) => c.id != widget.conversationId).toList();
    if (targets.isEmpty) {
      _toast('Start another conversation first to forward messages.');
      return;
    }
    final target = await showModalBottomSheet<DmConversation>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Forward to', style: TextStyle(fontWeight: FontWeight.w600))),
          for (final c in targets)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(c.otherUsername),
              onTap: () => Navigator.pop(ctx, c),
            ),
        ]),
      ),
    );
    if (target == null) return;
    try {
      if (m.kind == DmKind.text) {
        final text = _textOf(m);
        if (text == null) {
          _toast("This message can't be forwarded because it can't be decrypted here.");
          return;
        }
        final key = await _e2ee.keyFor(userId: uid, conversationId: target.id, otherUserId: target.otherUserId);
        if (key != null && _keyState == DmKeyState.ready) {
          final c = await _e2ee.encrypt(key: key, conversationId: target.id, plaintext: text);
          await _repo.send(conversationId: target.id, ciphertext: c.ciphertext, nonce: c.nonce, encVersion: 1, isForwarded: true);
        } else {
          await _repo.send(conversationId: target.id, body: text, isForwarded: true);
        }
      } else {
        final path = m.mediaPath;
        if (path == null) return;
        final copied = await _repo.copyMedia(fromPath: path, toConversationId: target.id, userId: uid);
        await _repo.send(
          conversationId: target.id,
          kind: m.kind,
          mediaPath: copied,
          mediaName: m.mediaName,
          mediaSizeBytes: m.mediaSizeBytes,
          mediaMime: m.mediaMime,
          durationMs: m.durationMs,
          isForwarded: true,
        );
      }
      _toast('Forwarded to ${target.otherUsername}');
    } catch (e) {
      _toast(dmErrorMessage(e));
    }
  }

  Future<void> _chatMenu(String value) async {
    final uid = _uid;
    try {
      if (value == 'clear') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Clear this chat?'),
            content: const Text('Messages are removed from your view only. The other person keeps their copy.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
            ],
          ),
        );
        if (ok == true) {
          await _repo.clearForMe(widget.conversationId);
          await _load();
        }
      } else if (value == 'pin') {
        await _repo.setFlags(widget.conversationId, pinned: true);
        _toast('Chat pinned');
      } else if (value == 'archive') {
        await _repo.setFlags(widget.conversationId, archived: true);
        if (mounted) Navigator.of(context).maybePop();
      } else if (value == 'mute') {
        await _repo.setFlags(widget.conversationId, mutedUntil: DateTime.now().add(const Duration(days: 3650)));
        _toast('Chat muted');
      } else if (value == 'reset_keys' && uid != null) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Reset encryption keys?'),
            content: const Text(
              'This creates new keys on this device. Encrypted messages sent before the reset can no longer be read by you. Other devices signed in to your account will need to reset too.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset keys')),
            ],
          ),
        );
        if (ok == true) {
          _keyState = await _e2ee.resetKeys(uid);
          _plain.clear();
          _replyPlain.clear();
          await _load();
        }
      }
    } catch (e) {
      _toast(dmErrorMessage(e));
    }
  }

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = widget.otherUsername ?? 'Chat';
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 16)),
          Text(
            _otherTyping ? 'typing…' : (_encryptedActive ? '🔒 End-to-end encrypted' : 'Not end-to-end encrypted'),
            style: TextStyle(fontSize: 11, color: _otherTyping ? scheme.primary : scheme.outline),
          ),
        ]),
        actions: [
          PopupMenuButton<String>(
            onSelected: _chatMenu,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'pin', child: Text('Pin chat')),
              const PopupMenuItem(value: 'archive', child: Text('Archive chat')),
              const PopupMenuItem(value: 'mute', child: Text('Mute')),
              const PopupMenuItem(value: 'clear', child: Text('Clear chat for me')),
              const PopupMenuItem(value: 'reset_keys', child: Text('Reset encryption keys')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (_keyState == DmKeyState.mismatch)
          MaterialBanner(
            content: const Text('Your encryption keys are on another device, so encrypted messages can\'t be read or sent here.'),
            actions: [TextButton(onPressed: () => _chatMenu('reset_keys'), child: const Text('Reset keys'))],
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : _messages.isEmpty
                      ? Center(child: Text('Say hello to $name', style: TextStyle(color: scheme.outline)))
                      : ListView.builder(
                          controller: _scroll,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          itemCount: _messages.length + (_loadingMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i >= _messages.length) {
                              return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                            }
                            final m = _messages[i];
                            return _MessageBubble(
                              message: m,
                              mine: m.senderId == _uid,
                              text: _textOf(m),
                              replyText: m.replyTo == null ? null : (m.replyTo!.encVersion == 1 ? _replyPlain[m.replyTo!.id] : m.replyTo!.body),
                              status: m.senderId == _uid
                                  ? m.statusFor(otherLastDeliveredAt: _otherDeliveredAt, otherLastReadAt: _otherReadAt)
                                  : null,
                              repo: _repo,
                              onLongPress: () => _showMessageActions(m),
                              onReact: (e) async {
                                try {
                                  await _repo.toggleReaction(m.id, e);
                                  await _refreshLatest();
                                } catch (err) {
                                  _toast(dmErrorMessage(err));
                                }
                              },
                            );
                          },
                        ),
        ),
        if (_replyTo != null)
          Container(
            color: scheme.surfaceContainerHighest,
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(children: [
              Icon(Icons.reply, size: 18, color: scheme.outline),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  dmKindLabel(_replyTo!.kind) ?? (_textOf(_replyTo!) ?? '🔒 Encrypted message'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _replyTo = null)),
            ]),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
            child: _recording ? _recordingBar(scheme) : _composerBar(scheme),
          ),
        ),
      ]),
    );
  }

  Widget _composerBar(ColorScheme scheme) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _composer,
      builder: (_, value, __) {
        final hasText = value.text.trim().isNotEmpty;
        return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: _sending ? null : _showAttachMenu),
          Expanded(
            child: TextField(
              controller: _composer,
              minLines: 1,
              maxLines: 5,
              maxLength: 4000,
              onChanged: _onComposerChanged,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Message', counterText: '', border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(22))), isDense: true),
            ),
          ),
          const SizedBox(width: 4),
          hasText
              ? IconButton.filled(icon: const Icon(Icons.send), onPressed: _sending ? null : _sendText)
              : IconButton.filled(icon: const Icon(Icons.mic), tooltip: 'Record voice message', onPressed: _sending ? null : _startRecording),
        ]);
      },
    );
  }

  Widget _recordingBar(ColorScheme scheme) {
    final s = _recordElapsed.inSeconds;
    final label = '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
    return Row(children: [
      IconButton(icon: Icon(Icons.delete_outline, color: scheme.error), tooltip: 'Discard', onPressed: _cancelRecording),
      Icon(Icons.fiber_manual_record, color: scheme.error, size: 14),
      const SizedBox(width: 6),
      Text('Recording $label'),
      const Spacer(),
      IconButton.filled(icon: const Icon(Icons.send), tooltip: 'Send voice message', onPressed: _finishRecording),
    ]);
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.text,
    required this.replyText,
    required this.status,
    required this.repo,
    required this.onLongPress,
    required this.onReact,
  });

  final DmMessage message;
  final bool mine;
  final String? text;
  final String? replyText;
  final DmStatus? status;
  final DmRepository repo;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = mine ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final fg = mine ? scheme.onPrimaryContainer : scheme.onSurface;
    final m = message;

    Widget body;
    if (m.isDeleted) {
      body = Text('🚫 This message was deleted', style: TextStyle(fontStyle: FontStyle.italic, color: fg.withValues(alpha: 0.7)));
    } else {
      switch (m.kind) {
        case DmKind.text:
          body = Text(
            text ?? '🔒 Can\'t decrypt on this device',
            style: TextStyle(color: text == null ? fg.withValues(alpha: 0.7) : fg, fontStyle: text == null ? FontStyle.italic : FontStyle.normal),
          );
        case DmKind.image:
          body = _DmImage(repo: repo, path: m.mediaPath);
        case DmKind.voice:
          body = _DmVoicePlayer(repo: repo, path: m.mediaPath, durationMs: m.durationMs ?? 0, color: fg);
        case DmKind.video:
        case DmKind.file:
          body = _DmFileTile(repo: repo, message: m, color: fg);
      }
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (m.isForwarded && !m.isDeleted)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('↪ Forwarded', style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.65))),
                ),
              if (m.replyTo != null && !m.isDeleted)
                Container(
                  margin: const EdgeInsets.only(bottom: 5),
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(left: BorderSide(color: scheme.primary, width: 3)),
                  ),
                  child: Text(
                    m.replyTo!.deleted ? 'Deleted message' : (dmKindLabel(m.replyTo!.kind) ?? replyText ?? '🔒 Encrypted message'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.8)),
                  ),
                ),
              body,
              if (m.reactions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(spacing: 4, children: [
                    for (final r in m.reactions)
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => onReact(r.emoji),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: r.mine ? scheme.primary.withValues(alpha: 0.2) : fg.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('${r.emoji} ${r.count}', style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                  ]),
                ),
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(timeAgo(m.createdAt), style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.6))),
                if (status != null && !m.isDeleted) ...[
                  const SizedBox(width: 4),
                  Icon(
                    status == DmStatus.sent ? Icons.check : Icons.done_all,
                    size: 14,
                    color: status == DmStatus.read ? scheme.primary : fg.withValues(alpha: 0.6),
                  ),
                ],
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DmImage extends StatelessWidget {
  const _DmImage({required this.repo, required this.path});
  final DmRepository repo;
  final String? path;

  @override
  Widget build(BuildContext context) {
    final p = path;
    if (p == null) return const SizedBox.shrink();
    return FutureBuilder<String>(
      future: repo.signedUrl(p),
      builder: (_, snap) {
        if (!snap.hasData) return const SizedBox(width: 180, height: 140, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        return GestureDetector(
          onTap: () => launchUrl(Uri.parse(snap.data!), mode: LaunchMode.externalApplication),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: snap.data!,
              width: 220,
              fit: BoxFit.cover,
              placeholder: (_, __) => const SizedBox(width: 220, height: 140),
              errorWidget: (_, __, ___) => const SizedBox(width: 220, height: 80, child: Center(child: Icon(Icons.broken_image_outlined))),
            ),
          ),
        );
      },
    );
  }
}

class _DmFileTile extends StatelessWidget {
  const _DmFileTile({required this.repo, required this.message, required this.color});
  final DmRepository repo;
  final DmMessage message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isVideo = message.kind == DmKind.video;
    final kb = ((message.mediaSizeBytes ?? 0) / 1024).round();
    final size = kb >= 1024 ? '${(kb / 1024).toStringAsFixed(1)} MB' : '$kb KB';
    return InkWell(
      onTap: () async {
        final p = message.mediaPath;
        if (p == null) return;
        final url = await repo.signedUrl(p);
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      },
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(isVideo ? Icons.play_circle_outline : Icons.insert_drive_file_outlined, color: color, size: 30),
        const SizedBox(width: 8),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(message.mediaName ?? (isVideo ? 'Video' : 'File'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color)),
            Text(size, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7))),
          ]),
        ),
      ]),
    );
  }
}

class _DmVoicePlayer extends StatefulWidget {
  const _DmVoicePlayer({required this.repo, required this.path, required this.durationMs, required this.color});
  final DmRepository repo;
  final String? path;
  final int durationMs;
  final Color color;

  @override
  State<_DmVoicePlayer> createState() => _DmVoicePlayerState();
}

class _DmVoicePlayerState extends State<_DmVoicePlayer> {
  AudioPlayer? _player;
  bool _playing = false;
  bool _loading = false;
  Duration _pos = Duration.zero;
  final List<StreamSubscription<Object?>> _subs = [];

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final p = widget.path;
    if (p == null) return;
    if (_player == null) {
      setState(() => _loading = true);
      try {
        final url = await widget.repo.signedUrl(p);
        final player = AudioPlayer();
        _subs.add(player.onPositionChanged.listen((d) {
          if (mounted) setState(() => _pos = d);
        }));
        _subs.add(player.onPlayerComplete.listen((_) {
          if (mounted) {
            setState(() {
              _playing = false;
              _pos = Duration.zero;
            });
          }
        }));
        _player = player;
        await player.play(UrlSource(url));
        if (mounted) setState(() => _playing = true);
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not play voice message.')));
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }
    if (_playing) {
      await _player!.pause();
      setState(() => _playing = false);
    } else {
      await _player!.resume();
      setState(() => _playing = true);
    }
  }

  String _fmt(int ms) {
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.durationMs <= 0 ? 1 : widget.durationMs;
    final progress = (_pos.inMilliseconds / total).clamp(0.0, 1.0);
    return SizedBox(
      width: 200,
      child: Row(children: [
        _loading
            ? const SizedBox(width: 32, height: 32, child: Padding(padding: EdgeInsets.all(6), child: CircularProgressIndicator(strokeWidth: 2)))
            : IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_fill, color: widget.color, size: 30),
                onPressed: _toggle,
              ),
        const SizedBox(width: 6),
        Expanded(child: LinearProgressIndicator(value: progress, minHeight: 3)),
        const SizedBox(width: 6),
        Text(_fmt(_playing || _pos > Duration.zero ? _pos.inMilliseconds : widget.durationMs), style: TextStyle(fontSize: 11, color: widget.color)),
      ]),
    );
  }
}
