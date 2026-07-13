import 'package:flutter/widgets.dart';

/// Web build: ads aren't supported here, render nothing.
class FeedAdCard extends StatelessWidget {
  const FeedAdCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
