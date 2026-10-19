import CoreLocation
import Flutter
import UIKit

final class GRemoteLocation: NSObject, CLLocationManagerDelegate, FlutterStreamHandler {
  private let manager = CLLocationManager()
  private var sink: FlutterEventSink?
  private var permission: [(Bool) -> Void] = []
  private var active = false
  var allowed: Bool { manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways }
  override init() {
    super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    NotificationCenter.default.addObserver(self,selector:#selector(stop),name:UIApplication.didEnterBackgroundNotification,object:nil)
  }
  func requestPermission(_ completion: @escaping (Bool) -> Void) {
    if manager.authorizationStatus != .notDetermined { completion(allowed); return }
    permission.append(completion); manager.requestWhenInUseAuthorization()
  }
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if manager.authorizationStatus != .notDetermined {
      let callbacks = permission; permission.removeAll(); callbacks.forEach { $0(allowed) }
      if !allowed { stop() }
    }
  }
  func start() throws {
    guard allowed, UIApplication.shared.applicationState == .active else { throw nativeError("permissionDenied","请允许前台定位") }
    active = true; manager.startUpdatingLocation()
  }
  @objc func stop() { active = false; manager.stopUpdatingLocation() }
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard active, UIApplication.shared.applicationState == .active, let fix = locations.last, fix.horizontalAccuracy >= 0 else { return }
    sink?(["latitude":fix.coordinate.latitude,"longitude":fix.coordinate.longitude,"accuracy":fix.horizontalAccuracy,"altitude":fix.altitude,"timestamp":Int64(fix.timestamp.timeIntervalSince1970*1000)])
  }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? { sink = events; return nil }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; stop(); return nil }
}
