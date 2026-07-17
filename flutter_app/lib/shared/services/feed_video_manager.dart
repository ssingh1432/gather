import 'dart:async';

import 'package:flutter/foundation.dart';

/// Coordinates video autoplay across the whole feed: exactly one video
/// plays at a time (the most visible one), matching how every major app
/// with a scrolling video feed does it. Running a `VideoPlayerController`
/// per visible item would be a real memory/perf risk in a long list, so
/// individual post widgets report their visibility here and only build a
/// controller once they're told they're the active one.
class FeedVideoManager {
  FeedVideoManager._();
  static final FeedVideoManager instance = FeedVideoManager._();

  final ValueNotifier<String?> activePostId = ValueNotifier<String?>(null);

  final Map<String, double> _visibleFractions = {};
  Timer? _debounce;

  void reportVisibility(String postId, double fraction) {
    if (fraction < 0.6) {
      _visibleFractions.remove(postId);
    } else {
      _visibleFractions[postId] = fraction;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _recompute);
  }

  void reportDisposed(String postId) {
    _visibleFractions.remove(postId);
    if (activePostId.value == postId) {
      _recompute();
    }
  }

  void _recompute() {
    if (_visibleFractions.isEmpty) {
      activePostId.value = null;
      return;
    }
    final best = _visibleFractions.entries.reduce((a, b) => b.value > a.value ? b : a);
    activePostId.value = best.key;
  }
}
