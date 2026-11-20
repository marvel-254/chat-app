import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/profile.dart';
import '../models/call_history.dart' as history;
import '../services/supabase.dart';
import '../services/call_state_machine.dart';
import '../services/call_history.dart';

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
  bool _ready = false;
  bool _muted = false;
  bool _cameraOff = false;
  bool _finished = false;
  String _status = 'Connecting…';
  late final CallStateMachine _callMachine;
  Timer? _ringingTimeout;
  Timer? _reconnectTimeout;
  Timer? _durationTimer;
  DateTime? _startedAt;
  DateTime? _connectedAt;
  int _durationSeconds = 0;
  bool _peerHangup = false;
  bool _historyRecorded = false;
  bool _switchingCamera = false;
  List<MediaDeviceInfo> _cameras = const [];
  int _cameraIndex = 0;

  String get _myId => Supa.currentUser!.id;
  String get _peerId => widget.peer.id;

  @override
  void initState() {
    super.initState();
    _callMachine = CallStateMachine(
      initial: widget.outgoing ? CallPhase.outgoing : CallPhase.incoming,
    );
    _startedAt = DateTime.now().toUtc();
    _start();
  }

  Future<void> _start() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      final channel = Supa.client.channel('call:${widget.conversationId}',
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
          } catch (_) {
            _endCall(
                notifyPeer: false,
                error:
                    "We couldn't access the microphone or camera. Check your permissions and try again.");
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

  /// TURN credentials are build-time references only. Long-lived secrets are
  /// never bundled in the APK; production should fetch short-lived credentials
  /// from an authenticated endpoint and provide them here.
  List<Map<String, dynamic>> _iceServers() {
    final servers = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
    ];
    const turnUrl = String.fromEnvironment('TURN_URL');
    const turnUser = String.fromEnvironment('TURN_USER');
    const turnPass = String.fromEnvironment('TURN_PASS');
    const relayOnly = bool.fromEnvironment('TURN_RELAY_ONLY');
    if (turnUrl.isNotEmpty && turnUser.isNotEmpty && turnPass.isNotEmpty) {
      servers.add({
        'urls': turnUrl,
        'username': turnUser,
        'credential': turnPass,
      });
      if (relayOnly) {
        servers.removeWhere((s) => (s['urls'] as String).startsWith('stun:'));
        servers.last['urls'] = '$turnUrl?transport=udp';
      }
    }
    return servers;
  }

  void _startRingingTimeout() {
    _ringingTimeout?.cancel();
    _ringingTimeout = Timer(const Duration(seconds: 45), () {
      if (!mounted || _finished) return;
      unawaited(_endCall(
        error: 'No answer. The call timed out.',
        reason: CallEndReason.timeout,
      ));
    });
  }

  Future<void> _onConnectionFailed() async {
    final pc = _peerConnection;
    if (pc == null) return;
    if (!_callMachine.shouldRetryReconnect) {
      await _endCall(
        error: 'Connection lost and could not be restored.',
        reason: CallEndReason.networkFailure,
      );
      return;
    }
    try {
      _callMachine.transition(CallPhase.reconnecting);
      if (mounted) setState(() => _status = 'Reconnecting…');
      await pc.restartIce();
      _reconnectTimeout?.cancel();
      _reconnectTimeout = Timer(const Duration(seconds: 12), () {
        if (!mounted || _finished) return;
        unawaited(_endCall(
          error: 'Connection lost and could not be restored.',
          reason: CallEndReason.networkFailure,
        ));
      });
    } catch (_) {
      await _endCall(
        error: 'Connection lost and could not be restored.',
        reason: CallEndReason.networkFailure,
      );
    }
  }

  void _startDurationTimer() {
    if (_connectedAt != null) return;
    _connectedAt = DateTime.now().toUtc();
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _finished || _connectedAt == null) return;
      final seconds = DateTime.now().toUtc()
          .difference(_connectedAt!)
          .inSeconds;
      if (seconds != _durationSeconds) {
        setState(() => _durationSeconds = seconds);
      }
    });
  }

  Future<void> _loadCameras() async {
    try {
      final cameras = await Helper.cameras;
      if (!_finished) _cameras = cameras;
    } catch (_) {
      _cameras = const [];
    }
  }

  Future<void> _switchCamera() async {
    if (_switchingCamera || _finished || _localStream == null) return;
    final tracks = _localStream!.getVideoTracks();
    if (tracks.isEmpty) return;
    final track = tracks.first;
    setState(() => _switchingCamera = true);
    try {
      if (_cameras.isEmpty) await _loadCameras();
      if (_cameras.length < 2) {
        if (mounted && !_finished) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Only one camera is available.')),
          );
        }
        return;
      }
      final next = (_cameraIndex + 1) % _cameras.length;
      if (kIsWeb) {
        await Helper.switchCamera(track, _cameras[next].deviceId, _localStream);
      } else {
        await Helper.switchCamera(track);
      }
      if (mounted && !_finished) {
        setState(() => _cameraIndex = next);
      }
    } catch (_) {
      if (mounted && !_finished) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not switch camera.')),
        );
      }
    } finally {
      if (mounted) setState(() => _switchingCamera = false);
    }
  }

  Future<void> _recordHistory({
    required bool localHangup,
    required bool peerHangup,
    String? reason,
  }) async {
    if (_historyRecorded) return;
    _historyRecorded = true;
    final answered = _connectedAt != null;
    final status = history.resolveCallStatus(
      outgoing: widget.outgoing,
      answered: answered,
      localHangup: localHangup,
      peerHangup: peerHangup,
      reason: reason,
    );
    final record = history.CallRecord(
      id: const Uuid().v4(),
      callId: widget.callId,
      conversationId: widget.conversationId,
      peerUserId: _peerId,
      kind: widget.video
          ? history.CallRecord.kindVideo
          : history.CallRecord.kindVoice,
      direction: widget.outgoing
          ? history.CallRecord.directionOutgoing
          : history.CallRecord.directionIncoming,
      status: status,
      startedAt: _startedAt ?? DateTime.now().toUtc(),
      connectedAt: _connectedAt,
      endedAt: DateTime.now().toUtc(),
      durationSeconds: answered ? _durationSeconds : 0,
      failureReason: status == history.CallRecord.statusFailed
          ? 'Connection was interrupted.'
          : null,
    );
    await CallHistory().record(record);
  }

  Future<void> _preparePeer() async {
    if (_ready) return;
    final config = <String, dynamic>{
      'iceServers': _iceServers(),
      'sdpSemantics': 'unified-plan',
    };
    final pc = await createPeerConnection(config);
    _peerConnection = pc;
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': widget.video ? {'facingMode': 'user'} : false,
    });
    _localStream = stream;
    _localRenderer.srcObject = stream;
    if (widget.video) await _loadCameras();
    for (final track in stream.getTracks()) {
      await pc.addTrack(track, stream);
    }
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteRenderer.srcObject = event.streams.first;
        if (mounted) setState(() => _status = 'Connected');
      }
    };
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _send('ice', {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };
    pc.onConnectionState = (state) {
      if (!mounted) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        if (_callMachine.state.phase != CallPhase.connected) {
          _callMachine.transition(CallPhase.connected);
        }
        _ringingTimeout?.cancel();
        _reconnectTimeout?.cancel();
        _startDurationTimer();
        setState(() => _status = 'Connected');
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        setState(() => _status = 'Reconnecting…');
        unawaited(_onConnectionFailed());
      }
    };
    _ready = true;
    if (widget.outgoing) {
      await _send('invite', {'video': widget.video});
      _callMachine.transition(CallPhase.ringing);
      _startRingingTimeout();
      if (mounted) setState(() => _status = 'Calling ${widget.peer.label}…');
    } else {
      await _send('accept', {'video': widget.video});
      _callMachine.transition(CallPhase.accepted);
      _startRingingTimeout();
      if (mounted) setState(() => _status = 'Joining call…');
    }
  }

  Future<void> _onSignal(Map<String, dynamic> payload) async {
    if (payload['call_id'] != widget.callId || payload['to'] != _myId) return;
    final pc = _peerConnection;
    if (pc == null) return;
    final kind = payload['kind'] as String?;
    final data = Map<String, dynamic>.from(payload['data'] as Map? ?? const {});
    try {
      if (kind == 'accept' && widget.outgoing) {
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
          _pendingCandidates.add(candidate);
        } else {
          await pc.addCandidate(candidate);
        }
      } else if (kind == 'hangup') {
        _peerHangup = true;
        await _endCall(notifyPeer: false, peerHangup: true);
      }
    } catch (_) {
      _endCall(
          notifyPeer: false,
          error: "That call didn't connect. You can try again in a moment.");
    }
  }

  Future<void> _send(String kind, Map<String, dynamic> data) async {
    await _channel?.httpSend(event: 'signal', payload: {
      'call_id': widget.callId,
      'from': _myId,
      'to': _peerId,
      'kind': kind,
      'data': data,
    });
  }

  Future<void> _endCall({
    bool notifyPeer = true,
    String? error,
    CallEndReason? reason,
    bool peerHangup = false,
    bool localHangup = false,
  }) async {
    if (_finished) return;
    _finished = true;
    _ringingTimeout?.cancel();
    _reconnectTimeout?.cancel();
    _durationTimer?.cancel();
    await _recordHistory(
      localHangup: localHangup || (notifyPeer && reason == null),
      peerHangup: peerHangup || _peerHangup,
      reason: reason?.name,
    );
    if (!_callMachine.state.isTerminal) {
      try {
        _callMachine.transition(CallPhase.failed, reason: reason);
      } on InvalidCallTransition {
        // A terminal transition already happened; keep the first reason.
      }
    }
    if (notifyPeer) await _send('hangup', const {});
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _localStream?.dispose();
    await _peerConnection?.close();
    final channel = _channel;
    if (channel != null) await Supa.client.removeChannel(channel);
    await _localRenderer.dispose();
    await _remoteRenderer.dispose();
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _ringingTimeout?.cancel();
    _reconnectTimeout?.cancel();
    if (!_finished) {
      unawaited(_recordHistory(
        localHangup: true,
        peerHangup: _peerHangup,
      ).catchError((_) {}));
      // Fire-and-forget teardown; silence errors since the app is shutting
      // down this screen and there's no context to surface them.
      unawaited(_send('hangup', const {}).catchError((_) {}));
      final localStream = _localStream;
      if (localStream != null) {
        unawaited(localStream.dispose().catchError((_) {}));
      }
      final peerConnection = _peerConnection;
      if (peerConnection != null) {
        unawaited(peerConnection.close().catchError((_) {}));
      }
      final channel = _channel;
      if (channel != null) {
        unawaited(Supa.client.removeChannel(channel).catchError((_) => ''));
      }
      unawaited(_localRenderer.dispose().catchError((_) {}));
      unawaited(_remoteRenderer.dispose().catchError((_) {}));
    }
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
                    if (_connectedAt != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        history.formatCallDuration(_durationSeconds),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                    ],
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
                          label: _muted
                              ? 'Unmute microphone'
                              : 'Mute microphone',
                          icon: _muted ? Icons.mic_off : Icons.mic,
                          color: _muted
                              ? Colors.red.withValues(alpha: 0.8)
                              : const Color(0xFF292A2F),
                          onTap: () {
                            setState(() => _muted = !_muted);
                            for (final track in _localStream?.getAudioTracks() ??
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
                            label: _switchingCamera
                                ? 'Switching camera'
                                : (_cameras.length < 2
                                    ? 'Camera switch unavailable'
                                    : 'Switch camera'),
                            icon: Icons.flip_camera_ios_outlined,
                            busy: _switchingCamera,
                            onTap: (_switchingCamera || _cameras.length < 2)
                                ? null
                                : _switchCamera),
                      ],
                      const SizedBox(width: 14),
                      _CallControl(
                          label: 'End call',
                          icon: Icons.call_end,
                          color: Colors.redAccent,
                          onTap: () => _endCall(localHangup: true)),
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
      this.color = const Color(0xFF292A2F),
      this.busy = false});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final bool busy;
  @override
  Widget build(BuildContext context) => Semantics(
      button: onTap != null,
      label: label,
      child: CircleAvatar(
          radius: 28,
          backgroundColor: color,
          child: IconButton(
              tooltip: label,
              onPressed: onTap,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Icon(icon, color: Colors.white))));
}
