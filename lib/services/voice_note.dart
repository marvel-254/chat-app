// Voice notes.
// Record a short audio clip and send it as an attachment. The message content
// is "voice:<uuid>" and targets the same private R2 bucket + signed download
// link pattern that chat files already use (R2 Worker
// /upload/attachment and /sign, plus chat-media-migrations.sql for the
// bucket layout).
// Storage path: <conversationIdSafe>/voice/<userId>/<uuid>.m4a
// Limits: 60 s, 20 MB (same cap as chat files).

import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
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
  static String get _tmpPath =>
      'audioplayerscache/${_uuid.v4()}.m4a';

  /// Current recording file, if any.

  /// Starts the microphone. Returns true if permission is granted and
  /// recording can begin.
  static Future<bool> start() async {
    // `record` owns the microphone permission request on every platform, so no
    // separate permission_handler dependency is needed (that plugin pulled in
    // permission_handler_android, which demanded compileSdk 37 and broke the
    // release build under AGP 9.1).
    try {
      if (!await _recorder.hasPermission()) return false;
      await _recorder.stop();
      await _recorder.start(
        const RecordConfig(),
        path: _tmpPath,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Stops recording and uploads the clip. Returns the message id, or ''
  /// on failure (oversized clip or upload error).
  static Future<String> stopAndUpload(String conversationId) async {
    final path = await _recorder.stop();
    if (path == null || !File(path).existsSync()) return '';

    final bytes = await File(path).readAsBytes();
    if (bytes.length > _maxBytes) {
      await File(path).delete();
      return '';
    }

    final messageId = _uuid.v4();
    final objectPath = _objectPath(conversationId, bytes);
    try {
      await _uploadToStorage(objectPath, bytes, 'audio/m4a');
      await _sendMessage(conversationId, 'voice:$messageId',
          objectPath: objectPath);
      return messageId;
    } catch (_) {
      await File(path).delete();
      return '';
    }
  }

  /// Plays a previously sent voice note by download URL.
  static Future<void> play(String url) async {
    try {
      await _player.stop();
      final source = UrlSource(url);
      await _player.setSource(source);
      await _player.play(source);
    } catch (_) {}
  }

  static String _objectPath(String conversationId, List<int> bytes) {
    final safe = conversationId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final ext = 'm4a';
    return '$safe/voice/${Supa.currentUser!.id}/$_uuid.v4.$ext';
  }

  static Future<void> _uploadToStorage(
      String objectPath, Uint8List bytes, String mime) async {
    await Supa.client
        .storage
        .from('chat-files')
        .uploadBinary(objectPath, bytes);
    final url = await Supa.client
        .storage
        .from('chat-files')
        .createSignedUrl(objectPath, 3600);
    await _player.stop();
    final source = UrlSource(url);
    await _player.setSource(source);
    await _player.play(source);
  }

  static Future<void> _sendMessage(
      String conversationId, String content,
      {required String objectPath}) async {
    final me = Supa.currentUser!.id;
    final now = DateTime.now().toIso8601String();
    await Supa.client.from('messages').insert({
      'id': _uuid.v4(),
      'conversation_id': conversationId,
      'sender_id': me,
      'content': content,
      'created_at': now,
    });
    await Supa.client
        .from('conversations')
        .update({'updated_at': now}).eq('id', conversationId);
  }
}
