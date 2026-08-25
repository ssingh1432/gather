import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/features/pages/page_video_state_ux.dart';

void main() {
  test('Page video can move from initialized to playing', () {
    expect(
      pageVideoStateAfterPlay(
        current: PageVideoPlaybackState.initialized,
      ),
      PageVideoPlaybackState.playing,
    );
  });

  test('playing Page video moves to paused', () {
    expect(
      pageVideoStateAfterPause(
        current: PageVideoPlaybackState.playing,
      ),
      PageVideoPlaybackState.paused,
    );
  });

  test('completed Page video can replay from the beginning', () {
    expect(pageVideoStateAfterCompletion(), PageVideoPlaybackState.completed);
    expect(
      pageVideoStateAfterReplay(
        current: PageVideoPlaybackState.completed,
      ),
      PageVideoPlaybackState.playing,
    );
  });

  test('error and disposed Page video states cannot start playback', () {
    expect(
      pageVideoStateAfterPlay(current: PageVideoPlaybackState.error),
      PageVideoPlaybackState.error,
    );
    expect(
      pageVideoStateAfterPlay(current: PageVideoPlaybackState.disposed),
      PageVideoPlaybackState.disposed,
    );
  });
}
