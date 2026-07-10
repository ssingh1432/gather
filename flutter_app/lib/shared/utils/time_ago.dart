/// Minimal relative-time formatter (e.g. "3m", "5h", "2d", "Jan 4") so post
/// and comment timestamps read the way people expect from a social feed
/// without pulling in the `intl`/`timeago` packages.
String timeAgo(DateTime dateTime) {
  final now = DateTime.now();
  final diff = now.difference(dateTime.toLocal());

  if (diff.inSeconds < 5) return 'now';
  if (diff.inMinutes < 1) return '${diff.inSeconds}s';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  if (diff.inDays < 365) {
    final local = dateTime.toLocal();
    return '${_month(local.month)} ${local.day}';
  }
  final local = dateTime.toLocal();
  return '${_month(local.month)} ${local.day}, ${local.year}';
}

String _month(int month) => const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][month - 1];
