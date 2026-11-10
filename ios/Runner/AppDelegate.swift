import Flutter
import UIKit
import GoogleMaps
import PushKit
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate {
  private var voipRegistry: PKPushRegistry?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Maps key from Info.plist `GMSApiKey` (set in Xcode / CI, never committed).
    if let key = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String, !key.isEmpty {
      GMSServices.provideAPIKey(key)
    }
    GeneratedPluginRegistrant.register(with: self)

    // VoIP push (PushKit) → CallKit incoming-call screen, also when the app is closed / the phone is locked.
    let registry = PKPushRegistry(queue: DispatchQueue.main)
    registry.delegate = self
    registry.desiredPushTypes = [PKPushType.voIP]
    voipRegistry = registry

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    let token = credentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  /// Payload from the NEXTX backend (services/callPush.js): type, call_id (UUID), from_name, room_name,
  /// chat_room_id, media ('audio' | 'video'), group ('1' | '0'). iOS requires every VoIP push to report a call.
  func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
    guard type == .voIP else {
      completion()
      return
    }
    let p = payload.dictionaryPayload
    let callId = (p["call_id"] as? String).flatMap { UUID(uuidString: $0) != nil ? $0 : nil } ?? UUID().uuidString
    let fromName = p["from_name"] as? String ?? "สายเรียกเข้า"
    let roomName = p["room_name"] as? String ?? ""
    let isVideo = (p["media"] as? String) == "video"
    let isGroup = (p["group"] as? String) == "1"
    let data = flutter_callkit_incoming.Data(
      id: callId,
      nameCaller: isGroup && !roomName.isEmpty ? roomName : fromName,
      handle: isGroup ? fromName : (isVideo ? "วิดีโอคอล" : "โทรด้วยเสียง"),
      type: isVideo ? 1 : 0
    )
    data.appName = "MOAI NEXT"
    data.supportsVideo = true
    data.duration = 45000
    data.extra = [
      "call_id": callId,
      "chat_room_id": p["chat_room_id"] as? String ?? "",
      "media": isVideo ? "video" : "audio",
      "from_name": fromName,
      "room_name": roomName,
      "group": isGroup ? "1" : "0",
    ]
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true) {
      completion()
    }
  }
}
