import 'package:supabase_flutter/supabase_flutter.dart';

class CallIce {
  static const _relayOnly = bool.fromEnvironment('CALL_RELAY_ONLY');

  /// The Edge Function may spend up to 6s calling the TURN provider. A shorter
  /// client timeout silently drops relay credentials and leaves calls on STUN.
  static const turnTimeout = Duration(seconds: 10);
  static const _stun = <String, dynamic>{
    'urls': 'stun:stun.l.google.com:19302',
  };

  static Future<Map<String, dynamic>> configuration(
    SupabaseClient client,
  ) async {
    final servers = <Map<String, dynamic>>[_stun];
    try {
      final response = await client.functions.invoke('call-turn',
          body: const {}).timeout(turnTimeout);
      final data = response.data;
      if (data is Map &&
          data['urls'] is List &&
          data['username'] is String &&
          data['credential'] is String) {
        final urls = (data['urls'] as List)
            .whereType<String>()
            .where((url) => url.startsWith('turn:') || url.startsWith('turns:'))
            .toList();
        if (urls.isNotEmpty) {
          servers.add({
            'urls': urls,
            'username': data['username'],
            'credential': data['credential'],
          });
        }
      }
    } catch (_) {
      // An unconfigured relay must not prevent same-network calls.
    }
    if (_relayOnly && servers.length == 1) throw StateError('TURN unavailable');
    return {
      'iceServers': _relayOnly ? servers.skip(1).toList() : servers,
      'iceTransportPolicy': _relayOnly ? 'relay' : 'all',
      'sdpSemantics': 'unified-plan',
    };
  }
}
