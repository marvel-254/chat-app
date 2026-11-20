import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'crypto/adapter.dart';

class SecurityFailure implements Exception {
  const SecurityFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef DeviceKey = ({String owner, String fingerprint, String key});

class SecureChat {
  static const prefix = 'bro2:';
  static const _store = FlutterSecureStorage();
  static SupabaseClient get _db => Supabase.instance.client;
  static String get _owner =>
      _db.auth.currentUser?.id ??
      (throw const SecurityFailure('Sign in again to use secure messaging.'));
  static final _opening = <String, Future<Map<String, dynamic>>>{};

  static Future<String> _run(Map<String, dynamic> args) async {
    try {
      return await runCrypto(jsonEncode(args));
    } catch (_) {
      throw const SecurityFailure(
          'Secure messaging failed. No plaintext was sent.');
    }
  }

  static Future<Map<String, dynamic>> _identity(String owner) =>
      _opening.putIfAbsent(
          owner,
          () => _load(owner).whenComplete(() {
                _opening.remove(owner);
              }));

  static Future<Map<String, dynamic>> _load(String owner) async {
    final slot = 'bro.pgp.v2.$owner';
    var raw = await _store.read(key: slot);
    if (raw == null) {
      raw = await _run({'op': 'generate'});
      await _store.write(key: slot, value: raw);
    }
    final pair = jsonDecode(raw) as Map<String, dynamic>;
    final fp = await _run({'op': 'fingerprint', 'key': pair['publicKey']});
    _checkOwner(owner);
    await _db.from('chat_device_keys').upsert({
      'user_id': owner,
      'fingerprint': fp,
      'public_key': pair['publicKey'],
    }, onConflict: 'fingerprint', ignoreDuplicates: true);
    return {...pair, 'fp': fp};
  }

  static void _checkOwner(String expected) {
    if (_owner != expected)
      throw const SecurityFailure('The signed-in account changed.');
  }

  static Future<List<DeviceKey>> devices(String conversation) async {
    final owner = _owner;
    final own = await _identity(owner);
    final members = (await _db
            .from('conversation_participants')
            .select('user_id')
            .eq('conversation_id', conversation))
        .map((r) => r['user_id'] as String)
        .toSet();
    if (members.length < 2 || !members.contains(owner)) {
      throw const SecurityFailure(
          'Conversation membership could not be verified.');
    }
    final rows = await _db
        .from('chat_device_keys')
        .select('user_id,fingerprint,public_key')
        .inFilter('user_id', members.toList())
        .isFilter('revoked_at', null)
        .order('fingerprint');
    if (rows.length > 64)
      throw const SecurityFailure('Too many devices in this conversation.');
    final result = <DeviceKey>[];
    for (final r in rows) {
      final fp = await _run({'op': 'fingerprint', 'key': r['public_key']});
      if (fp != r['fingerprint'])
        throw const SecurityFailure('Invalid device identity.');
      result.add((
        owner: r['user_id'] as String,
        fingerprint: fp,
        key: r['public_key'] as String
      ));
    }
    if (!result.any((d) => d.owner == owner && d.fingerprint == own['fp'])) {
      throw const SecurityFailure(
          'This device key was revoked. Register a replacement device.');
    }
    _checkOwner(owner);
    return result;
  }

  static String _snapshot(List<DeviceKey> keys) =>
      jsonEncode(keys.map((d) => [d.owner, d.fingerprint]).toList());
  static String _trustSlot(String owner, String c) => 'bro.verified.$owner.$c';
  static Future<bool> verified(
          String conversation, List<DeviceKey> keys) async =>
      await _store.read(key: _trustSlot(_owner, conversation)) ==
      _snapshot(keys);
  static Future<void> approve(
      String owner, String conversation, List<DeviceKey> shown) async {
    _checkOwner(owner);
    final current = await devices(conversation);
    if (_snapshot(shown) != _snapshot(current))
      throw const SecurityFailure(
          'Devices changed. Compare fingerprints again.');
    await _store.write(
        key: _trustSlot(owner, conversation), value: _snapshot(shown));
  }

  static Future<void> revoke(String fingerprint) =>
      _db.rpc('revoke_chat_key', params: {'p_key': fingerprint});

  static Map<String, dynamic> _context(String id, String conversation,
          String sender, String? reply, String purpose) =>
      {
        'v': 2,
        'id': id,
        'conversation': conversation,
        'sender': sender,
        'reply': reply,
        'purpose': purpose
      };

  static Future<String> seal(String id, String conversation, String text,
      {String? reply, String purpose = 'message'}) async {
    final owner = _owner;
    final keys = await devices(conversation);
    final members = await _db
        .from('conversation_participants')
        .select('user_id')
        .eq('conversation_id', conversation);
    if (members.any((m) => !keys.any((d) => d.owner == m['user_id']))) {
      throw const SecurityFailure(
          'A participant has no registered device. Nothing was sent.');
    }
    if (!await verified(conversation, keys))
      throw const SecurityFailure(
          'Unverified or changed devices. Compare fingerprints using the shield before sending.');
    final own = await _identity(owner);
    final packet = await _run({
      'op': 'seal',
      'keys': keys.map((d) => d.key).toList(),
      'secret': own['privateKey'],
      'body': {
        ..._context(id, conversation, owner, reply, purpose),
        'text': text
      }
    });
    _checkOwner(owner);
    return '$prefix${own['fp']}:$packet';
  }

  static Future<String> open(String content, String id, String conversation,
      String sender, String? reply,
      {String purpose = 'message'}) async {
    final owner = _owner;
    if (content.length > 256 * 1024 || !content.startsWith(prefix))
      throw const SecurityFailure('Unsupported envelope.');
    final split = content.indexOf(':', prefix.length);
    if (split < 0) throw const SecurityFailure('Invalid envelope.');
    final fp = content.substring(prefix.length, split);
    final trusted = await _store.read(key: _trustSlot(owner, conversation));
    if (trusted == null ||
        !(jsonDecode(trusted) as List)
            .any((k) => k[0] == sender && k[1] == fp)) {
      throw const SecurityFailure(
          'Unverified sender device. Compare fingerprints.');
    }
    final row = await _db
        .from('chat_device_keys')
        .select('public_key,revoked_at')
        .eq('user_id', sender)
        .eq('fingerprint', fp)
        .single();
    if (row['revoked_at'] != null ||
        await _run({'op': 'fingerprint', 'key': row['public_key']}) != fp) {
      throw const SecurityFailure('Revoked or changed signing key.');
    }
    final own = await _identity(owner);
    final text = await _run({
      'op': 'open',
      'packet': content.substring(split + 1),
      'secret': own['privateKey'],
      'signer': row['public_key'],
      'context': _context(id, conversation, sender, reply, purpose)
    });
    _checkOwner(owner);
    return text;
  }
}
