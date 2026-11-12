import AVFoundation
import Flutter
import flutter_webrtc
import WebRTC

/// Live captions during a call: reads the microphone audio WebRTC already captures (after echo
/// cancellation, via flutter_webrtc's capture post-processing) instead of opening a second recorder,
/// so the call keeps its audio session. Emits PCM16 mono 24 kHz in 100 ms packets (4800 bytes).
final class CallMicTap: NSObject, FlutterStreamHandler, RTCAudioRenderer {
  private var events: FlutterEventSink?
  private var running = false
  private let lock = NSLock()
  private var out = Data()
  private var phase = 0.0
  private static let packet = 4800

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    FlutterMethodChannel(name: "nextx/call_mic_tap", binaryMessenger: messenger).setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "start":
        self.stop()
        self.lock.lock()
        self.out.removeAll(keepingCapacity: true)
        self.phase = 0
        self.lock.unlock()
        AudioManager.sharedInstance().addLocalAudioRenderer(self)
        self.running = true
        result(true)
      case "stop":
        self.stop()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    FlutterEventChannel(name: "nextx/call_mic_tap/pcm", binaryMessenger: messenger).setStreamHandler(self)
  }

  private func stop() {
    if running { AudioManager.sharedInstance().removeLocalAudioRenderer(self) }
    running = false
  }

  func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
    events = eventSink
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    events = nil
    stop()
    return nil
  }

  /// 10 ms Int16 buffers from WebRTC's audio thread → channel 0 → 24 kHz (linear) → 100 ms packets.
  func render(pcmBuffer: AVAudioPCMBuffer) {
    guard let ch = pcmBuffer.int16ChannelData?[0] else { return }
    let frames = Int(pcmBuffer.frameLength)
    let rate = pcmBuffer.format.sampleRate
    if frames < 2 || rate <= 0 { return }
    var packets: [Data] = []
    lock.lock()
    let step = rate / 24000.0
    while phase < Double(frames - 1) {
      let i = Int(phase)
      let f = phase - Double(i)
      var s = Int16(clamping: Int((Double(ch[i]) * (1 - f) + Double(ch[i + 1]) * f).rounded()))
      withUnsafeBytes(of: &s) { out.append(contentsOf: $0) }
      phase += step
    }
    phase = max(0, phase - Double(frames))
    while out.count >= CallMicTap.packet {
      packets.append(out.prefix(CallMicTap.packet))
      out.removeFirst(CallMicTap.packet)
    }
    lock.unlock()
    if packets.isEmpty { return }
    DispatchQueue.main.async { [weak self] in
      guard let sink = self?.events else { return }
      for p in packets { sink(FlutterStandardTypedData(bytes: Data(p))) }
    }
  }
}
