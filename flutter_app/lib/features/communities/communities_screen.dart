import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../features/data/repositories.dart';
import '../../shared/widgets/auth_redirects.dart';
import '../../shared/widgets/reusables.dart';

class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});
  @override
  State<CommunitiesScreen> createState() => _C();
}

class _C extends State<CommunitiesScreen> {
  final repo = CommunityRepository();
  final q = TextEditingController();
  late Future<List<Map<String, dynamic>>> f = _load();
  Map<String, bool> joined = {};
  List<Map<String, dynamic>> _categoryOptions = const [];
  String? _selectedCategoryId;
  String? _selectedTagId;
  String? _selectedTagName;

  @override
  void initState() {
    super.initState();
    repo.listCategoryOptions().then((options) {
      if (mounted) setState(() => _categoryOptions = options);
    });
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final data = await repo.listCommunitiesFiltered(query: q.text.trim(), categoryId: _selectedCategoryId, tagId: _selectedTagId);
    final uid = SupabaseConfig.currentUserId;
    if (uid != null && data.isNotEmpty) {
      joined = await repo.joinedStates(data.map((e) => e['id'].toString()).toList(), uid);
    } else {
      joined = {};
    }
    return data;
  }

  void _selectCategory(String? categoryId) {
    setState(() {
      _selectedCategoryId = categoryId;
      f = _load();
    });
  }

  void _clearTagFilter() => setState(() {
        _selectedTagId = null;
        _selectedTagName = null;
        f = _load();
      });

  Future<void> _openTagFilterDialog() async {
    final controller = TextEditingController();
    List<Map<String, dynamic>> results = const [];
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Filter by tag'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'Search tags', border: OutlineInputBorder()),
                  onChanged: (query) async {
                    final r = await repo.searchTagOptions(query);
                    setDialogState(() => results = r);
                  },
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView(
                    shrinkWrap: true,
                    children: [for (final t in results) ListTile(title: Text(t['name'] as String), onTap: () => Navigator.pop(ctx, t))],
                  ),
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedTagId = picked['id'] as String;
      _selectedTagName = picked['name'] as String;
      f = _load();
    });
  }

  void _retry() => setState(() => f = _load());

  Future<void> _handleJoinLeave(Map<String, dynamic> community) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      redirectToLogin(context, redirect: '/communities', message: 'Please log in or create an account to join a community.');
      return;
    }
    final id = community['id'].toString();
    final isMember = joined[id] ?? false;
    try {
      if (isMember) {
        await repo.leaveCommunity(id, uid);
      } else {
        final result = await repo.requestJoin(id);
        if (result == 'requested' && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Join request sent. An owner or admin will review it.')),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update membership: $e')));
      return;
    }
    _retry();
  }

  Future<void> _redeemCodeDialog() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter invite code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'e.g. 73SX83G2', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Join')),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;

    try {
      final result = await repo.redeemInviteCode(code.trim());
      final communityId = result['community_id']?.toString();
      if (!mounted) return;
      final joined = result['result'] == 'joined';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(joined ? 'Joined!' : 'You\'re already a member of that community.')),
      );
      if (communityId != null) context.push('/community?id=$communityId');
      _retry();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not redeem that code: $e')));
    }
  }

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Communities'),
        actions: [
          IconButton(
            icon: const Icon(Icons.key_outlined),
            tooltip: 'Have an invite code?',
            onPressed: () {
              if (SupabaseConfig.currentUserId == null) {
                redirectToLogin(context, redirect: '/communities', message: 'Please log in or create an account to redeem an invite.');
                return;
              }
              _redeemCodeDialog();
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create community',
            onPressed: () {
              if (SupabaseConfig.currentUserId == null) {
                redirectToLogin(context, redirect: '/create-community', message: 'Please log in or create an account to create a community.');
                return;
              }
              context.push('/create-community');
            },
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: q,
            decoration: InputDecoration(
              hintText: 'Search communities',
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _retry),
            ),
            onSubmitted: (_) => _retry(),
          ),
        ),
        if (_categoryOptions.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(label: const Text('All'), selected: _selectedCategoryId == null, onSelected: (_) => _selectCategory(null)),
                ),
                for (final cat in _categoryOptions)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(cat['name'] as String),
                      selected: _selectedCategoryId == cat['id'],
                      onSelected: (_) => _selectCategory(cat['id'] as String),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (_selectedTagId == null)
                TextButton.icon(onPressed: _openTagFilterDialog, icon: const Icon(Icons.sell_outlined, size: 18), label: const Text('Filter by tag'))
              else
                Chip(label: Text('#$_selectedTagName'), onDeleted: _clearTagFilter, visualDensity: VisualDensity.compact),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder(
            future: f,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const FeedSkeletonList(itemCount: 4);
              }
              if (snapshot.hasError) {
                return ErrorRetryState(title: 'Unable to load communities', message: 'Network failure. Check your connection and try again.', onRetry: _retry);
              }
              final data = snapshot.data ?? const <Map<String, dynamic>>[];
              if (data.isEmpty) {
                return EmptyState(
                  icon: Icons.groups_outlined,
                  title: 'No communities',
                  message: q.text.trim().isEmpty ? 'Be the first to create a community.' : 'Try a different search or create it yourself.',
                  action: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Create community'),
                    onPressed: () {
                      if (SupabaseConfig.currentUserId == null) {
                        redirectToLogin(context, redirect: '/create-community', message: 'Please log in or create an account to create a community.');
                        return;
                      }
                      context.push('/create-community');
                    },
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _retry(),
                child: ListView(
                  children: data
                      .map((e) => CommunityCard(
                            community: e,
                            joined: joined[e['id'].toString()] ?? false,
                            onOpen: () => context.push('/community?id=${e['id']}'),
                            onJoinLeave: () => _handleJoinLeave(e),
                          ))
                      .toList(),
                ),
              );
            },
          ),
        )
      ]),
    );
  }
}
