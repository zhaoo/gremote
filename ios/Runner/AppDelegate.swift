import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var device: GRemoteDevice?
  private var media: GRemoteMedia?
  private var location: GRemoteLocation?
  private var channels: [FlutterMethodChannel] = []
  private var locationEvents: FlutterEventChannel?

  override func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    GeneratedPluginRegistrant.register(with:self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let messenger = controller.binaryMessenger
      let location = GRemoteLocation(); self.location = location
      let device = GRemoteDevice(flutter:CameraDeviceFlutterApi(binaryMessenger:messenger)); self.device = device
      let media = GRemoteMedia(controller:controller,location:location); self.media = media
      CameraDeviceHostApiSetup.setUp(binaryMessenger:messenger,api:device)
      MediaHostApiSetup.setUp(binaryMessenger:messenger,api:media)
      let locationChannel = FlutterMethodChannel(name:"gremote/location",binaryMessenger:messenger)
      locationChannel.setMethodCallHandler { call,result in
        do {
          switch call.method { case "start":try location.start(); result(nil)
          case "stop":location.stop(); result(nil)
          default:result(FlutterMethodNotImplemented) }
        } catch { result(FlutterError(code:"locationUnavailable",message:"无法启动前台定位",details:nil)) }
      }
      let wifiChannel = FlutterMethodChannel(name:"gremote/wifi_scan",binaryMessenger:messenger)
      wifiChannel.setMethodCallHandler { _,result in
        result(FlutterError(code:"wifiScanUnsupported",message:"iOS 不允许扫描附近 Wi-Fi，请在系统设置连接相机网络",details:nil))
      }
      let appInfoChannel = FlutterMethodChannel(name:"gremote/app_info",binaryMessenger:messenger)
      appInfoChannel.setMethodCallHandler { call,result in
        guard call.method == "read" else { result(FlutterMethodNotImplemented); return }
        let info = Bundle.main.infoDictionary ?? [:]
        guard let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String else {
          result(FlutterError(code:"appInfoUnavailable",message:"无法读取应用版本",details:nil)); return
        }
        result(["appName": info["CFBundleDisplayName"] as? String ?? "GRemote",
                "version": version, "buildNumber": build])
      }
      channels = [locationChannel,wifiChannel,appInfoChannel]
      let events = FlutterEventChannel(name:"gremote/location/fixes",binaryMessenger:messenger)
      events.setStreamHandler(location); locationEvents = events
    }
    return super.application(application,didFinishLaunchingWithOptions:launchOptions)
  }
  override func applicationDidEnterBackground(_ application: UIApplication) {
    location?.stop(); device?.enterBackground(); application.isIdleTimerDisabled = false
    super.applicationDidEnterBackground(application)
  }
}
