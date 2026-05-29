import 'package:flutter/material.dart';

import '../data/repositories.dart';
import '../../core/supabase_client.dart';
import '../../shared/widgets/auth_redirects.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.postId});
  final String postId;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final repo = FeedRepository();
  final commentCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Post')),
        body: FutureBuilder(
          future: Future.wait([repo.getPost(widget.postId), repo.comments(widget.postId)]),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final post = snapshot.data![0] as dynamic;
            final comments = snapshot.data![1] as List<Map<String, dynamic>>;
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(post.authorUsername ?? 'Unknown', style: Theme.of(context).textTheme.titleMedium),
                Text(post.textContent),
                const Divider(),
                ...comments.map((c) => ListTile(title: Text(c['users']?['username'] ?? 'User'), subtitle: Text(c['content'] ?? ''))),
                TextField(controller: commentCtrl, decoration: const InputDecoration(labelText: 'Add comment')),
                ElevatedButton(
                  onPressed: () async {
                    final uid = SupabaseConfig.client.auth.currentUser?.id;
                    if (uid == null) {
                      redirectToLogin(
                        context,
                        redirect: '/post?id=${widget.postId}',
                        message: 'Please log in or create an account to comment.',
                      );
                      return;
                    }
                    if (commentCtrl.text.trim().isEmpty) return;
                    await repo.addComment(widget.postId, uid, commentCtrl.text.trim());
                    setState(() => commentCtrl.clear());
                  },
                  child: const Text('Comment'),
                )
              ],
            );
          },
        ),
      );
}
