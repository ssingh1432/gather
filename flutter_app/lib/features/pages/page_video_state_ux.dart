/// Page-only video state model used to make playback lifecycle rules explicit.
enum PageVideoPlaybackState {
  loading,
  initialized,
  playing,
  paused,
  completed,
  error,
  disposed,
}

PageVideoPlaybackState pageVideoStateAfterPlay({
  required PageVideoPlaybackState current,
}) {
  if (current == PageVideoPlaybackState.disposed ||
      current == PageVideoPlaybackState.error) {
    return current;
  }
  return PageVideoPlaybackState.playing;
}

PageVideoPlaybackState pageVideoStateAfterPause({
  required PageVideoPlaybackState current,
}) {
  if (current == PageVideoPlaybackState.playing) {
    return PageVideoPlaybackState.paused;
  }
  return current;
}

PageVideoPlaybackState pageVideoStateAfterCompletion() =>
    PageVideoPlaybackState.completed;

PageVideoPlaybackState pageVideoStateAfterReplay({
  required PageVideoPlaybackState current,
}) {
  if (current == PageVideoPlaybackState.completed ||
      current == PageVideoPlaybackState.paused ||
      current == PageVideoPlaybackState.initialized) {
    return PageVideoPlaybackState.playing;
  }
  return current;
}
