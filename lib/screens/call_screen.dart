import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';
import '../services/supabase.dart';

/// One-to-one WebRTC call. Supabase Realtime carries only the SDP/ICE setup;
/// audio and video stay peer-to-peer.
class CallScreen extends StatefulWidget {
  const CallScreen(
      {super.key,
      required this.conversationId,
      required this.peer,
      required this.callId,
      required this.video,
      required this.outgoing});
  final String conversationId;
  final Profile peer;
  final String callId;
  final bool video;
  final bool outgoing;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  final List<RTCIceCandidate> _pendingCandidates = [];
  RealtimeChannel? _channel;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  bool _ready = false,
      _preparing = false,
      _accepted = false,
      _restarting = false,
      _connected = false;
  int _retries = 0;
  Timer? _deadline, _heartbeat;
  StreamSubscription<List<ConnectivityResult>>? _net;
  final _elapsed = Stopwatch()..start();
  static const _capture = MethodChannel('bro/capture');
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  void _timeout(int secs, String reason) {
    _deadline?.cancel();
    _deadline = Timer(Duration(seconds: secs), () => _endCall(error: reason));
  }

  bool _muted = false;
  bool _cameraOff = false;
  bool _finished = false;
  String _status = 'Connecting…';

  String get _myId => Supa.currentUser!.id;
  String get _peerId => widget.peer.id;

  @override
  void initState() {
    super.initState();
    _timeout(45, 'Call timed out.');
    _net = Connectivity()
        .onConnectivityChanged
        .distinct((a, b) => setEquals(a.toSet(), b.toSet()))
        .listen((_) {
      if (_connected) _recover();
    });
    _start();
  }

