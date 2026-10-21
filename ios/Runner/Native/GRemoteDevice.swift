import Flutter
import Foundation
import NetworkExtension
import Photos
import UIKit
import Security
import CryptoKit

func nativeError(_ code: String, _ message: String) -> PigeonError {
  PigeonError(code: code, message: message, details: nil)
}
func onMain<T>(_ completion: @escaping (Result<T, Error>) -> Void, _ result: Result<T, Error>) {
  DispatchQueue.main.async { completion(result) }
}

final class GRemoteDevice: NSObject, CameraDeviceHostApi, URLSessionDataDelegate, URLSessionDownloadDelegate, URLSessionWebSocketDelegate, UIDocumentPickerDelegate {
  private let flutter: CameraDeviceFlutterApi
  private let bluetooth = RicohBluetooth()
  private lazy var session: URLSession = makeSession()
  private func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 300
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: config, delegate: self, delegateQueue: .main)
  }
  private var stream: URLSessionDataTask?
  private var socket: URLSessionWebSocketTask?
  private var downloads: [ObjectIdentifier: (String, (Result<String, Error>) -> Void)] = [:]
  private var companionFileResult: ((Result<FlutterStandardTypedData?, Error>) -> Void)?
  private var companionFileLimit = 0
  private var companionFileGeneration = UUID()
  private var connected = false
  private var generation = 0
  init(flutter: CameraDeviceFlutterApi) {
    self.flutter = flutter
    super.init()
    bluetooth.event = { [weak self] type, payload in self?.emit(type, payload) }
  }
  func emit(_ type: String, _ payload: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) else { return }
    DispatchQueue.main.async { self.flutter.onNativeEvent(type: type, jsonPayload: json) { _ in } }
  }
  // Kept for wire compatibility only. Dart handles iOS permissions separately.
  func androidSdkInt() throws -> Int64 { 0 }
  func scan(timeoutMs: Int64, completion: @escaping (Result<[NativeBleDevice?], Error>) -> Void) { bluetooth.scan(milliseconds: timeoutMs, completion: completion) }
  func connectBle(deviceId: String, completion: @escaping (Result<Void, Error>) -> Void) { bluetooth.connect(deviceId, completion: completion) }
  private func closeTransport() {
    let wasConnected = connected
    generation += 1; connected = false
    stream?.cancel(); stream = nil; socket?.cancel(with: .goingAway, reason: nil); socket = nil
    let oldSession = session; session = makeSession(); oldSession.invalidateAndCancel()
    if wasConnected { emit("wifiState", ["state":"lost"]) }
  }
  func disconnectBle(completion: @escaping (Result<Void, Error>) -> Void) {
    closeTransport()
    bluetooth.disconnect(); completion(.success(()))
  }
  func readBootstrap(completion: @escaping (Result<NativeCameraBootstrap, Error>) -> Void) { bluetooth.bootstrap(completion: completion) }
  func setCameraPower(value: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
    guard (0...2).contains(value) else { completion(.failure(nativeError("invalidArgument", "无效电源参数"))); return }
    bluetooth.write(RicohBluetooth.power, value: Data([UInt8(value)]), completion: completion)
  }
  func setNetworkType(value: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
    guard (0...1).contains(value) else { completion(.failure(nativeError("invalidArgument", "无效网络参数"))); return }
    bluetooth.write(RicohBluetooth.network, value: Data([UInt8(value)]), completion: completion)
  }
  func writeOperationRequest(value: FlutterStandardTypedData, completion: @escaping (Result<Void, Error>) -> Void) {
    guard value.data.count == 2 else { completion(.failure(nativeError("invalidArgument", "相机操作需要两个字节"))); return }
    bluetooth.write(RicohBluetooth.request, value: value.data, completion: completion)
  }
  func connectCameraWifi(ssid: String, passphrase: String, completion: @escaping (Result<Void, Error>) -> Void) {
    closeTransport(); let token = generation
    func probe() {
      guard self.generation == token else { completion(.failure(nativeError("wifiCancelled", "连接已取消"))); return }
      let request = URLRequest(url: try! CameraEndpoint.url("/v1/props"))
      self.session.dataTask(with: request) { _, response, error in
        DispatchQueue.main.async {
          guard self.generation == token else { completion(.failure(nativeError("wifiCancelled", "连接已取消"))); return }
          if let error = error { completion(.failure(error)); return }
          guard (response as? HTTPURLResponse)?.statusCode == 200 else { completion(.failure(nativeError("cameraUnavailable", "请确认已连接相机 Wi-Fi，并允许本地网络访问"))); return }
          self.connected = true; self.emit("wifiState", ["state":"connected"]); completion(.success(()))
        }
      }.resume()
    }
    // Empty SSID means the user has joined the camera network in Settings.
    if ssid.isEmpty { probe(); return }
    let config = passphrase.isEmpty ? NEHotspotConfiguration(ssid: ssid) : NEHotspotConfiguration(ssid: ssid, passphrase: passphrase, isWEP: false)
    config.joinOnce = true
    NEHotspotConfigurationManager.shared.apply(config) { error in
      DispatchQueue.main.async {
        if let error = error as NSError?, !(error.domain == NEHotspotConfigurationErrorDomain && error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue) {
          completion(.failure(nativeError("wifiConnectFailed", "请在系统设置连接相机 Wi-Fi 后重试"))); return
        }
        probe()
      }
    }
  }
  // Network binding for the companion service has not been proven on iOS.
  func companionRequest(method: String, path: String, headers: [String?: String?], body: FlutterStandardTypedData?, completion: @escaping (Result<NativeHttpResponse, Error>) -> Void) {
    completion(.failure(nativeError("companionUnsupported", "iOS 暂不支持相机伴侣网络；仍可离线试卷与整理数字胶卷")))
  }
  func pickCompanionFile(kind: String, completion: @escaping (Result<FlutterStandardTypedData?, Error>) -> Void) {
    guard ["pairing", "film"].contains(kind), companionFileResult == nil else { completion(.failure(nativeError("companionPickerBusy", "文件选择暂不可用"))); return }
    guard var controller = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController else { completion(.failure(nativeError("companionPickerFailed", "无法打开文件选择器"))); return }
    while let presented = controller.presentedViewController { controller = presented }
    companionFileGeneration = UUID()
    companionFileLimit = kind == "pairing" ? 4096 : 18432; companionFileResult = completion
    let picker = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .import); picker.delegate = self; picker.allowsMultipleSelection = false
    controller.present(picker, animated: !UIAccessibility.isReduceMotionEnabled)
  }
  func cancelCompanionFileRead() {
    companionFileGeneration = UUID()
    let completion = companionFileResult; companionFileResult = nil
    completion?(.failure(nativeError("companionPickerCancelled", "文件读取已取消")))
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    companionFileGeneration = UUID()
    let completion = companionFileResult; companionFileResult = nil; completion?(.success(nil))
  }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard companionFileResult != nil else { return }
    let token = companionFileGeneration, limit = companionFileLimit
    guard let url = urls.first else { cancelCompanionFileRead(); return }
    // Provider coordination and bounded reads can block; never run on UIKit's queue.
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result: Result<Data, Error>
      do {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url); defer { handle.closeFile() }
        let data = handle.readData(ofLength: limit + 1)
        guard !data.isEmpty, data.count <= limit else { throw nativeError("invalidCompanionFile", "文件为空或超过大小限制") }
        result = .success(data)
      } catch { result = .failure(nativeError("invalidCompanionFile", "文件读取失败或超过大小限制")) }
      DispatchQueue.main.async { [weak self] in
        guard let self = self, self.companionFileGeneration == token,
          let completion = self.companionFileResult else { return }
        self.companionFileResult = nil
        self.companionFileGeneration = UUID()
        completion(result.map { FlutterStandardTypedData(bytes: $0) })
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
      guard let self = self, self.companionFileGeneration == token,
        let completion = self.companionFileResult else { return }
      self.companionFileGeneration = UUID(); self.companionFileResult = nil
      completion(.failure(nativeError("invalidCompanionFile", "文件读取超时，请下载到本机后重试")))
    }
  }
  private func pairingQuery(_ instanceId: String) throws -> [String: Any] {
    guard instanceId.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil else { throw nativeError("invalidArgument", "无效相机身份") }
    return [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"com.izhaoo.gremote.companion", kSecAttrAccount as String:instanceId]
  }
  func saveCompanionPairing(instanceId: String, keyBytes: FlutterStandardTypedData, completion: @escaping (Result<Void, Error>) -> Void) {
    do {
      guard keyBytes.data.count == 32 else { throw nativeError("invalidArgument", "配对密钥长度无效") }
      let query = try pairingQuery(instanceId)
      let fields: [String: Any] = [kSecValueData as String:keyBytes.data, kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
      var status = SecItemUpdate(query as CFDictionary, fields as CFDictionary)
      if status == errSecItemNotFound { status = SecItemAdd(query.merging(fields) { _, new in new } as CFDictionary, nil) }
      guard status == errSecSuccess else { throw nativeError("pairingStoreFailed", "无法保存相机配对") }
      completion(.success(()))
    } catch { completion(.failure(error)) }
  }
  func removeCompanionPairing(instanceId: String, completion: @escaping (Result<Void, Error>) -> Void) {
    do { let status = SecItemDelete(try pairingQuery(instanceId) as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else { throw nativeError("pairingStoreFailed", "无法移除相机配对") }
      completion(.success(()))
    } catch { completion(.failure(error)) }
  }
  func signCompanionRequest(instanceId: String, canonicalBytes: FlutterStandardTypedData, completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void) {
    do {
      guard canonicalBytes.data.count <= 1024 else { throw nativeError("invalidArgument", "签名内容超限") }
      var query = try pairingQuery(instanceId); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
      var result: CFTypeRef?
      guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data, data.count == 32 else { throw nativeError("pairingMissing", "请重新导入相机配对") }
      let mac = HMAC<SHA256>.authenticationCode(for: canonicalBytes.data, using: SymmetricKey(data:data))
      completion(.success(FlutterStandardTypedData(bytes:Data(mac))))
    } catch { completion(.failure(error)) }
  }
  func cameraRequest(method: String, url: String, headers: [String?: String?], body: FlutterStandardTypedData?, completion: @escaping (Result<NativeHttpResponse, Error>) -> Void) {
    do {
      guard connected else { throw nativeError("wifiNotConnected", "请先连接相机 Wi-Fi") }
      var request = URLRequest(url: try CameraEndpoint.url(url)); request.httpMethod = method; request.httpBody = body?.data
      for (key, value) in headers { if let key = key, let value = value { request.setValue(value, forHTTPHeaderField: key) } }
      let token = generation
      session.dataTask(with: request) { data, response, error in
        DispatchQueue.main.async {
          guard self.generation == token else { completion(.failure(nativeError("wifiCancelled", "连接已结束"))); return }
          if let error = error { completion(.failure(error)); return }
          guard let response = response as? HTTPURLResponse else { completion(.failure(nativeError("cameraHttpStatus", "相机未返回 HTTP 响应"))); return }
          var fields: [String?: String?] = [:]
          for (key, value) in response.allHeaderFields { fields[String(describing:key)] = String(describing:value) }
          completion(.success(NativeHttpResponse(statusCode: Int64(response.statusCode), headers: fields, body: FlutterStandardTypedData(bytes:data ?? Data()))))
        }
      }.resume()
    } catch { completion(.failure(error)) }
  }
  func startLiveView(url: String, completion: @escaping (Result<Void, Error>) -> Void) {
    do {
      guard connected else { throw nativeError("wifiNotConnected", "请先连接相机 Wi-Fi") }
      stream?.cancel(); stream = session.dataTask(with: try CameraEndpoint.url(url)); stream?.resume(); completion(.success(()))
    } catch { completion(.failure(error)) }
  }
  func stopLiveView(completion: @escaping (Result<Void, Error>) -> Void) { stream?.cancel(); stream = nil; completion(.success(())) }
  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard stream === dataTask else { return }
    flutter.onLiveViewChunk(bytes: FlutterStandardTypedData(bytes:data)) { _ in }
  }
  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
      completionHandler(.cancel); if stream === dataTask { emit("liveView", ["state":"failed"]) }; return
    }
    completionHandler(.allow)
  }
  func openChangeSocket(path: String, completion: @escaping (Result<Void, Error>) -> Void) {
    do {
      guard connected else { throw nativeError("wifiNotConnected", "请先连接相机 Wi-Fi") }
      socket?.cancel(with:.normalClosure,reason:nil)
      let task = session.webSocketTask(with: try CameraEndpoint.url(path, socket:true)); socket = task; task.resume(); receive(task); completion(.success(()))
    } catch { completion(.failure(error)) }
  }
  func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
    guard socket === webSocketTask else { return }
    emit("changes.open", [:])
  }
  func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
    guard socket === webSocketTask else { return }
    socket = nil; emit("changes.closed", ["code":closeCode.rawValue])
  }
  private func receive(_ task: URLSessionWebSocketTask) {
    task.receive { result in
      DispatchQueue.main.async {
        guard self.socket === task else { return }
        switch result {
        case .success(let message):
          if case .string(let text) = message { self.emit("changes.message", ["text":text]) }
          self.receive(task)
        case .failure: self.socket = nil; self.emit("changes.failure", [:])
        }
      }
    }
  }
  func closeChangeSocket(completion: @escaping (Result<Void, Error>) -> Void) { socket?.cancel(with:.normalClosure,reason:nil); socket = nil; completion(.success(())) }
  func setKeepScreenOn(on: Bool) throws { UIApplication.shared.isIdleTimerDisabled = on }
  func downloadPhoto(directory: String, fileName: String, completion: @escaping (Result<String, Error>) -> Void) {
    do {
      guard connected else { throw nativeError("wifiNotConnected", "请先连接相机 Wi-Fi") }
      let task = session.downloadTask(with: try CameraEndpoint.photo(directory:directory,file:fileName))
      downloads[ObjectIdentifier(task)] = ("\(directory)/\(fileName)", completion); task.resume()
    } catch { completion(.failure(error)) }
  }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    guard let transfer = downloads[ObjectIdentifier(downloadTask)] else { return }
    emit("photoProgress", ["id":transfer.0,"bytes":totalBytesWritten,"total":totalBytesExpectedToWrite])
  }
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    guard let transfer = downloads.removeValue(forKey:ObjectIdentifier(downloadTask)) else { return }
    guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200,
          let size = try? location.resourceValues(forKeys:[.fileSizeKey]).fileSize, size > 0,
          !((response.mimeType ?? "").contains("json")) else { transfer.1(.failure(nativeError("invalidPhoto", "下载内容不是照片"))); return }
    let name = String(transfer.0.split(separator:"/").last!)
    let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+"-"+name)
    do { try FileManager.default.moveItem(at:location,to:copy) }
    catch { transfer.1(.failure(error)); return }
    let token = generation
    GRemoteMedia.savePhoto(copy, name:name) { result in
      try? FileManager.default.removeItem(at:copy)
      guard self.generation == token else { transfer.1(.failure(nativeError("wifiCancelled", "连接已结束"))); return }
      transfer.1(result)
    }
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let transfer = downloads.removeValue(forKey:ObjectIdentifier(task)) { transfer.1(.failure(error ?? nativeError("downloadFailed", "下载未完成"))) }
    if stream === task { stream = nil; if error != nil { emit("liveView", ["state":"failed"]) } }
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    guard let url = request.url, (try? CameraEndpoint.url(url.absoluteString)) != nil else { completionHandler(nil); return }
    completionHandler(request)
  }
}
