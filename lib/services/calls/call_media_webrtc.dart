import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_media.dart';

/// [CallMedia] on top of flutter_webrtc (Android / iOS).
class WebRtcCallMedia implements CallMedia {
  MediaStream? _local;
  MediaStreamTrack? _camera;
  final _peers = <_WebRtcPeer>{};

  @override
  Object? get localStream => _local;

  @override
  bool get hasVideo => _camera != null;

  static const _audio = {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true};
  static const _video = {
    'facingMode': 'user',
    'width': {'ideal': 1280},
    'height': {'ideal': 720},
    'frameRate': {'ideal': 24},
  };

  @override
  Future<bool> openLocal({required bool video}) async {
    try {
      _local = await navigator.mediaDevices.getUserMedia({'audio': _audio, 'video': video ? _video : false});
    } catch (e) {
      if (!video) rethrow;
      // No camera / denied → join with the microphone only.
      _local = await navigator.mediaDevices.getUserMedia({'audio': _audio, 'video': false});
    }
    final vt = _local!.getVideoTracks();
    _camera = vt.isEmpty ? null : vt.first;
    await Helper.setSpeakerphoneOn(video && _camera != null);
    return _camera != null || !video;
  }

  @override
  Future<void> setMuted(bool muted) async {
    for (final t in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
  }

  @override
  Future<bool> setVideo(bool on) async {
    final local = _local;
    if (local == null) return false;
    if (_camera == null) {
      if (!on) return false;
      try {
        final s = await navigator.mediaDevices.getUserMedia({'audio': false, 'video': _video});
        _camera = s.getVideoTracks().first;
        await local.addTrack(_camera!);
        for (final p in _peers) {
          await p.sendVideo();
        }
        await Helper.setSpeakerphoneOn(true);
        return true;
      } catch (e) {
        debugPrint('[call] camera: $e');
        return false;
      }
    }
    _camera!.enabled = on;
    return on;
  }

  @override
  Future<void> switchCamera() async {
    final cam = _camera;
    if (cam != null) await Helper.switchCamera(cam);
  }

  @override
  Future<void> setSpeaker(bool on) => Helper.setSpeakerphoneOn(on);

  @override
  Future<CallPeer> createPeer(List<Map<String, dynamic>> iceServers, {bool relayOnly = false}) async {
    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'iceTransportPolicy': relayOnly ? 'relay' : 'all',
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
    });
    final peer = _WebRtcPeer(pc, this);
    _peers.add(peer);
    return peer;
  }

  @override
  Future<void> closeLocal() async {
    for (final p in [..._peers]) {
      await p.close();
    }
    _peers.clear();
    for (final t in _local?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _local?.dispose();
    _local = null;
    _camera = null;
    await Helper.setSpeakerphoneOn(false).catchError((_) {});
  }
}

class _WebRtcPeer extends CallPeer {
  _WebRtcPeer(this.pc, this.media) {
    pc.onIceCandidate = (c) {
      if (c.candidate == null || c.candidate!.isEmpty) return;
      onCandidate?.call({'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
    };
    pc.onRenegotiationNeeded = () => onNegotiationNeeded?.call();
    pc.onTrack = (ev) async {
      if (ev.streams.isNotEmpty) {
        _remote = ev.streams.first;
      } else {
        _remote ??= await createLocalMediaStream('remote');
        await _remote!.addTrack(ev.track);
      }
      onStream?.call(_remote!);
    };
    pc.onConnectionState = (s) => onState?.call(switch (s) {
          RTCPeerConnectionState.RTCPeerConnectionStateConnected => 'connected',
          RTCPeerConnectionState.RTCPeerConnectionStateConnecting => 'connecting',
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected => 'disconnected',
          RTCPeerConnectionState.RTCPeerConnectionStateFailed => 'failed',
          RTCPeerConnectionState.RTCPeerConnectionStateClosed => 'closed',
          _ => 'new',
        });
  }

  final RTCPeerConnection pc;
  final WebRtcCallMedia media;
  MediaStream? _remote;
  bool _hasRemote = false;

  @override
  Future<void> addLocalTracks() async {
    final local = media._local;
    if (local == null) return;
    for (final t in local.getTracks()) {
      await pc.addTrack(t, local);
    }
  }

  @override
  Future<void> attachLocalToOffered() async {
    final local = media._local;
    if (local == null) return;
    final trs = await pc.getTransceivers();
    for (final t in local.getTracks()) {
      final tr = trs.where((x) => x.sender.track == null && x.receiver.track?.kind == t.kind).firstOrNull;
      if (tr != null) {
        await tr.sender.replaceTrack(t);
        await tr.sender.setStreams([local]);
        await tr.setDirection(TransceiverDirection.SendRecv);
      } else {
        await pc.addTrack(t, local);
      }
    }
  }

  @override
  Future<Map<String, dynamic>> createOffer({bool iceRestart = false}) async {
    final d = await pc.createOffer(iceRestart ? {'iceRestart': true} : {});
    await pc.setLocalDescription(d);
    return {'type': d.type, 'sdp': d.sdp};
  }

  @override
  Future<Map<String, dynamic>> createAnswer() async {
    final d = await pc.createAnswer({});
    await pc.setLocalDescription(d);
    return {'type': d.type, 'sdp': d.sdp};
  }

  @override
  Future<void> setRemote(Map<String, dynamic> description) async {
    await pc.setRemoteDescription(RTCSessionDescription(description['sdp']?.toString(), description['type']?.toString()));
    _hasRemote = true;
  }

  @override
  Future<void> rollback() => pc.setLocalDescription(RTCSessionDescription('', 'rollback'));

  @override
  Future<void> addCandidate(Map<String, dynamic> c) =>
      pc.addCandidate(RTCIceCandidate(c['candidate']?.toString(), c['sdpMid']?.toString(), (c['sdpMLineIndex'] as num?)?.toInt()));

  @override
  bool get hasRemoteDescription => _hasRemote;

  @override
  String get signalingState => switch (pc.signalingState) {
        RTCSignalingState.RTCSignalingStateStable || null => 'stable',
        RTCSignalingState.RTCSignalingStateHaveLocalOffer => 'have-local-offer',
        RTCSignalingState.RTCSignalingStateHaveRemoteOffer => 'have-remote-offer',
        _ => 'other',
      };

  @override
  Future<void> sendVideo() async {
    final local = media._local;
    final cam = media._camera;
    if (local == null || cam == null) return;
    final trs = await pc.getTransceivers();
    final tr = trs.where((x) => x.sender.track?.kind == 'video' || x.receiver.track?.kind == 'video').firstOrNull;
    if (tr != null) {
      await tr.sender.replaceTrack(cam);
      await tr.sender.setStreams([local]);
      await tr.setDirection(TransceiverDirection.SendRecv);
    } else {
      await pc.addTrack(cam, local);
    }
  }

  @override
  Future<void> close() async {
    media._peers.remove(this);
    try {
      await pc.close();
    } catch (_) {}
  }
}
