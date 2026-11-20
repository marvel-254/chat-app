import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import 'supabase.dart';

class VoiceNoteService {
  static final _recorder = AudioRecorder();
  static Future<bool> start() async {
    try {
      if (!await _recorder.hasPermission()) return false;
      final name = '${const Uuid().v4()}.m4a';
      final path =
          kIsWeb ? name : '${(await getTemporaryDirectory()).path}/$name';
      await _recorder.start(const RecordConfig(), path: path);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> cancel() async {
    try {
      await _recorder.cancel();
    } catch (_) {}
  }

  static Future<String> stopAndUpload(String conversationId) async {
    final path = await _recorder.stop();
    if (path == null) return '';
    final sender = Supa.currentUser!.id;
    try {
      if (kIsWeb && !path.startsWith('blob:'))
        throw StateError('Recording unavailable.');
      final bytes = kIsWeb
          ? (await http.get(Uri.parse(path))).bodyBytes
          : await File(path).readAsBytes();
      final meta = await Supa.uploadAttachment(
          conversationId, bytes, 'Voice note.m4a', 'audio/mp4');
      return (await Supa.sendMessage(
              conversationId, 'attachment:${jsonEncode(meta)}',
              expectedSenderId: sender))
          .id;
    } finally {
      if (!kIsWeb) await File(path).delete();
    }
  }
}
