import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../../core/responsive.dart';
import '../../shared/models/models.dart';
import '../data/repositories.dart';

/// Instagram-style close friends list: a private list only the owner can
/// see. Picked from your followers, since that's the natural population —
/// no point close-friending someone who can't see your posts at all.
class CloseFriendsScreen extends StatefulWidget {
  const CloseFriendsScreen({super.key});

  @override
  State<CloseFriendsScreen> createState() => _CloseFriendsScreenState();
}

class _CloseFriendsScreenState extends State<CloseFriendsScreen> {
  final _repo = ProfileRepository();
  bool _loading = true;
  String? _error;
  List<RecommendedUser> _followers = const [];
  Set<String> _closeFriendIds = {};
  final Set<String> _pending = {};

  String? get _uid => SupabaseConfig.currentUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.followersList(uid),
        _repo.closeFriendIds(uid),
      ]);
      if (mounted) {
        setState(() {
          _followers = results[0] as List<RecommendedUser>;
          _closeFriendIds = (results[1] as List<String>).toSet();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String friendId, bool add) async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _pending.add(friendId));
    try {
      if (add) {
        await _repo.addCloseFriend(uid, friendId);
        setState(() => _closeFriendIds.add(friendId));
      } else {
        await _repo.removeCloseFriend(uid, friendId);
        setState(() => _closeFriendIds.remove(friendId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    } finally {
      if (mounted) setState(() => _pending.remove(friendId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Close Friends')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : ResponsiveCenter(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          "Only you can see who's on this list.",
                          style: TextStyle(color: Theme.of(context).colorScheme.outline),
                        ),
                      ),
                      Expanded(
                        child: _followers.isEmpty
                            ? const Center(child: Text('No followers to add yet.'))
                            : ListView.builder(
                                itemCount: _followers.length,
                                itemBuilder: (context, i) {
                                  final f = _followers[i];
                                  final isMember = _closeFriendIds.contains(f.id);
                                  final busy = _pending.contains(f.id);
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundImage: f.avatarUrl != null ? NetworkImage(f.avatarUrl!) : null,
                                      child: f.avatarUrl == null ? Text(f.username.isNotEmpty ? f.username[0].toUpperCase() : '?') : null,
                                    ),
                                    title: Text(f.username),
                                    trailing: busy
                                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                        : Switch(
                                            value: isMember,
                                            onChanged: (v) => _toggle(f.id, v),
                                          ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
