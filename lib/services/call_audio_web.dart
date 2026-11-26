// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Retries playback on every video element created by the WebRTC platform
/// views. Safe to call repeatedly; rejected promises are ignored.
void resumeRemoteVideoAudio() {
  for (final element in html.document.querySelectorAll('video')) {
    if (element is! html.VideoElement) continue;
    try {
      element.play().catchError((_) {});
    } catch (_) {}
  }
}
