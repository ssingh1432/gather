import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/utils/time_ago.dart';
import '../../shared/widgets/reusables.dart';

/// Page-only comment/reply presentation.
/// Reply chains are visually flat; parent_comment_id remains authoritative.
class PageCommentsUx extends StatelessWidget {
  const PageCommentsUx({
    super.key,
    required this.comments,
    required this.loading,
    required this.sending,
    required this.replyingTo,
    required this.onReply,
    required this.onCancelReply,
    required this.onSubmit,
    required this.controller,
    required this.focusNode,
  });

  final List<Map<String, dynamic>> comments;
  final bool loading;
  final bool sending;
  final Map<String, dynamic>? replyingTo;
  final void Function(Map<String, dynamic>) onReply;
  final VoidCallback onCancelReply;
  final VoidCallback onSubmit;
  final TextEditingController controller;
  final FocusNode focusNode;

  Map<String, dynamic> _user(Map<String, dynamic> c) => c['users'] is Map
      ? Map<String, dynamic>.from(c['users'] as Map)
      : <String, dynamic>{};

  String _username(Map<String, dynamic> c) {
    final value = _user(c)['username']?.toString().trim();
    return value?.isNotEmpty == true ? value! : 'user';
  }

  String _userId(Map<String, dynamic> c) => c['user_id']?.toString() ?? '';

  String? _avatar(Map<String, dynamic> c) {
    final value = _user(c)['profile_photo_url']?.toString();
    return value?.isNotEmpty == true ? value : null;
  }

  Map<String, dynamic>? _parentOf(Map<String, dynamic> comment) {
    final parentId = comment['parent_comment_id']?.toString();
    if (parentId == null || parentId.isEmpty) return null;
    for (final candidate in comments) {
      if (candidate['id']?.toString() == parentId) return candidate;
    }
    return null;
  }

  List<Map<String, dynamic>> _threadReplies(String rootId) {
    final byParent = <String, List<Map<String, dynamic>>>{};
    for (final c in comments) {
      final parent = c['parent_comment_id']?.toString();
      if (parent != null && parent.isNotEmpty) {
        byParent.putIfAbsent(parent, () => <Map<String, dynamic>>[]).add(c);
      }
    }

    final result = <Map<String, dynamic>>[];
    final queue = List<Map<String, dynamic>>.from(byParent[rootId] ?? const []);
    final seen = <String>{rootId};
    while (queue.isNotEmpty) {
      final item = queue.removeAt(0);
      final id = item['id']?.toString();
      if (id == null || !seen.add(id)) continue;
      result.add(item);
      queue.addAll(byParent[id] ?? const []);
    }
    return result;
  }

  Widget _row(BuildContext context, Map<String, dynamic> comment, {Map<String, dynamic>? replyTo}) {
    final theme = Theme.of(context);
    final authorId = _userId(comment);
    final targetId = replyTo == null ? '' : _userId(replyTo);
    final targetUsername = replyTo == null ? null : _username(replyTo);
    final created = DateTime.tryParse(comment['created_at']?.toString() ?? '');
    final commentId = comment['id']?.toString() ?? 'unknown';

    return Padding(
      key: ValueKey('page-comment-$commentId'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: authorId.isEmpty ? null : () => context.push('/user?id=$authorId'),
            child: ProfileAvatar(url: _avatar(comment), radius: 15),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (targetUsername != null)
                  InkWell(
                    key: ValueKey('page-reply-target-$commentId'),
                    onTap: targetId.isEmpty ? null : () => context.push('/user?id=$targetId'),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 3, bottom: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.reply_rounded, size: 14, color: theme.colorScheme.primary),
                          const SizedBox(width: 3),
                          Text('@$targetUsername', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                  decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5), borderRadius: BorderRadius.circular(13)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_username(comment), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(comment['content']?.toString() ?? '', style: theme.textTheme.bodyMedium),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 10, top: 2),
                  child: Row(children: [
                    if (created != null) Text(timeAgo(created.toLocal()), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                    if (created != null) const SizedBox(width: 12),
                    InkWell(onTap: () => onReply(comment), child: Text('Reply', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.primary))),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roots = comments.where((c) => c['parent_comment_id'] == null || c['parent_comment_id'].toString().isEmpty).toList();
    final rows = <Widget>[];
    for (final root in roots) {
      rows.add(_row(context, root));
      final rootId = root['id']?.toString();
      if (rootId == null) continue;
      for (final reply in _threadReplies(rootId)) {
        rows.add(_row(context, reply, replyTo: _parentOf(reply)));
      }
    }

    final theme = Theme.of(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .55,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
        decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : rows.isEmpty
                    ? Center(child: Text('No comments yet. Be the first to comment.', style: theme.textTheme.bodySmall))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        itemCount: rows.length,
                        itemBuilder: (_, index) => rows[index],
                      ),
          ),
          if (replyingTo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
              child: Row(children: [
                Icon(Icons.reply_rounded, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 5),
                Expanded(child: Text('Replying to @${_username(replyingTo!)}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600))),
                IconButton(onPressed: onCancelReply, icon: const Icon(Icons.close, size: 17), visualDensity: VisualDensity.compact),
              ]),
            ),
          Row(children: [
            ProfileAvatar(radius: 15),
            const SizedBox(width: 8),
            Expanded(child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                hintText: replyingTo == null ? 'Write a comment…' : 'Write a reply…',
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              ),
            )),
            IconButton(onPressed: sending ? null : onSubmit, icon: sending ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.send_rounded, color: theme.colorScheme.primary)),
          ]),
        ]),
      ),
    );
  }
}
