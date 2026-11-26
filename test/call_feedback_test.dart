import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bro_chat/services/call_feedback.dart';

void main() {
  test('generated cues are valid mono WAV bytes', () {
    final wav = buildCueWav(CallFeedbackCue.hangup);
    final ascii = latin1.decode(wav.sublist(0, 4));
    final wave = latin1.decode(wav.sublist(8, 12));
    expect(ascii, 'RIFF');
    expect(wave, 'WAVE');

    final view = ByteData.sublistView(wav);
    expect(view.getUint16(20, Endian.little), 1); // PCM
    expect(view.getUint16(22, Endian.little), 1); // mono
    expect(view.getUint32(24, Endian.little), toneSampleRate);
    expect(view.getUint16(34, Endian.little), 16);
    expect(view.getUint32(40, Endian.little), wav.length - 44);
  });

  test('tone generator emits sound only during the tone window', () {
    final wav = buildToneWav(
      const [ToneSegment([440], Duration(milliseconds: 200), gapAfter: Duration(milliseconds: 200))],
    );
    final samples = wav.length - 44;
    expect(samples, greaterThan(0));

    final data = Float64List(samples ~/ 2);
    final view = ByteData.sublistView(wav, 44);
    for (var i = 0; i < data.length; i++) {
      data[i] = view.getInt16(i * 2, Endian.little) / 32767;
    }
    final toneEnd = (0.2 * toneSampleRate).round();
    final peakInTone = data.sublist(0, toneEnd).map((v) => v.abs()).reduce((a, b) => a > b ? a : b);
    final peakInGap = data.sublist(toneEnd + 200).map((v) => v.abs()).reduce((a, b) => a > b ? a : b);
    expect(peakInTone, greaterThan(0.05));
    expect(peakInGap, 0.0);
  });

  test('ringback and ringtone have distinct cadences', () {
    final ringback = callCueSegments[CallFeedbackCue.ringback]!;
    final ringtone = callCueSegments[CallFeedbackCue.ringtone]!;
    expect(ringback.length, 2);
    expect(ringtone.length, 3);
    expect(
      ringback.fold<Duration>(Duration.zero, (s, e) => s + e.duration + e.gapAfter),
      const Duration(seconds: 4),
    );
  });
}
