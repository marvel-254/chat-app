import 'dart:async';
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
  bool _ready = false;
  bool _muted = false;
  bool _cameraOff = false;
  bool _finished = false;
  String _status = 'Connecting…';

  String get _myId => Supa.currentUser!.id;
  String get _peerId => widget.peer.id;

  @override
  void initState() {
    super.initState();
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
                error: 'Could not access the microphone or camera.');
          }
        }
      });
    } catch (_) {
      _endCall(
          notifyPeer: false,
          error: 'Could not start the call. Check your device permissions.');
    }
  }

  Future<void> _preparePeer() async {
    if (_ready) return;
    final config = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
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
        setState(() => _status = 'Connected');
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        setState(() => _status = 'Connection failed');
      }
    };
    _ready = true;
    if (widget.outgoing) {
      await _send('invite', {'video': widget.video});
      if (mounted) setState(() => _status = 'Calling ${widget.peer.label}…');
    } else {
      await _send('accept', {'video': widget.video});
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
        await _endCall(notifyPeer: false);
      }
    } catch (_) {
      _endCall(notifyPeer: false, error: 'The call could not connect.');
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

  Future<void> _endCall({bool notifyPeer = true, String? error}) async {
    if (_finished) return;
    _finished = true;
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
    if (!_finished) {
      unawaited(_send('hangup', const {}));
      unawaited(_localStream?.dispose());
      unawaited(_peerConnection?.close());
      final channel = _channel;
      if (channel != null) unawaited(Supa.client.removeChannel(channel));
      unawaited(_localRenderer.dispose());
      unawaited(_remoteRenderer.dispose());
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
                            : (_status == 'Connecting…'
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
