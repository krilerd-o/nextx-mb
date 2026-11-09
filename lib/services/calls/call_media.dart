/// Media layer of a call, kept behind an interface so the signaling logic in
/// [CallService] can be tested without real WebRTC (see `call_media_webrtc.dart`).
library;

/// One RTCPeerConnection to one remote socket.
abstract class CallPeer {
  /// Called with `{candidate, sdpMid, sdpMLineIndex}`.
  void Function(Map<String, dynamic> candidate)? onCandidate;
  void Function()? onNegotiationNeeded;

  /// The remote stream (a `MediaStream` for the WebRTC layer) — new object when tracks change.
  void Function(Object stream)? onStream;

  /// 'new' | 'connecting' | 'connected' | 'disconnected' | 'failed' | 'closed'
  void Function(String state)? onState;

  /// Adds every local track (the side that sends the offer).
  Future<void> addLocalTracks();

  /// Answerer: put local tracks on the transceivers the offer created (no extra offer).
  Future<void> attachLocalToOffered();

  /// Creates the offer / answer, sets it as local description and returns `{type, sdp}`.
  Future<Map<String, dynamic>> createOffer({bool iceRestart = false});
  Future<Map<String, dynamic>> createAnswer();

  Future<void> setRemote(Map<String, dynamic> description);
  Future<void> rollback();
  Future<void> addCandidate(Map<String, dynamic> candidate);
  bool get hasRemoteDescription;

  /// 'stable' | 'have-local-offer' | …
  String get signalingState;

  /// Send [track] on the video sender (camera on in a voice call → renegotiates).
  Future<void> sendVideo();

  Future<void> close();
}

abstract class CallMedia {
  /// Opens microphone (+ camera). Returns false when the camera could not be opened (voice only).
  Future<bool> openLocal({required bool video});
  Object? get localStream;
  bool get hasVideo;
  Future<void> setMuted(bool muted);

  /// Turns the camera on / off; opens it the first time in a voice call. Returns whether video is on.
  Future<bool> setVideo(bool on);
  Future<void> switchCamera();
  Future<void> setSpeaker(bool on);
  Future<CallPeer> createPeer(List<Map<String, dynamic>> iceServers);
  Future<void> closeLocal();
}
