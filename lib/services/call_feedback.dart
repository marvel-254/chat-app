import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Short locally synthesised cues for call states. Generating bytes avoids
/// shipping audio assets and keeps the cues identical on web and mobile.
enum CallFeedbackCue { ringback, ringtone, hangup, denied }

class ToneSegment {
  const ToneSegment(this.frequencies, this.duration, {this.gapAfter = Duration.zero});

  final List<double> frequencies;
  final Duration duration;
  final Duration gapAfter;
}

const int toneSampleRate = 16000;

final Map<CallFeedbackCue, List<ToneSegment>> callCueSegments = {
  CallFeedbackCue.ringback: const [
    ToneSegment([440, 480], Duration(milliseconds: 700),
        gapAfter: Duration(milliseconds: 300)),
    ToneSegment([440, 480], Duration(milliseconds: 700),
        gapAfter: Duration(milliseconds: 2300)),
  ],
  CallFeedbackCue.ringtone: const [
    ToneSegment([660, 880], Duration(milliseconds: 500),
        gapAfter: Duration(milliseconds: 250)),
    ToneSegment([660, 880], Duration(milliseconds: 500),
        gapAfter: Duration(milliseconds: 1250)),
    ToneSegment([660, 880], Duration(milliseconds: 500),
        gapAfter: Duration(milliseconds: 2000)),
  ],
  CallFeedbackCue.hangup: const [
    ToneSegment([660], Duration(milliseconds: 180)),
    ToneSegment([494], Duration(milliseconds: 180)),
    ToneSegment([330], Duration(milliseconds: 220)),
  ],
  CallFeedbackCue.denied: const [
    ToneSegment([220], Duration(milliseconds: 160),
        gapAfter: Duration(milliseconds: 80)),
    ToneSegment([196], Duration(milliseconds: 220)),
  ],
};

/// Builds a mono 16-bit PCM WAV. Pure so cadence and headers can be tested.
Uint8List buildToneWav(
  List<ToneSegment> segments, {
  int sampleRate = toneSampleRate,
  double volume = 0.18,
}) {
  final total = segments.fold<Duration>(
    Duration.zero,
    (sum, segment) => sum + segment.duration + segment.gapAfter,
  );
  final sampleCount = (total.inMilliseconds * sampleRate / 1000).round();
  final pcm = ByteData(sampleCount * 2);
  var written = 0;
  for (final segment in segments) {
    final toneSamples =
        (segment.duration.inMilliseconds * sampleRate / 1000).round();
    final gapSamples =
        (segment.gapAfter.inMilliseconds * sampleRate / 1000).round();
    for (var i = 0; i < toneSamples + gapSamples && written < sampleCount; i++) {
      final t = i / sampleRate;
      var amplitude = 0.0;
      if (i < toneSamples) {
        for (final frequency in segment.frequencies) {
          amplitude +=
              math.sin(2 * math.pi * frequency * t);
        }
        amplitude = amplitude / segment.frequencies.length;
        // Short fades remove the click at each tone edge.
        final fadeSamples = (sampleRate * 0.012).round();
        final edge = i < fadeSamples
            ? i / fadeSamples
            : (toneSamples - i < fadeSamples
                ? (toneSamples - i) / fadeSamples
                : 1.0);
        amplitude *= edge.clamp(0.0, 1.0);
      }
      pcm.setInt16(written * 2, (amplitude * volume * 32767).round(),
          Endian.little);
      written++;
    }
  }
  final header = ByteData(44);
  void ascii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      header.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  final dataSize = written * 2;
  ascii(0, 'RIFF');
  header.setUint32(4, 36 + dataSize, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, dataSize, Endian.little);
  final bytes = Uint8List(44 + dataSize);
  bytes.setRange(0, 44, header.buffer.asUint8List());
  bytes.setRange(44, 44 + dataSize, pcm.buffer.asUint8List(0, dataSize));
  return bytes;
}

Uint8List buildCueWav(CallFeedbackCue cue) => buildToneWav(callCueSegments[cue]!);

/// Owns a single player so cues never overlap. All failures are swallowed:
/// a missing audio device must never break call setup.
class CallFeedback {
  CallFeedback({AudioPlayer? player, this.enabled = true})
      : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  bool enabled;

  void setEnabled(bool value) {
    enabled = value;
    if (!enabled) unawaited(stop());
  }

  Future<void> play(CallFeedbackCue cue) async {
    if (!enabled) return;
    try {
      await _player.stop();
      await _player.play(
        BytesSource(buildCueWav(cue), mimeType: 'audio/wav'),
        volume: cue == CallFeedbackCue.hangup || cue == CallFeedbackCue.denied
            ? 0.5
            : 0.35,
      );
    } catch (_) {
      // Browser autoplay policy or no output device: visual states still work.
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
