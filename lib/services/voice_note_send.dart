import '../models/pending_message.dart';
import 'voice_note_codec.dart';

/// What the recorder produced. A failure is a value, not an exception, so the
/// dialog can show a specific reason instead of a generic "could not send".
class VoiceNoteOutcome {
  const VoiceNoteOutcome._({this.objectPath, this.failure});

  factory VoiceNoteOutcome.success(String objectPath) =>
      VoiceNoteOutcome._(objectPath: objectPath);

  factory VoiceNoteOutcome.failed(VoiceNoteFailure failure) =>
      VoiceNoteOutcome._(failure: failure);

  final String? objectPath;
  final VoiceNoteFailure? failure;

  bool get isSuccess => objectPath != null && failure == null;

  String? get content =>
      objectPath == null ? null : encodeVoiceNoteContent(objectPath!);

  String? get message => failure == null ? null : voiceNoteFailureMessage(failure!);
}

/// Voice notes enter the same durable queue as text. The send callback in
/// ChatScreen flushes this through Supa.sendMessage with retries and identity
/// checks instead of writing directly to the messages table.
PendingMessage voiceNotePendingMessage({
  required VoiceNoteOutcome outcome,
  required String conversationId,
  required String senderId,
  required String localId,
  required DateTime now,
  Duration? expiry,
}) {
  final content = outcome.content;
  if (!outcome.isSuccess || content == null) {
    throw StateError('Cannot enqueue a failed voice note.');
  }
  return PendingMessage(
    localId: localId,
    conversationId: conversationId,
    senderId: senderId,
    content: content,
    createdAt: now,
    expiresAt: expiry == null ? null : now.add(expiry),
  );
}