  Future<void> _start() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      if (_finished) return;
      final channel = Supa.client.channel(
          'call:${widget.conversationId}:${widget.callId}',
          opts: const RealtimeChannelConfig(private: true));
      _channel = channel;
      channel.onBroadcast(
          event: 'signal', callback: (payload) => _onSignal(payload));
      channel.subscribe((status, error) async {
        if (status == RealtimeSubscribeStatus.subscribed &&
            mounted &&
            !_ready) {
          try {
            await _preparePeer();
          } catch (e) {
            _endCall(
                notifyPeer: false,
                error: e is StateError
                    ? e.message
                    : 'Call unavailable. Check permissions and try again.');
          }
        }
      });
    } catch (_) {
      _endCall(
          notifyPeer: false,
          error:
              "We couldn't start the call. Check your device permissions and try again.");
    }
  }

  Future<void> _preparePeer() async {
    if (_preparing || _ready || _finished) return;
    _preparing = true;
    List<dynamic> servers;
    try {
      final r = await Supa.client.functions.invoke('turn-credentials',
          body: {'conversation_id': widget.conversationId});
      servers = r.data['iceServers'] as List;
    } catch (_) {
      throw StateError('Call relay unavailable. Try again later.');
    }
    if (_finished) return;
    final pc = await createPeerConnection({
      'iceServers': servers,
      'iceTransportPolicy':
          const bool.fromEnvironment('CALL_RELAY_ONLY') ? 'relay' : 'all',
      'sdpSemantics': 'unified-plan'
    });
    if (_finished) {
      await pc.close();
      return;
    }
    _peerConnection = pc;
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': widget.video ? {'facingMode': 'user'} : false,
    });
    if (_finished) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
      return;
    }
    _localStream = stream;
    if (_android) await _capture.invokeMethod('start', widget.video);
    if (_finished) return;
    _localRenderer.srcObject = stream;
    for (final track in stream.getTracks()) {
      await pc.addTrack(track, stream);
    }
    pc.onTrack = (event) {
      if (!_finished && event.streams.isNotEmpty) {
        _remoteRenderer.srcObject = event.streams.first;
        if (mounted) setState(() {});
      }
    };
    pc.onIceCandidate = (candidate) {
      if (!_finished && candidate.candidate != null) {
        _send('ice', {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }).catchError((_) {});
      }
    };
    pc.onConnectionState = (state) {
      if (!mounted || _finished) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _connected = true;
        _deadline?.cancel();
        _restarting = false;
        setState(() => _status = 'Connected');
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _recover();
      }
    };
    _ready = true;
    if (widget.outgoing) {
      try {
        await _send('invite', {'video': widget.video});
      } on PostgrestException catch (e) {
        if (e.message.contains('busy'))
          throw StateError('One participant is already on a call.');
        rethrow;
      }
      if (mounted) setState(() => _status = 'Calling ${widget.peer.label}…');
    } else {
      await _send('accept', {'video': widget.video});
      _accepted = true;
      _lease();
      if (mounted) setState(() => _status = 'Joining call…');
    }
  }

  void _lease() {
    _heartbeat ??= Timer.periodic(const Duration(seconds: 30), (_) {
      _send('heartbeat', {}).catchError((_) {
        if (!_finished) _recover();
      });
    });
  }

  Future<void> _recover() async {
    if (_finished || !_accepted || _restarting) return;
    _restarting = true;
    _connected = false;
    if (++_retries > 2) {
      await _endCall(error: 'Connection lost.');
      return;
    }
    _timeout(18, 'Could not restore the connection.');
    setState(() => _status = 'Reconnecting…');
    if (widget.outgoing) {
      try {
        final pc = _peerConnection!;
        final offer = await pc.createOffer({'iceRestart': true});
        await pc.setLocalDescription(offer);
        await _send('offer', {'sdp': offer.sdp, 'type': offer.type});
      } catch (_) {
        await _endCall(error: 'Connection lost.');
      }
    }
  }

  Future<void> _onSignal(Map<String, dynamic> payload) async {
    if (_finished ||
        payload['from'] != _peerId ||
        payload['call_id'] != widget.callId ||
        payload['to'] != _myId) return;
    final pc = _peerConnection;
    if (pc == null) return;
    final kind = payload['kind'] as String?;
    final data = Map<String, dynamic>.from(payload['data'] as Map? ?? const {});
    try {
      if (kind == 'accept' && widget.outgoing && !_accepted) {
        _accepted = true;
        _lease();
        _timeout(30, 'Call did not connect.');
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        await _send('offer', {'sdp': offer.sdp, 'type': offer.type});
        if (mounted) setState(() => _status = 'Connecting…');
      } else if (kind == 'offer' && !widget.outgoing) {
        await pc.setRemoteDescription(RTCSessionDescription(
            data['sdp'] as String?, data['type'] as String?));
        for (final candidate in _pendingCandidates) {
          await pc.addCandidate(candidate);
        }
        _pendingCandidates.clear();
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        await _send('answer', {'sdp': answer.sdp, 'type': answer.type});
      } else if (kind == 'answer' && widget.outgoing) {
        await pc.setRemoteDescription(RTCSessionDescription(
            data['sdp'] as String?, data['type'] as String?));
        for (final candidate in _pendingCandidates) {
          await pc.addCandidate(candidate);
        }
        _pendingCandidates.clear();
      } else if (kind == 'ice') {
        final candidate = RTCIceCandidate(data['candidate'] as String?,
            data['sdpMid'] as String?, data['sdpMLineIndex'] as int?);
        if (await pc.getRemoteDescription() == null) {
          if (_pendingCandidates.length < 128)
            _pendingCandidates.add(candidate);
        } else {
          await pc.addCandidate(candidate);
        }
      } else if (kind == 'reject') {
        await _endCall(notifyPeer: false, error: 'Call declined.');
      } else if (kind == 'hangup') {
        await _endCall(notifyPeer: false);
      }
    } catch (_) {
      _endCall(
          notifyPeer: false,
          error: "That call didn't connect. You can try again in a moment.");
    }
  }

  Future<void> _send(String kind, Map<String, dynamic> data) async {
    await Supa.client.rpc('signal_call', params: {
      'p_id': widget.callId,
      'p_peer': _peerId,
      'p_conversation': widget.conversationId,
      'p_kind': kind,
      'p_data': data
    });
  }

  Future<void> _quiet(Future<dynamic> Function() fn) async {
    try {
      await fn().timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> _endCall(
      {bool notifyPeer = true, String? error, bool pop = true}) async {
    if (_finished) return;
    _finished = true;
    _deadline?.cancel();
    _heartbeat?.cancel();
    unawaited(_net?.cancel());
    if (notifyPeer) unawaited(_quiet(() => _send('hangup', {})));
    final stream = _localStream;
    if (stream != null) {
      for (final t in stream.getTracks()) {
        await _quiet(t.stop);
      }
      await _quiet(stream.dispose);
    }
    if (_android) await _quiet(() => _capture.invokeMethod('stop'));
    final pc = _peerConnection;
    if (pc != null) {
      await _quiet(pc.close);
      await _quiet(pc.dispose);
    }
    final channel = _channel;
    if (channel != null) await _quiet(() => Supa.client.removeChannel(channel));
    await _quiet(_localRenderer.dispose);
    await _quiet(_remoteRenderer.dispose);
    debugPrint(
        'Call ended: seconds=${_elapsed.elapsed.inSeconds}, restarts=$_retries');
    if (!mounted || !pop) return;
    if (error != null)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    unawaited(_endCall(pop: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF121318),
        body: SafeArea(
            child: Stack(fit: StackFit.expand, children: [
          if (widget.video && _remoteRenderer.srcObject != null)
            RTCVideoView(_remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
          else
            Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                  radius: 58,
                  backgroundColor: const Color(0xFF292A2F),
                  backgroundImage: widget.peer.avatarUrl == null
                      ? null
                      : NetworkImage(widget.peer.avatarUrl!),
                  child: widget.peer.avatarUrl == null
                      ? Text(widget.peer.peerInitial,
                          style: const TextStyle(
                              fontSize: 42, color: Colors.white))
                      : null),
              const SizedBox(height: 20),
              Text(widget.peer.label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w600)),
              Text('@${widget.peer.username}',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _status == 'Connected'
                            ? const Color(0xFF22C55E)
                            : (_status == 'Connecting…' ||
                                    _status.startsWith('Calling') ||
                                    _status == 'Joining call…'
                                ? Colors.amber
                                : Colors.redAccent),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_status,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ])),
          if (widget.video && _ready)
            Positioned(
                right: 18,
                top: 24,
                width: 110,
                height: 160,
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: RTCVideoView(_localRenderer,
                        mirror: true,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))),
          Positioned(
              left: 20,
              right: 20,
              bottom: 32,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xE61E1F25),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: Colors.white12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CallControl(
                          label:
                              _muted ? 'Unmute microphone' : 'Mute microphone',
                          icon: _muted ? Icons.mic_off : Icons.mic,
                          color: _muted
                              ? Colors.red.withValues(alpha: 0.8)
                              : const Color(0xFF292A2F),
                          onTap: () {
                            setState(() => _muted = !_muted);
                            for (final track
                                in _localStream?.getAudioTracks() ??
                                    <MediaStreamTrack>[]) {
                              track.enabled = !_muted;
                            }
                          }),
                      if (widget.video) ...[
                        const SizedBox(width: 14),
                        _CallControl(
                            label: _cameraOff
                                ? 'Turn camera on'
                                : 'Turn camera off',
                            icon: _cameraOff
                                ? Icons.videocam_off
                                : Icons.videocam,
                            color: _cameraOff
                                ? Colors.red.withValues(alpha: 0.8)
                                : const Color(0xFF292A2F),
                            onTap: () {
                              setState(() => _cameraOff = !_cameraOff);
                              for (final track
                                  in _localStream?.getVideoTracks() ??
                                      <MediaStreamTrack>[]) {
                                track.enabled = !_cameraOff;
                              }
                            }),
                        const SizedBox(width: 14),
                        _CallControl(
                            label: 'Switch camera',
                            icon: Icons.flip_camera_ios_outlined,
                            onTap: () async {
                              for (final track
                                  in _localStream?.getVideoTracks() ??
                                      <MediaStreamTrack>[]) {
                                await Helper.switchCamera(track);
                              }
                            }),
                      ],
                      const SizedBox(width: 14),
                      _CallControl(
                          label: 'End call',
                          icon: Icons.call_end,
                          color: Colors.redAccent,
                          onTap: () => _endCall()),
                    ],
                  ),
                ),
              )),
        ])),
      );
}

class _CallControl extends StatelessWidget {
  const _CallControl(
      {required this.label,
      required this.icon,
      required this.onTap,
      this.color = const Color(0xFF292A2F)});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) => Semantics(
      button: true,
      label: label,
      child: CircleAvatar(
          radius: 28,
          backgroundColor: color,
          child: IconButton(
              tooltip: label,
              onPressed: onTap,
              icon: Icon(icon, color: Colors.white))));
}
