import 'dart:convert';

/// Voice note transport rules shared by the recorder, the outbox and the
/// player. Keeping these pure makes the message format testable without a
/// Supabase session.
const maxVoiceNoteBytes = 20 * 1024 * 1024;
const maxVoiceNoteDuration = Duration(seconds: 60);

enum VoiceNoteFailure {
  permissionDenied,
  recorderUnavailable,
  tooLarge,
  tooLong,
  uploadFailed,
  sessionChanged,
  legacyDisabled,
  unsupportedPlatform,
}

String encodeVoiceNoteContent(String objectPath) =>
    'voice:${jsonEncode({'path': objectPath, 'mime': 'audio/m4a'})}';

String? decodeVoiceNotePath(String content) {
  if (!content.startsWith('voice:')) return null;
  try {
    final decoded = jsonDecode(content.substring(6));
    if (decoded is! Map) return null;
    final path = decoded['path'];
    return path is String && path.isNotEmpty ? path : null;
  } catch (_) {
    return null;
  }
}

bool isVoiceNoteTooLarge(int bytes) => bytes > maxVoiceNoteBytes;

bool isVoiceNoteTooLong(Duration duration) => duration > maxVoiceNoteDuration;

String voiceNoteFailureMessage(VoiceNoteFailure failure) => switch (failure) {
      VoiceNoteFailure.permissionDenied =>
        'Microphone permission is needed for voice notes.',
      VoiceNoteFailure.recorderUnavailable =>
        'The microphone could not be started on this device.',
      VoiceNoteFailure.tooLarge =>
        'That voice note is too large. Try a shorter recording.',
      VoiceNoteFailure.tooLong => 'Voice notes are limited to 60 seconds.',
      VoiceNoteFailure.uploadFailed =>
        'Could not send that voice note. Check your connection and try again.',
      VoiceNoteFailure.sessionChanged =>
        'Your session changed while recording. Try again.',
      VoiceNoteFailure.legacyDisabled =>
        'Enable legacy messaging in the chat before sending a voice note.',
      VoiceNoteFailure.unsupportedPlatform =>
        'Voice note recording is not available on web yet.',
    };
