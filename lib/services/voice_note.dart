import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import 'supabase.dart';
import 'legacy_messaging.dart';
import 'voice_note_codec.dart';
import 'voice_note_send.dart';

/// Recording and upload only. Playing a note is the player's job: the private
/// `chat-files` bucket needs a short-lived signed URL, which is resolved at
/// playback time by [Supa.attachmentUrl].
class VoiceNoteService {
  static final AudioRecorder _recorder = AudioRecorder();
  static const Uuid _uuid = Uuid();

  static String get _tmpPath => 'audioplayerscache/${_uuid.v4()}.m4a';

  /// Returns null when recording started, otherwise the reason it did not.
  static Future<VoiceNoteFailure?> start() async {
    if (kIsWeb) return VoiceNoteFailure.unsupportedPlatform;
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      return VoiceNoteFailure.permissionDenied;
    }
    try {
      await _recorder.stop();
      await _recorder.start(const RecordConfig(), path: _tmpPath);
      return null;
    } catch (_) {
      return VoiceNoteFailure.recorderUnavailable;
    }
  }

  /// Stops and uploads the clip. No message is written here: the caller puts
  /// the encoded content into [MessageOutbox] so it gets the same optimistic
  /// status, retries and identity checks as a text message.
  static Future<VoiceNoteOutcome> stopAndUpload(String conversationId) async {
    if (kIsWeb) {
      return VoiceNoteOutcome.failed(VoiceNoteFailure.unsupportedPlatform);
    }
    final path = await _recorder.stop();
    if (path == null) {
      return VoiceNoteOutcome.failed(VoiceNoteFailure.recorderUnavailable);
    }
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return VoiceNoteOutcome.failed(VoiceNoteFailure.uploadFailed);
      }
      final bytes = await file.readAsBytes();
      if (isVoiceNoteTooLarge(bytes.length)) {
        return VoiceNoteOutcome.failed(VoiceNoteFailure.tooLarge);
      }
      final owner = Supa.currentUser?.id;
      if (owner == null) {
        return VoiceNoteOutcome.failed(VoiceNoteFailure.sessionChanged);
      }
      try {
        LegacyMessaging.requireAllowed(owner);
      } catch (_) {
        return VoiceNoteOutcome.failed(VoiceNoteFailure.legacyDisabled);
      }
      if (Supa.currentUser?.id != owner) {
        return VoiceNoteOutcome.failed(VoiceNoteFailure.sessionChanged);
      }
      final messageId = _uuid.v4();
      final attachment = await Supa.uploadAttachment(
        conversationId,
        bytes,
        '$messageId.m4a',
        'audio/m4a',
      );
      if (Supa.currentUser?.id != owner) {
        return VoiceNoteOutcome.failed(VoiceNoteFailure.sessionChanged);
      }
      final objectPath = attachment['path'] as String?;
      if (objectPath == null || objectPath.isEmpty) {
        return VoiceNoteOutcome.failed(VoiceNoteFailure.uploadFailed);
      }
      return VoiceNoteOutcome.success(objectPath);
    } catch (_) {
      return VoiceNoteOutcome.failed(VoiceNoteFailure.uploadFailed);
    } finally {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  /// Abort an in-progress recording when the dialog is dismissed.
  static Future<void> cancel() async {
    try {
      await _recorder.stop();
    } catch (_) {}
  }
}
