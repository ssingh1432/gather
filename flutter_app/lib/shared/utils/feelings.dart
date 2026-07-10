class FeelingOption {
  final String label;
  final String emoji;
  const FeelingOption(this.label, this.emoji);

  /// What gets stored on the post, e.g. "😊 happy".
  String get stored => '$emoji $label';
}

const List<FeelingOption> kFeelingOptions = [
  FeelingOption('happy', '😊'),
  FeelingOption('blessed', '🙏'),
  FeelingOption('excited', '🤩'),
  FeelingOption('loved', '🥰'),
  FeelingOption('grateful', '💚'),
  FeelingOption('celebrating', '🎉'),
  FeelingOption('proud', '😌'),
  FeelingOption('tired', '😴'),
  FeelingOption('sad', '😢'),
  FeelingOption('motivated', '💪'),
];

/// Pulls just the emoji back out of a stored "emoji label" string so the
/// post card can show it beside the location without re-parsing elsewhere.
String? feelingEmoji(String? stored) {
  if (stored == null || stored.trim().isEmpty) return null;
  final firstToken = stored.trim().split(' ').first;
  return firstToken;
}

/// The human-readable part of a stored feeling, e.g. "happy" from "😊 happy".
String feelingLabel(String stored) {
  final parts = stored.trim().split(' ');
  if (parts.length <= 1) return stored.trim();
  return parts.sublist(1).join(' ');
}
