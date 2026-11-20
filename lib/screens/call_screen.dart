import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';
import '../models/call_record.dart';
import '../services/call_ice.dart';
import '../services/calls.dart';
import '../services/supabase.dart';

/// One-to-one WebRTC call. Supabase Realtime carries only the SDP/ICE setup;
/// audio and video stay peer-to-peer.
class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.conversationId,
    required this.peer,
    required this.callId,
    required this.video,
    required this.outgoing,
  });
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
  final _pendingCandidates = <RTCIceCandidate>[];
  final _clock = Stopwatch();
  RealtimeChannel? _channel;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream, _cameraStream;
  MediaStreamTrack? _videoTrack;
  RTCRtpSender? _videoSender;
  Future<void>? _rendererSetup, _cameraOperation;
  Future<void> _signals = Future.value();
  Timer? _poll, _deadline, _ticker, _recovery;
  StreamSubscription<AuthState>? _auth;
  StreamSubscription<List<ConnectivityResult>>? _network;
  String? _networkSignature;
  bool _ready = false, _muted = false, _cameraOff = false, _finished = false;
  bool _front = true, _canSwitch = false, _switching = false, _speaker = false;
  bool _polling = false,
      _offerPending = false,
      _remoteDescriptionPending = true;
  bool _receivedOffer = false, _offeredInitially = false;
  bool _sessionCreated = false,
      _everConnected = false,
      _connectedReported = false;
  int _restarts = 0;
  DateTime? _lastHeartbeat;
  String _status = 'Preparing call…';
  late final String _myId;
  late final SupabaseClient _client;
  CallStatus? _serverStatus;
  String get _peerId => widget.peer.id;

  @override
  void initState() {
    super.initState();
    _myId = Supa.currentUser!.id;
    _client = Supa.client;
    _auth = Supa.authStateChanges.listen((_) {
      if (Supa.currentUser?.id != _myId) unawaited(_finish());
    });
    _armDeadline(const Duration(seconds: 30), 'Could not prepare the call.');
    unawaited(_start());
  }

  void _armDeadline(Duration delay, String error) {
    _deadline?.cancel();
    _deadline = Timer(
      delay,
      () => unawaited(_finish(action: 'fail', error: error)),
    );
  }

  Future<void> _start() async {
    try {
      _rendererSetup = Future.wait([
        _localRenderer.initialize(),
        _remoteRenderer.initialize(),
      ]).then<void>((_) {});
      await _rendererSetup;
      if (_finished) return;
      if (!widget.outgoing) {
        final record = await Calls.get(widget.callId);
        if (_finished) return;
        if (record == null ||
            record.status != CallStatus.ringing ||
            record.calleeId != _myId ||
            record.callerId != _peerId ||
            record.conversationId != widget.conversationId ||
            record.video != widget.video) {
          await _finish(error: 'This call is no longer available.');
          return;
        }
        final claimed = await Calls.advance(widget.callId, 'accept');
        _sessionCreated = claimed.status == CallStatus.accepted;
        if (_finished) {
          if (_sessionCreated) unawaited(_advanceQuietly('end'));
          return;
        }
        _applyRecord(claimed);
        if (_finished) return;
      }
      await _preparePeer();
      if (_finished) return;
      if (widget.outgoing) {
        final record = await Calls.start(
          widget.callId,
          widget.conversationId,
          _peerId,
          widget.video,
        );
        _sessionCreated = true;
        if (_finished) {
          unawaited(_advanceQuietly('end'));
          return;
        }
        _applyRecord(record);
        if (_finished) return;
      }
      final channel = _client.channel(
        'bro-call:${widget.callId}',
        opts: const RealtimeChannelConfig(private: true),
      );
      _channel = channel;
      final subscribed = Completer<void>();
      channel
          .onBroadcast(
        event: 'signal',
        callback: (payload) {
          _signals = _signals.then((_) => _onSignal(payload)).catchError((
            Object _,
          ) {
            if (!_finished)
              unawaited(
                _finish(action: 'fail', error: 'Call signaling failed.'),
              );
          });
        },
      )
          .subscribe((status, _) {
        if (status == RealtimeSubscribeStatus.subscribed &&
            !subscribed.isCompleted) {
          subscribed.complete();
        }
      });
      await subscribed.future.timeout(Calls.timeout);
      if (_finished) return;
      setState(() => _ready = true);
      _poll = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_refresh()),
      );
      unawaited(_refresh());
      _network = Connectivity().onConnectivityChanged.listen((results) {
        final signature = results.map((e) => e.name).toList()..sort();
        final previous = _networkSignature;
        _networkSignature = signature.join(',');
        if (previous != null &&
            previous != _networkSignature &&
            _everConnected) {
          _diagnostic('network_changed');
          unawaited(_checkNetworkChange());
        }
      });
    } catch (_) {
      await _finish(
        action: 'fail',
        error:
            'Could not start the call. Check your connection and microphone or camera permissions.',
      );
    }
  }

  Future<void> _preparePeer() async {
    final config = await CallIce.configuration(_client);
    if (_finished) return;
    final pc = await createPeerConnection(config);
    if (_finished) {
      await _release(() async {
        await pc.close();
        await pc.dispose();
      });
      return;
    }
    _peerConnection = pc;
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': widget.video ? {'facingMode': 'user'} : false,
    });
    if (_finished) {
      await _releaseStream(stream);
      return;
    }
    _localStream = stream;
    _localRenderer.srcObject = stream;
    for (final track in stream.getTracks()) {
      if (_finished) return;
      final sender = await pc.addTrack(track, stream);
      if (track.kind == 'video') {
        _videoSender = sender;
        _videoTrack = track;
        _front = track.getSettings()['facingMode'] != 'environment';
      }
    }
    if (_videoTrack != null) {
      try {
        _canSwitch = (await Helper.cameras).length > 1;
      } catch (_) {}
    }
    if (_finished) return;
    pc.onTrack = (event) {
      if (!_finished && mounted && event.streams.isNotEmpty) {
        setState(() => _remoteRenderer.srcObject = event.streams.first);
      }
    };
    pc.onIceCandidate = (candidate) {
      if (!_finished && candidate.candidate != null) {
        unawaited(
          _send('ice', {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          }).catchError((Object _) {}),
        );
      }
    };
    pc.onIceConnectionState = (state) => _diagnostic('ice_${state.name}');
    pc.onConnectionState = (state) {
      if (_finished) return;
      _diagnostic('peer_${state.name}');
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _deadline?.cancel();
          _recovery?.cancel();
          _recovery = null;
          _restarts = 0;
          if (!_everConnected) {
            _everConnected = true;
            _clock.start();
            _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
              if (mounted && !_finished) setState(() {});
            });
          }
          _setStatus('Connected');
          unawaited(_refresh());
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          if (_everConnected) {
            _beginRecovery();
          } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
            unawaited(
              _finish(action: 'fail', error: 'Could not connect the call.'),
            );
          }
        default:
          break;
      }
    };
  }

  Future<void> _refresh() async {
    if (_polling || _finished) return;
    _polling = true;
    try {
      final heartbeatDue = _lastHeartbeat == null ||
          DateTime.now().difference(_lastHeartbeat!) >=
              const Duration(seconds: 20);
      final action = _everConnected && !_connectedReported
          ? 'connected'
          : _status == 'Connected' && heartbeatDue
              ? 'heartbeat'
              : 'refresh';
      if (!widget.outgoing &&
          !_receivedOffer &&
          _serverStatus == CallStatus.accepted) {
        unawaited(_send('ready', {}).catchError((Object _) {}));
      }
      final record = await Calls.advance(widget.callId, action);
      if (_finished) return;
      if (action != 'refresh' && record.status == CallStatus.connected) {
        _connectedReported = true;
        _lastHeartbeat = DateTime.now();
      }
      _applyRecord(record);
    } catch (_) {
      // A media connection can survive an unavailable signaling service.
      _diagnostic('status_unavailable');
    } finally {
      _polling = false;
    }
  }

  void _applyRecord(CallRecord record) {
    final previous = _serverStatus;
    _serverStatus = record.status;
    if (record.status.terminal) {
      unawaited(
        _finish(
          error: record.status == CallStatus.completed
              ? null
              : record.outcome(_myId),
        ),
      );
      return;
    }
    if (previous == record.status) return;
    if (record.status == CallStatus.ringing) {
      _setStatus('Calling ${widget.peer.label}…');
      // Server timestamp is authoritative; this is an independent UI ceiling.
      _armDeadline(const Duration(seconds: 52), 'No answer.');
    } else if (record.status == CallStatus.accepted && !_everConnected) {
      _setStatus('Connecting…');
      _armDeadline(const Duration(seconds: 35), 'Could not connect the call.');
    }
  }

  Future<void> _offer({bool restart = false}) async {
    final pc = _peerConnection;
    if (pc == null || _finished || (_offerPending && !restart)) return;
    _offerPending = true;
    _remoteDescriptionPending = true;
    if (restart) _pendingCandidates.clear();
    final offer = await pc.createOffer(restart ? {'iceRestart': true} : {});
    if (_finished) return;
    await pc.setLocalDescription(offer);
    await _send('offer', {'sdp': offer.sdp, 'type': offer.type});
  }

  Future<void> _onSignal(Map<String, dynamic> payload) async {
    final pc = _peerConnection;
    if (_finished ||
        pc == null ||
        payload['to'] != _myId ||
        payload['from'] != _peerId) return;
    final raw = payload['data'];
    if (raw is! Map) return;
    final kind = payload['kind'];
    if (kind == 'ready' && widget.outgoing && _ready && !_offeredInitially) {
      _offeredInitially = true;
      await _offer();
      return;
    }
    if (kind == 'offer' && !widget.outgoing ||
        kind == 'answer' && widget.outgoing && _offerPending) {
      final sdp = raw['sdp'];
      if (sdp is! String || raw['type'] != kind) return;
      await pc.setRemoteDescription(RTCSessionDescription(sdp, kind as String));
      _remoteDescriptionPending = false;
      for (final candidate in _pendingCandidates) {
        await _release(() => pc.addCandidate(candidate));
      }
      _pendingCandidates.clear();
      if (kind == 'offer') {
        _receivedOffer = true;
        final answer = await pc.createAnswer();
        if (_finished) return;
        await pc.setLocalDescription(answer);
        await _send('answer', {'sdp': answer.sdp, 'type': answer.type});
      } else {
        _offerPending = false;
      }
    } else if (kind == 'ice') {
      final candidate = raw['candidate'];
      final mid = raw['sdpMid'];
      final index = raw['sdpMLineIndex'];
      if (candidate is! String ||
          (mid != null && mid is! String) ||
          (index != null && index is! int)) return;
      final ice = RTCIceCandidate(candidate, mid as String?, index as int?);
      if (_remoteDescriptionPending) {
        if (_pendingCandidates.length < 128) _pendingCandidates.add(ice);
      } else {
        await _release(() => pc.addCandidate(ice));
      }
    } else if (kind == 'restart' && widget.outgoing && _everConnected) {
      _beginRecovery();
    }
  }

  Future<void> _checkNetworkChange() async {
    try {
      final state = await _peerConnection?.getConnectionState();
      if (state != RTCPeerConnectionState.RTCPeerConnectionStateConnected)
        _beginRecovery();
    } catch (_) {}
  }

  void _beginRecovery() {
    if (_finished || !_everConnected || _recovery != null) return;
    _setStatus('Reconnecting…');
    _recovery = Timer(const Duration(seconds: 3), () => unawaited(_recover()));
  }

  Future<void> _recover() async {
    if (_finished || _status == 'Connected') return;
    if (_restarts >= 2) {
      await _finish(
        action: 'fail',
        error: 'Connection lost. Please try again.',
      );
      return;
    }
    _restarts++;
    _diagnostic('reconnect_attempt_$_restarts');
    try {
      if (widget.outgoing) {
        if (_offerPending) {
          await _peerConnection?.setLocalDescription(
            RTCSessionDescription('', 'rollback'),
          );
          _offerPending = false;
        }
        await _offer(restart: true);
      } else {
        _remoteDescriptionPending = true;
        await _send('restart', {});
      }
    } catch (_) {
      _diagnostic('restart_unavailable');
    }
    if (!_finished && _status != 'Connected') {
      _recovery = Timer(
        const Duration(seconds: 8),
        () => unawaited(_recover()),
      );
    }
  }

  Future<void> _send(String kind, Map<String, dynamic> data) async {
    if (_finished || Supa.currentUser?.id != _myId) return;
    await _client.rpc(
      'signal_bro_call',
      params: {'p_id': widget.callId, 'p_kind': kind, 'p_data': data},
    ).timeout(Calls.timeout);
  }

  Future<void> _advanceQuietly(String action) async {
    if (Supa.currentUser?.id != _myId) return;
    try {
      await Calls.advance(widget.callId, action);
    } catch (_) {}
  }

  void _setStatus(String value) {
    if (mounted && !_finished) setState(() => _status = value);
  }

  void _diagnostic(String category) {
    assert(() {
      debugPrint('RTC: $category');
      return true;
    }());
  }

  Future<void> _switchCamera() async {
    final old = _videoTrack;
    if (_finished || _switching || !_canSwitch || old == null) return;
    setState(() => _switching = true);
    final operation = _replaceCamera(old);
    _cameraOperation = operation;
    try {
      await operation;
    } catch (_) {
      if (mounted && !_finished) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not switch cameras.')),
        );
      }
    } finally {
      _cameraOperation = null;
      if (mounted && !_finished) setState(() => _switching = false);
    }
  }

  Future<void> _replaceCamera(MediaStreamTrack old) async {
    final cameras = await Helper.cameras;
    if (_finished || cameras.length < 2) return;
    if (!kIsWeb) {
      // Native flutter_webrtc swaps capture hardware on the same sender track.
      _front = await Helper.switchCamera(old);
      return;
    }
    final sender = _videoSender;
    if (sender == null) return;
    final activeId = old.getSettings()['deviceId'];
    final facing = _front ? 'environment' : 'user';
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': {
        'facingMode': {'exact': facing},
      },
    }).catchError((Object _) {
      if (_finished) throw StateError('Call ended');
      // Desktops often have no facing-mode metadata. Cycle actual device IDs.
      final index = cameras.indexWhere(
        (camera) => camera.deviceId == activeId,
      );
      final next = cameras[(index + 1) % cameras.length];
      return navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'deviceId': {'exact': next.deviceId},
        },
      });
    });
    var installed = false;
    try {
      if (_finished) return;
      final next = stream.getVideoTracks().single;
      if (activeId != null && next.getSettings()['deviceId'] == activeId) {
        throw StateError('Camera did not change');
      }
      next.enabled = !_cameraOff;
      await sender.replaceTrack(next);
      final previous = _cameraStream;
      _cameraStream = stream;
      _videoTrack = next;
      next.enabled = !_cameraOff;
      installed = true;
      _front = next.getSettings()['facingMode'] == 'user';
      if (!_finished) _localRenderer.srcObject = stream;
      if (previous != null) {
        await _releaseStream(previous);
      } else {
        await _release(old.stop);
        await _release(() async {
          await _localStream?.removeTrack(old);
        });
      }
    } finally {
      if (!installed) await _releaseStream(stream);
    }
  }

  static Future<void> _release(Future<void> Function() close) async {
    try {
      await close();
    } catch (_) {}
  }

  static Future<void> _releaseStream(MediaStream stream) async {
    for (final track in stream.getTracks()) {
      await _release(track.stop);
    }
    await _release(stream.dispose);
  }

  Future<void> _finish({
    String? action,
    String? error,
    bool navigate = true,
  }) async {
    if (_finished) return;
    _finished = true;
    _clock.stop();
    _deadline?.cancel();
    _poll?.cancel();
    _ticker?.cancel();
    _recovery?.cancel();
    unawaited(
      _release(() async {
        await _network?.cancel();
      }),
    );
    unawaited(
      _release(() async {
        await _auth?.cancel();
      }),
    );
    if (action != null && (_sessionCreated || widget.outgoing)) {
      // Do not make media/resource cleanup depend on an online database.
      unawaited(_advanceQuietly(action));
    }
    final channel = _channel;
    if (channel != null)
      unawaited(
        _release(() async {
          await _client.removeChannel(channel);
        }),
      );
    final pc = _peerConnection;
    if (pc != null)
      unawaited(
        _release(() async {
          await pc.close();
          await pc.dispose();
        }),
      );
    final local = _localStream;
    if (local != null) unawaited(_releaseStream(local));
    unawaited(
      _release(() async {
        await _release(() async {
          await _cameraOperation;
        });
        final camera = _cameraStream;
        if (camera != null) await _releaseStream(camera);
      }),
    );
    unawaited(
      _release(() async {
        await _release(() async {
          await _rendererSetup;
        });
        await _release(_localRenderer.dispose);
        await _release(_remoteRenderer.dispose);
      }),
    );
    if (!mounted || !navigate) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
    final route = ModalRoute.of(context);
    if (route?.isCurrent == true) {
      Navigator.of(context).pop();
    } else if (route?.isActive == true) {
      route!.navigator?.removeRoute(route);
    }
  }

  @override
  void dispose() {
    unawaited(_finish(action: 'end', navigate: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF121318),
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.video && _remoteRenderer.srcObject != null)
                RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              else
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 58,
                        backgroundColor: const Color(0xFF292A2F),
                        backgroundImage: widget.peer.avatarUrl == null
                            ? null
                            : NetworkImage(widget.peer.avatarUrl!),
                        child: widget.peer.avatarUrl == null
                            ? Text(
                                widget.peer.peerInitial,
                                style: const TextStyle(
                                  fontSize: 42,
                                  color: Colors.white,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        widget.peer.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '@${widget.peer.username}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
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
                            Text(
                              _everConnected
                                  ? '$_status · ${CallRecord.formatDuration(_clock.elapsed)}'
                                  : _status,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (_everConnected &&
                  widget.video &&
                  _remoteRenderer.srcObject != null)
                Positioned(
                  top: 24,
                  left: 18,
                  child: Chip(
                    label: Text(
                      '$_status · ${CallRecord.formatDuration(_clock.elapsed)}',
                    ),
                  ),
                ),
              if (widget.video && _ready)
                Positioned(
                  right: 18,
                  top: 24,
                  width: 110,
                  height: 160,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: RTCVideoView(
                      _localRenderer,
                      mirror: _front,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 32,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
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
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
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
                          },
                        ),
                        if (widget.video) ...[
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
                              _videoTrack?.enabled = !_cameraOff;
                            },
                          ),
                          _CallControl(
                            label: 'Switch camera',
                            icon: Icons.flip_camera_ios_outlined,
                            busy: _switching,
                            onTap: _canSwitch && !_switching
                                ? _switchCamera
                                : null,
                          ),
                        ],
                        if (!kIsWeb &&
                            (defaultTargetPlatform == TargetPlatform.android ||
                                defaultTargetPlatform == TargetPlatform.iOS))
                          _CallControl(
                            label: _speaker ? 'Use earpiece' : 'Use speaker',
                            icon: _speaker ? Icons.volume_up : Icons.hearing,
                            onTap: !_ready
                                ? null
                                : () async {
                                    try {
                                      final next = !_speaker;
                                      if (next) {
                                        await Helper
                                            .setSpeakerphoneOnButPreferBluetooth();
                                      } else {
                                        await Helper.setSpeakerphoneOn(false);
                                      }
                                      if (mounted && !_finished)
                                        setState(() => _speaker = next);
                                    } catch (_) {}
                                  },
                          ),
                        _CallControl(
                          label: 'End call',
                          icon: Icons.call_end,
                          color: Colors.redAccent,
                          onTap: () => _finish(action: 'end'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.label,
    required this.icon,
    required this.onTap,
    this.busy = false,
    this.color = const Color(0xFF292A2F),
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool busy;
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
            icon: busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon,
                    color: onTap == null ? Colors.white38 : Colors.white),
          ),
        ),
      );
}
