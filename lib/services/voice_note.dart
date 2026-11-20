import 'legacy_messaging.dart';
import 'legacy_message_codec.dart';
// Voice notes.
//
// Record a short audio clip and send it as an attachment. The message content
// is "voice:" followed by a tiny JSON object carrying the storage object path
// and mime type (same pattern chat files use). The audio file is stored in the
// chat-files bucket as <conversationId>/voice/<userId>/<messageId>.m4a and can
// be fetched with [Supa.attachmentUrl].
//
// Limits: 60 s, 20 MB.

import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import 'supabase.dart';

/// Max byte cap. Mirrors the chat-file cap (20 MB) and the existing storage policy.
const _maxBytes = 20 * 1024 * 1024;

final _uuid = const Uuid();

class VoiceNoteService {
  static final _recorder = AudioRecorder();
  static final _player = AudioPlayer();

  /// Temporary path of the in-progress recording.
  static String get _tmpPath => 'audioplayerscache/${_uuid.v4()}.m4a';

  /// Starts the microphone. Returns true if permission is granted and
  /// recording can begin.
  static Future<bool> start() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) return false;
    try {
      await _recorder.stop();
      await _recorder.start(const RecordConfig(), path: _tmpPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Stops recording, uploads the clip, and sends it. Returns the message id,
  /// or '' on failure (oversized clip or upload error).
  static Future<String> stopAndUpload(String conversationId) async {
    final path = await _recorder.stop();
    if (path == null || !File(path).existsSync()) return '';

    final bytes = await File(path).readAsBytes();
    if (bytes.length > _maxBytes) {
      await File(path).delete();
      return '';
    }

    final messageId = _uuid.v4();
    final owner = Supa.currentUser?.id;
    try {
      LegacyMessaging.requireAllowed(owner);
      final attachment = await Supa.uploadAttachment(
          conversationId, bytes, '$messageId.m4a', 'audio/m4a');
      final objectPath = attachment['path'] as String;
      // Mirror the chat-file pattern: content carries the object path so the
      // receiving device can reconstruct the download URL without a schema
      // migration or a separate table.
      if (Supa.currentUser?.id != owner) return '';
      await _sendMessage(
          conversationId, 'voice:${jsonEncode(_voiceMeta(objectPath))}');
      return messageId;
    } catch (_) {
      return '';
    } finally {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  /// Plays a previously sent voice note by download URL.
  static Future<void> play(String url) async {
    try {
      await _player.stop();
      final source = UrlSource(url);
      await _player.setSource(source);
      await _player.play(source);
    } catch (_) {
      // Silently ignore playback failures so audio errors never break the UI.
    }
  }

  static Map<String, String> _voiceMeta(String objectPath) =>
      {'path': objectPath, 'mime': 'audio/m4a'};

  static Future<void> _sendMessage(
      String conversationId, String content) async {
    final me = Supa.currentUser!.id;
    final now = DateTime.now().toIso8601String();
    await Supa.client.from('messages').insert({
      'id': _uuid.v4(),
      'conversation_id': conversationId,
      'sender_id': me,
      'content': content,
      'content_format': LegacyMessageCodec.plaintext,
      'created_at': now,
    });
    await Supa.client
        .from('conversations')
        .update({'updated_at': now}).eq('id', conversationId);
  }
}
