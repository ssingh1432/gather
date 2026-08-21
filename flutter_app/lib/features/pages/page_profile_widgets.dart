import 'package:flutter/material.dart';

import 'pages_theme.dart';

class PageCtaRow extends StatelessWidget {
  const PageCtaRow({
    super.key,
    required this.following,
    required this.favorite,
    required this.busy,
    required this.onFollow,
    required this.onFavorite,
    required this.onMessage,
  });

  final bool following;
  final bool favorite;
  final bool busy;
  final VoidCallback onFollow;
  final VoidCallback? onFavorite;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: busy ? null : onFollow,
          icon: Icon(following ? Icons.check : Icons.person_add_alt_1_outlined),
          label: Text(following ? 'Following' : 'Follow'),
        ),
        OutlinedButton.icon(
          onPressed: onFavorite,
          icon: Icon(favorite ? Icons.star : Icons.star_outline),
          label: Text(favorite ? 'Favorited' : 'Favorite'),
        ),
        OutlinedButton.icon(
          onPressed: onMessage,
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('Message'),
        ),
      ],
    );
  }
}

class PageVisitorPostFollowGate extends StatelessWidget {
  const PageVisitorPostFollowGate({
    super.key,
    required this.busy,
    required this.onFollow,
  });

  final bool busy;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PageTokens.spaceMd),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(PageTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Follow this Page to post'),
          const SizedBox(height: PageTokens.spaceSm),
          FilledButton(
            onPressed: busy ? null : onFollow,
            child: const Text('Follow'),
          ),
        ],
      ),
    );
  }
}
