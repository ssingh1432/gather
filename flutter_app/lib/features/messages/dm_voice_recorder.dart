import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class RecordedVoice {
  const RecordedVoice({required this.bytes, required this.durationMs, required this.mime, required this.extension});
  final Uint8List bytes;
  final int durationMs;
  final String mime;
  final String extension;
}

/// Thin wrapper over `record` for voice notes. Max length matches the
/// server's 5-minute limit on `dm_messages.duration_ms`.
class DmVoiceRecorder {
  static const int maxDurationMs = 300000;

  final AudioRecorder _recorder = AudioRecorder();
  final Stopwatch _watch = Stopwatch();

  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;
    // Web records Opus/WebM; native records AAC in an .m4a container.
    final config = RecordConfig(encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc);
    var path = '';
    if (!kIsWeb) {
      final dir = await getTemporaryDirectory();
      path = '${dir.path}/dm_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    }
    await _recorder.start(config, path: path);
    _watch
      ..reset()
      ..start();
    return true;
  }

  Duration get elapsed => _watch.elapsed;

  /// Stops and returns the recording, or null if nothing was captured.
  Future<RecordedVoice?> stop() async {
    _watch.stop();
    final path = await _recorder.stop();
    if (path == null) return null;
    final bytes = await XFile(path).readAsBytes();
    final ms = _watch.elapsedMilliseconds.clamp(1, maxDurationMs);
    return RecordedVoice(
      bytes: bytes,
      durationMs: ms,
      mime: kIsWeb ? 'audio/webm' : 'audio/mp4',
      extension: kIsWeb ? 'webm' : 'm4a',
    );
  }

  Future<void> cancel() async {
    _watch.stop();
    await _recorder.cancel();
  }

  Future<void> dispose() => _recorder.dispose();
}
