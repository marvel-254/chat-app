import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';
import '../models/call_record.dart';
import '../services/call_ice.dart';
import '../services/call_state_machine.dart';
import '../services/call_media_failure.dart';
import '../services/call_feedback.dart';
import '../services/call_audio.dart'
    if (dart.library.html) '../services/call_audio_web.dart';
import '../widgets/call_device_picker.dart';
import '../services/calls.dart';
import '../services/supabase.dart';

/// One-to-one WebRTC call. Supabase Realtime carries only the SDP/ICE setup;
/// audio and video stay peer-to-peer.
enum _PipCorner { topRight, topLeft, bottomRight, bottomLeft }

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
  bool _signalingReady = false, _muted = false, _cameraOff = false;
  bool _videoUnavailable = false, _remoteCameraOff = false;
  _PipCorner _pipCorner = _PipCorner.topRight;
  Offset? _pipDragOffset;
  final CallFeedback _feedback = CallFeedback();
  List<CallDeviceEntry> _devices = <CallDeviceEntry>[];
  String? _audioInputId, _audioOutputId, _videoInputId;
  late final CallStateMachine _machine;

  /// The single source of truth for call phase and terminal state.
  CallStateMachine get machine => _machine;
  bool get _videoActive => widget.video && !_videoUnavailable;
  bool get _finished => _machine.state.isTerminal;
  bool get _everConnected => _clock.isRunning;
  int get _restarts => _machine.state.reconnectionAttempts;
  bool _front = true, _canSwitch = false, _switching = false, _speaker = false;
  bool _polling = false,
      _offerPending = false,
      _remoteDescriptionPending = true;
  bool _receivedOffer = false, _offeredInitially = false;
  bool _sessionCreated = false, _serverConnectedReported = false;
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
    _machine = CallStateMachine(
      initial: widget.outgoing ? CallPhase.outgoing : CallPhase.incoming,
    );
    _auth = Supa.authStateChanges.listen((_) {
      if (Supa.currentUser?.id != _myId) unawaited(_finish());
    });
    _armDeadline(const Duration(seconds: 30), 'Could not prepare the call.');
    unawaited(_start());
  }

  /// Browsers block remote audio when the video element was created without a
  /// user gesture. Called after each media attachment so playback is retried.
  void _resumeRemotePlayback() {
    if (!kIsWeb || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_finished) resumeRemoteVideoAudio();
    });
  }

  Color get _statusColor {
    if (_status == 'Connected') return const Color(0xFF22C55E);
    if (_status == 'Connecting…' ||
        _status.startsWith('Calling') ||
        _status == 'Joining call…' ||
        _status == 'Reconnecting…') {
      return Colors.amber;
    }
    return Colors.redAccent;
  }

  /// Applies a validated phase change; duplicate or reverse transitions are
  /// ignored instead of leaving the UI in an impossible state.
  void _transition(CallPhase phase, {CallEndReason? reason}) {
    if (_machine.state.phase == phase || _finished) return;
    try {
      _machine.transition(phase, reason: reason);
    } on InvalidCallTransition catch (error) {
      _diagnostic('invalid_transition_$error');
    }
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
        _transition(CallPhase.accepted);
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
            if (!_finished) {
              unawaited(
                _finish(action: 'fail', error: 'Call signaling failed.'),
              );
            }
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
      setState(() => _signalingReady = true);
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

  Future<void> _loadDevices() async {
    try {
      final found = await navigator.mediaDevices.enumerateDevices();
      if (!mounted || _finished) return;
      setState(() {
        _devices = found
            .where((device) => device.deviceId.isNotEmpty)
            .map((device) {
              final kind = device.kind;
              final deviceKind = kind == 'audioinput'
                  ? CallDeviceKind.microphone
                  : kind == 'audiooutput'
                      ? CallDeviceKind.speaker
                      : kind == 'videoinput'
                          ? CallDeviceKind.camera
                          : null;
              if (deviceKind == null) return null;
              final selected = deviceKind == CallDeviceKind.microphone
                  ? _audioInputId == device.deviceId
                  : deviceKind == CallDeviceKind.speaker
                      ? _audioOutputId == device.deviceId
                      : _videoInputId == device.deviceId;
              return CallDeviceEntry(
                id: device.deviceId,
                label: device.label,
                kind: deviceKind,
                isSelected: selected,
              );
            })
            .whereType<CallDeviceEntry>()
            .toList();
      });
    } catch (_) {
      // Device labels are unavailable before permission; skip silently.
    }
  }

  Future<void> _openDevicePicker() async {
    final grouped = <CallDeviceKind, List<CallDeviceEntry>>{
      for (final kind in CallDeviceKind.values)
        kind: _devices.where((entry) => entry.kind == kind).toList(),
    };
    await showCallDevicePicker(
      context: context,
      devices: grouped,
      currentMicrophoneId: _audioInputId,
      currentSpeakerId: _audioOutputId,
      currentCameraId: _videoInputId,
      onSelected: (entry) => unawaited(_selectDevice(entry)),
    );
  }

  Future<void> _selectDevice(CallDeviceEntry entry) async {
    if (_finished) return;
    try {
      switch (entry.kind) {
        case CallDeviceKind.speaker:
          await Helper.selectAudioOutput(entry.id);
          setState(() => _audioOutputId = entry.id);
          break;
        case CallDeviceKind.microphone:
          if (kIsWeb) {
            final stream = await navigator.mediaDevices.getUserMedia({
              'audio': {
                'deviceId': {'exact': entry.id}
              },
              'video': false,
            });
            final tracks = stream.getAudioTracks();
            if (tracks.isEmpty) return;
            await _replaceLocalTrack(tracks.first);
          } else {
            await Helper.selectAudioInput(entry.id);
          }
          setState(() => _audioInputId = entry.id);
          break;
        case CallDeviceKind.camera:
          if (kIsWeb) {
            final stream = await navigator.mediaDevices.getUserMedia({
              'audio': false,
              'video': {
                'deviceId': {'exact': entry.id}
              },
            });
            final tracks = stream.getVideoTracks();
            if (tracks.isEmpty) return;
            await _replaceLocalTrack(tracks.first);
            setState(() => _front = false);
          } else {
            final track = _videoTrack;
            if (track != null) {
              final stream = await Helper.switchCamera(
                track,
                entry.id,
                _localStream,
              );
              if (!stream) return;
            }
          }
          setState(() => _videoInputId = entry.id);
          break;
      }
      if (mounted && !_finished) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Using ${entry.label.isEmpty ? 'device' : entry.label}',
            ),
          ),
        );
      }
      unawaited(_loadDevices());
    } catch (error) {
      if (mounted && !_finished) {
        final failure = describeMediaError(
          error,
          video: entry.kind == CallDeviceKind.camera,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure.message)),
        );
      }
    }
  }

  Future<void> _replaceLocalTrack(MediaStreamTrack track) async {
    final pc = _peerConnection;
    if (pc == null) return;
    MediaStreamTrack? previous;
    for (final sender in await pc.getSenders()) {
      final current = sender.track;
      if (current != null && current.kind == track.kind) {
        previous = current;
        await sender.replaceTrack(track);
      }
    }
    final oldStream = _localRenderer.srcObject;
    final tracks = <MediaStreamTrack>[];
    if (oldStream != null) {
      for (final existing in oldStream.getTracks()) {
        if (existing.kind != track.kind) tracks.add(existing);
      }
    }
    tracks.add(track);
    final replacement = await createLocalMediaStream(
      'local-${DateTime.now().microsecondsSinceEpoch}',
    );
    for (final item in tracks) {
      await replacement.addTrack(item);
    }
    if (mounted && !_finished) {
      setState(() {
        _localStream = replacement;
        _localRenderer.srcObject = replacement;
        if (track.kind == 'video') _videoTrack = track;
      });
    }
    await previous?.stop();
  }

  /// Opens capture with a typed failure. On desktop browsers without a camera
  /// we keep audio instead of dropping the entire call.
  Future<MediaStream> _openLocalMedia() async {
    try {
      return await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.video ? {'facingMode': 'user'} : false,
      });
    } catch (error) {
      final failure = describeMediaError(error, video: widget.video);
      if (!widget.video ||
          (failure.kind != CallMediaFailureKind.deviceNotFound &&
              failure.kind != CallMediaFailureKind.deviceBusy)) {
        throw failure;
      }
      try {
        final audioOnly = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': false,
        });
        if (mounted && !_finished) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text('Camera unavailable. Continuing with audio only.'),
            ),
          );
        }
        _videoUnavailable = true;
        _diagnostic('audio_only_fallback');
        return audioOnly;
      } catch (_) {
        throw failure;
      }
    }
  }

  Future<void> _preparePeer() async {
    // ICE credential issuance can take a network round trip. Start device
    // capture alongside it so TURN setup does not add directly to call setup
    // time. Keep cleanup explicit if relay-only diagnostics fail meanwhile.
    final mediaFuture = _openLocalMedia();
    late final Map<String, dynamic> config;
    try {
      config = await CallIce.configuration(_client);
    } catch (_) {
      try {
        await _releaseStream(await mediaFuture);
      } catch (_) {}
      rethrow;
    }
    if (_finished) {
      try {
        await _releaseStream(await mediaFuture);
      } catch (_) {}
      return;
    }
    RTCPeerConnection pc;
    try {
      pc = await createPeerConnection(config);
    } catch (_) {
      try {
        await _releaseStream(await mediaFuture);
      } catch (_) {}
      rethrow;
    }
    if (_finished) {
      await _release(() async {
        await pc.close();
        await pc.dispose();
      });
      try {
        await _releaseStream(await mediaFuture);
      } catch (_) {}
      return;
    }
    _peerConnection = pc;
    MediaStream stream;
    try {
      stream = await mediaFuture;
    } on CallMediaFailure catch (failure) {
      await _finish(action: 'fail', error: failure.message);
      return;
    } catch (error) {
      final failure = describeMediaError(error, video: widget.video);
      await _finish(action: 'fail', error: failure.message);
      return;
    }
    if (_finished) {
      await _releaseStream(stream);
      return;
    }
    _localStream = stream;
    _localRenderer.srcObject = stream;
    unawaited(_loadDevices());
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
        final incoming = event.streams.first;
        setState(() {
          _remoteRenderer.srcObject = incoming;
          _remoteCameraOff = incoming.getVideoTracks().isEmpty ||
              incoming.getVideoTracks().every((track) => !track.enabled);
        });
        _resumeRemotePlayback();
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
          _transition(CallPhase.connected);
          unawaited(_feedback.stop());
          if (!_everConnected) {
            _clock.start();
            _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
              if (mounted && !_finished) setState(() {});
            });
          }
          _setStatus('Connected');
          if (kDebugMode) unawaited(_reportCandidateType(pc));
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
      final action = _everConnected && !_serverConnectedReported
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
        _serverConnectedReported = true;
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
    if (record.status == CallStatus.accepted) {
      // The callee repeats `ready` over Realtime, but that broadcast can be
      // lost during subscribe/reconnect. The call row is authoritative, so
      // the caller also starts negotiation when its status poll sees accept.
      unawaited(
        _offerInitial().catchError((Object _) {
          if (!_finished) {
            unawaited(
              _finish(action: 'fail', error: 'Call signaling failed.'),
            );
          }
        }),
      );
    }
    if (previous == record.status) return;
    if (record.status == CallStatus.ringing) {
      _transition(CallPhase.ringing);
      unawaited(_feedback.play(CallFeedbackCue.ringback));
      _setStatus('Calling ${widget.peer.label}…');
      // Server timestamp is authoritative; this is an independent UI ceiling.
      _armDeadline(const Duration(seconds: 52), 'No answer.');
    } else if (record.status == CallStatus.accepted && !_everConnected) {
      _transition(CallPhase.accepted);
      unawaited(_feedback.stop());
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
    if (restart) await pc.restartIce();
    final offer = restart
        ? await pc.createOffer({'iceRestart': true})
        : await pc.createOffer();
    if (_finished) return;
    await pc.setLocalDescription(offer);
    await _send('offer', {'sdp': offer.sdp, 'type': offer.type});
  }

  Future<void> _offerInitial() async {
    if (!widget.outgoing ||
        !_signalingReady ||
        _offeredInitially ||
        _finished) {
      return;
    }
    _offeredInitially = true;
    await _offer();
  }

  Future<void> _onSignal(Map<String, dynamic> payload) async {
    final pc = _peerConnection;
    if (_finished ||
        pc == null ||
        payload['to'] != _myId ||
        payload['from'] != _peerId) {
      return;
    }
    final raw = payload['data'];
    if (raw is! Map) return;
    final kind = payload['kind'];
    if (kind == 'ready' &&
        widget.outgoing &&
        _signalingReady &&
        !_offeredInitially) {
      await _offerInitial();
      return;
    }
    if (kind == 'offer' && !widget.outgoing ||
        kind == 'answer' && widget.outgoing && _offerPending) {
      final sdp = raw['sdp'];
      if (sdp is! String || raw['type'] != kind) return;
      await pc.setRemoteDescription(RTCSessionDescription(sdp, kind as String));
      _remoteDescriptionPending = false;
      _resumeRemotePlayback();
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
          (index != null && index is! int)) {
        return;
      }
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
      if (state != RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _beginRecovery();
      }
    } catch (_) {}
  }

  void _beginRecovery() {
    if (_finished || !_everConnected || _recovery != null) return;
    if (!_machine.shouldRetryReconnect) {
      unawaited(_finish(
        action: 'fail',
        error: 'Connection lost. Please try again.',
      ));
      return;
    }
    _transition(CallPhase.reconnecting);
    if (_finished) return;
    _setStatus('Reconnecting…');
    _recovery = Timer(const Duration(seconds: 3), () => unawaited(_recover()));
  }

  Future<void> _recover() async {
    if (_finished || _status == 'Connected') return;
    if (!_machine.shouldRetryReconnect) {
      await _finish(
        action: 'fail',
        error: 'Connection lost. Please try again.',
      );
      return;
    }
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
      if (action == 'end' && _everConnected && !_serverConnectedReported) {
        // A fast hangup can race the first connected report. Preserve the
        // completed outcome before finalizing, even for a sub-second call.
        try {
          await Calls.advance(widget.callId, 'connected');
        } catch (_) {}
      }
      if (Supa.currentUser?.id == _myId) {
        await Calls.advance(widget.callId, action);
      }
    } catch (_) {}
  }

  void _setStatus(String value) {
    if (mounted && !_finished) setState(() => _status = value);
  }

  Future<void> _reportCandidateType(RTCPeerConnection pc) async {
    try {
      final reports = await pc.getStats().timeout(const Duration(seconds: 3));
      if (_finished) return;
      final selected = <Object?>{};
      for (final report in reports) {
        if (report.type == 'transport') {
          selected.add(report.values['selectedCandidatePairId']);
        }
      }
      for (final pair
          in reports.where((report) => report.type == 'candidate-pair')) {
        if (!selected.contains(pair.id) &&
            !(pair.values['nominated'] == true &&
                pair.values['state'] == 'succeeded')) {
          continue;
        }
        for (final local in reports
            .where((report) => report.id == pair.values['localCandidateId'])) {
          final type = local.values['candidateType'];
          if (const {'host', 'srflx', 'prflx', 'relay'}.contains(type)) {
            _diagnostic('candidate_$type');
          }
        }
      }
    } catch (_) {/* Unsupported or closing connections do not expose stats. */}
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
    } catch (error) {
      if (mounted && !_finished) {
        final failure = describeMediaError(error, video: true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure.message)),
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
      final switched = await Helper.switchCamera(old);
      if (switched) {
        // switchCamera reports success, not the camera's facing direction.
        // Toggle the facing state so the local preview mirror follows hardware.
        _front = !_front;
      }
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
    _transition(
      action == 'fail' ? CallPhase.failed : CallPhase.ended,
      reason: _machine.reasonFor(error),
    );
    if (action == 'fail') {
      unawaited(_feedback.play(CallFeedbackCue.denied));
    } else if (action == 'end') {
      unawaited(_feedback.play(CallFeedbackCue.hangup));
    }
    _clock.stop();
    if (_everConnected) {
      _diagnostic('connected_seconds_${_clock.elapsed.inSeconds}');
    }
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
    if (channel != null) {
      unawaited(
        _release(() async {
          await _client.removeChannel(channel);
        }),
      );
    }
    final pc = _peerConnection;
    if (pc != null) {
      unawaited(
        _release(() async {
          await pc.close();
          await pc.dispose();
        }),
      );
    }
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
    // Let the hangup cue finish before tearing the player down.
    Timer(const Duration(milliseconds: 1200), () {
      unawaited(_feedback.dispose());
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      return Scaffold(
        backgroundColor: const Color(0xFF121318),
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: Center(child: _buildStatusPill()),
              ),
              if (_videoActive &&
                  _remoteRenderer.srcObject != null &&
                  !_remoteCameraOff)
                RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              else if (_videoActive &&
                  _remoteRenderer.srcObject != null &&
                  _remoteCameraOff)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: const Color(0xFF292A2F),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Icon(
                          Icons.videocam_off_outlined,
                          size: 42,
                          color: Colors.white54,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${widget.peer.label} turned off their camera',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 15),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'You can keep talking',
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ],
                  ),
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
                    ],
                  ),
                ),
              if (_videoActive && _signalingReady) _buildLocalPip(box),
              Positioned(
                left: 20,
                right: 20,
                bottom: 16,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xF01C1E24),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.white12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.42),
                            blurRadius: 28,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _CallControl(
                                    label: _muted
                                        ? 'Unmute microphone'
                                        : 'Mute microphone',
                                    caption: _muted ? 'Unmute' : 'Mute',
                                    icon: _muted ? Icons.mic_off : Icons.mic,
                                    color: _muted
                                        ? Colors.red.withValues(alpha: 0.8)
                                        : const Color(0xFF292A2F),
                                    onTap: () {
                                      setState(() => _muted = !_muted);
                                      _feedback.setEnabled(!_muted);
                                      for (final track
                                          in _localStream?.getAudioTracks() ??
                                              <MediaStreamTrack>[]) {
                                        track.enabled = !_muted;
                                      }
                                    },
                                  ),
                                  if (_videoActive) ...[
                                    _CallControl(
                                      label: _cameraOff
                                          ? 'Turn camera on'
                                          : 'Turn camera off',
                                      caption:
                                          _cameraOff ? 'Camera on' : 'Camera',
                                      icon: _cameraOff
                                          ? Icons.videocam_off
                                          : Icons.videocam,
                                      color: _cameraOff
                                          ? Colors.red.withValues(alpha: 0.8)
                                          : const Color(0xFF292A2F),
                                      onTap: () {
                                        setState(
                                            () => _cameraOff = !_cameraOff);
                                        _videoTrack?.enabled = !_cameraOff;
                                      },
                                    ),
                                    _CallControl(
                                      label: 'Switch camera',
                                      caption: 'Flip',
                                      icon: Icons.flip_camera_ios_outlined,
                                      busy: _switching,
                                      onTap: _canSwitch && !_switching
                                          ? _switchCamera
                                          : null,
                                    ),
                                  ],
                                  if (!kIsWeb &&
                                      (defaultTargetPlatform ==
                                              TargetPlatform.android ||
                                          defaultTargetPlatform ==
                                              TargetPlatform.iOS))
                                    _CallControl(
                                      label: _speaker
                                          ? 'Use earpiece'
                                          : 'Use speaker',
                                      caption:
                                          _speaker ? 'Earpiece' : 'Speaker',
                                      icon: _speaker
                                          ? Icons.volume_up
                                          : Icons.hearing,
                                      onTap: !_signalingReady
                                          ? null
                                          : () async {
                                              try {
                                                final next = !_speaker;
                                                if (next) {
                                                  await Helper
                                                      .setSpeakerphoneOnButPreferBluetooth();
                                                } else {
                                                  await Helper
                                                      .setSpeakerphoneOn(false);
                                                }
                                                if (mounted && !_finished) {
                                                  setState(
                                                      () => _speaker = next);
                                                }
                                              } catch (_) {}
                                            },
                                    ),
                                  _CallControl(
                                    label: 'Select call devices',
                                    caption: 'Devices',
                                    icon: Icons.devices_other_rounded,
                                    onTap: !_signalingReady || _finished
                                        ? null
                                        : _openDevicePicker,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _CallControl(
                            label: 'End call',
                            caption: 'End',
                            icon: Icons.call_end,
                            color: Colors.redAccent,
                            onTap: () => _finish(action: 'end'),
                            prominent: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Offset _pipBaseOffset(BoxConstraints box, Size size) {
    const insetX = 18.0;
    const insetTop = 76.0;
    const insetBottom = 156.0;
    switch (_pipCorner) {
      case _PipCorner.topLeft:
        return const Offset(insetX, insetTop);
      case _PipCorner.topRight:
        return Offset(box.maxWidth - size.width - insetX, insetTop);
      case _PipCorner.bottomLeft:
        return Offset(insetX, box.maxHeight - size.height - insetBottom);
      case _PipCorner.bottomRight:
        return Offset(
          box.maxWidth - size.width - insetX,
          box.maxHeight - size.height - insetBottom,
        );
    }
  }

  Widget _buildLocalPip(BoxConstraints box) {
    final landscape = box.maxWidth > box.maxHeight;
    final size = landscape ? const Size(160, 100) : const Size(100, 144);
    final base = _pipBaseOffset(box, size);
    final offset = _pipDragOffset ?? base;
    final left = offset.dx.clamp(
      0.0,
      (box.maxWidth - size.width).clamp(0.0, 1e9),
    );
    final top = offset.dy.clamp(
      0.0,
      (box.maxHeight - size.height).clamp(0.0, 1e9),
    );
    return AnimatedPositioned(
      duration: _pipDragOffset == null
          ? const Duration(milliseconds: 220)
          : Duration.zero,
      curve: Curves.easeOut,
      left: left,
      top: top,
      width: size.width,
      height: size.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => setState(() => _pipDragOffset = base),
        onPanUpdate: (details) {
          setState(() {
            _pipDragOffset = (_pipDragOffset ?? base) + details.delta;
          });
        },
        onPanEnd: (_) {
          final center = (_pipDragOffset ?? base) +
              Offset(size.width / 2, size.height / 2);
          final isLeft = center.dx < box.maxWidth / 2;
          final isTop = center.dy < box.maxHeight / 2;
          setState(() {
            _pipCorner = isTop
                ? (isLeft ? _PipCorner.topLeft : _PipCorner.topRight)
                : (isLeft ? _PipCorner.bottomLeft : _PipCorner.bottomRight);
            _pipDragOffset = null;
          });
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: RTCVideoView(
                  _localRenderer,
                  mirror: _front,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
              const Positioned(
                right: 6,
                top: 6,
                child: Icon(Icons.open_with, size: 14, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill() {
    final label = _everConnected
        ? '$_status · ${CallRecord.formatDuration(_clock.elapsed)}'
        : _status;
    final shown = _remoteCameraOff ? '$label · Camera off' : label;
    return Semantics(
      label: shown,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xE61E1F25),
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
                color: _statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              shown,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.label,
    required this.icon,
    required this.onTap,
    this.caption,
    this.busy = false,
    this.color = const Color(0xFF292A2F),
    this.prominent = false,
  });
  final String label;
  final String? caption;
  final IconData icon;
  final VoidCallback? onTap;
  final bool busy;
  final Color color;
  final bool prominent;
  @override
  Widget build(BuildContext context) {
    final size = prominent ? 54.0 : 48.0;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: SizedBox(
        width: 66,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: label,
              child: Material(
                color: color,
                borderRadius: BorderRadius.circular(prominent ? 27 : 18),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(prominent ? 27 : 18),
                  child: SizedBox.square(
                    dimension: size,
                    child: Center(
                      child: busy
                          ? const SizedBox.square(
                              dimension: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              icon,
                              size: prominent ? 25 : 22,
                              color:
                                  onTap == null ? Colors.white38 : Colors.white,
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              caption ?? label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onTap == null ? Colors.white38 : Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
