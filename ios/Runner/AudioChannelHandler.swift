import Flutter
import Foundation

/// Mock first-pass iOS audio contract. Swap internals to AVAudioEngine later.
final class AudioChannelHandler: NSObject, FlutterStreamHandler {
  static let channel = "com.vocalpolish/audio"
  static let levels = "com.vocalpolish/audio_levels"

  private var sink: FlutterEventSink?
  private var timer: Timer?
  private var recording = false
  private var paused = false
  private var startedAt: Date?
  private var accumulated: TimeInterval = 0
  private var filePath = ""
  private var deviceId = "default"

  func register(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: Self.channel, binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        self?.handle(call, result: result)
      }
    FlutterEventChannel(name: Self.levels, binaryMessenger: messenger)
      .setStreamHandler(self)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "startRecording":
      recording = true
      paused = false
      accumulated = 0
      startedAt = Date()
      filePath = NSTemporaryDirectory() + "take-\(Int(Date().timeIntervalSince1970)).wav"
      startMeter()
      result(["status": "recording"])
    case "pauseRecording":
      if let startedAt, recording, !paused {
        accumulated += Date().timeIntervalSince(startedAt)
      }
      paused = true
      result(["status": "paused"])
    case "resumeRecording":
      paused = false
      startedAt = Date()
      result(["status": "recording"])
    case "stopRecording":
      var extra: TimeInterval = 0
      if let startedAt, recording, !paused {
        extra = Date().timeIntervalSince(startedAt)
      }
      let ms = Int(max(0.8, accumulated + extra) * 1000)
      recording = false
      paused = false
      stopMeter()
      result(["filePath": filePath, "durationMs": ms])
    case "trimAudio":
      let start = args?["startMs"] as? Int ?? 0
      let end = args?["endMs"] as? Int ?? 0
      let path = args?["filePath"] as? String ?? filePath
      result(["filePath": path, "durationMs": max(1, end - start)])
    case "fadeAudio", "normalizeAudio":
      let path = args?["filePath"] as? String ?? filePath
      result(["filePath": path, "durationMs": 0])
    case "getInputDevices":
      result(["devices": [["id": "default", "name": "iPhone Microphone"], ["id": "usb-mic", "name": "USB condenser"]]])
    case "setInputDevice":
      deviceId = args?["deviceId"] as? String ?? "default"
      result(["status": "ok", "deviceId": deviceId])
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    if recording { startMeter() }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    stopMeter()
    return nil
  }

  private func startMeter() {
    stopMeter()
    timer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
      guard let self, self.recording, !self.paused else { return }
      let peak = 0.15 + Double.random(in: 0...0.8)
      let amps = (0..<48).map { _ in 0.1 + Double.random(in: 0...0.85) }
      self.sink?(["rms": peak * 0.7, "peak": peak, "amplitudes": amps])
    }
  }

  private func stopMeter() {
    timer?.invalidate()
    timer = nil
  }
}
