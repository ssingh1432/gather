import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';

class ProfileAvatar extends StatelessWidget {
  final String? url;
  const ProfileAvatar({super.key, this.url});
  @override
  Widget build(BuildContext context) => CircleAvatar(backgroundImage: (url != null && url!.isNotEmpty) ? CachedNetworkImageProvider(url!) : null, child: url == null ? const Icon(Icons.person) : null);
}

class PostCard extends StatelessWidget {
  final PostModel post;
  final VoidCallback onLike;
  final VoidCallback onBookmark;
  final VoidCallback onComment;
  const PostCard({super.key, required this.post, required this.onLike, required this.onBookmark, required this.onComment});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(post.authorUsername ?? 'Unknown', style: Theme.of(context).textTheme.titleMedium),
            if (post.textContent.isNotEmpty) Text(post.textContent),
            if (post.imageUrl != null) Padding(padding: const EdgeInsets.only(top: 8), child: Image.network(post.imageUrl!, height: 180, fit: BoxFit.cover)),
            Row(children: [IconButton(onPressed: onLike, icon: const Icon(Icons.favorite_border)), IconButton(onPressed: onComment, icon: const Icon(Icons.comment_outlined)), IconButton(onPressed: onBookmark, icon: const Icon(Icons.bookmark_border))])
          ]),
        ),
      );
}

class CommunityCard extends StatelessWidget {
  final Map<String, dynamic> community;
  final VoidCallback onOpen;
  final VoidCallback onJoinLeave;
  const CommunityCard({super.key, required this.community, required this.onOpen, required this.onJoinLeave});
  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onOpen,
        title: Text(community['name'] ?? ''),
        subtitle: Text(community['description'] ?? ''),
        trailing: TextButton(onPressed: onJoinLeave, child: const Text('Join/Leave')),
      );
}
