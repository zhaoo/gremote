import Darwin
import Foundation
import Network

/// A local IPv4 address belonging to the Wi-Fi path, never a cellular or VPN address.
struct CameraWiFi: Equatable {
  let interface: NWInterface
  let address: String

  static func current(_ path: NWPath?) -> CameraWiFi? {
    guard let path = path, path.status == .satisfied, path.usesInterfaceType(.wifi),
          let interface = path.availableInterfaces.first(where: { $0.type == .wifi })
    else { return nil }

    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0, let first = head else { return nil }
    defer { freeifaddrs(first) }
    var cursor: UnsafeMutablePointer<ifaddrs>? = first
    while let entry = cursor?.pointee {
      cursor = entry.ifa_next
      guard let name = entry.ifa_name, String(cString: name) == interface.name,
            let address = entry.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
            let mask = entry.ifa_netmask else { continue }
      let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
        UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
      }
      let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
        UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
      }
      let last = ip & 255
      if ip & 0xffffff00 == 0xc0a80000 && (2...254).contains(last) && netmask == 0xffffff00 {
        return CameraWiFi(interface: interface, address: "192.168.0.\(last)")
      }
    }
    return nil
  }
}

enum CompanionWire {
  enum Failure: Error { case request, response, timeout, disconnected }
  static let maxBody = 16_384
  static let maxHead = 2_048
  static let authority = "192.168.0.1:18743"
  static let hotspot = "/m10v/v1/hotspot"
  private static let route = #"\A/m10v/v1/(?:hotspot|capabilities|state|extensions/(?:capabilities|state|operations(?:/[a-f0-9]{32})?)|operations(?:/[a-f0-9]{32})?|films/stage(?:/[a-f0-9]{32}(?:/(?:verify|chunks/[0-2]))?)?)\z"#
  private static let allowed = Set(["x-m10v-keyid", "x-m10v-nonce", "x-m10v-boot",
    "x-m10v-session", "x-m10v-seq", "x-m10v-signature", "x-m10v-chunk-hash", "content-type"])

  static func request(method: String, path: String, headers: [String?: String?], body: Data) throws -> Data {
    guard ["GET", "POST", "PUT"].contains(method), path.range(of: route, options: .regularExpression) != nil,
          headers.count <= 8, body.count <= maxBody, method != "GET" || body.isEmpty
    else { throw Failure.request }

    if path == hotspot && (method != "GET" || headers != ["X-M10V-Hotspot": "1"]) {
      throw Failure.request
    }
    var head = "\(method) \(path) HTTP/1.1\r\nHost: \(authority)\r\nConnection: close\r\n"
    var names = Set<String>()
    for (rawName, rawValue) in headers {
      guard let name = rawName?.lowercased(), let value = rawValue,
            allowed.contains(name) || (name == "x-m10v-hotspot" && path == hotspot),
            names.insert(name).inserted, value.utf8.count <= 80,
            value.utf8.allSatisfy({ (32...126).contains($0) }) else { throw Failure.request }
      head += "\(name): \(value)\r\n"
    }
    if method != "GET" { head += "Content-Length: \(body.count)\r\n" }
    var bytes = Data((head + "\r\n").utf8)
    bytes.append(body)
    return bytes
  }

  struct Response {
    let status: Int
    let headers: [String: String]
    let body: Data
  }

  /// The M10V HTTP server always sends a bounded Content-Length and closes.
  static func response(_ bytes: Data) throws -> Response? {
    guard let end = bytes.range(of: Data("\r\n\r\n".utf8)) else {
      if bytes.count >= maxHead { throw Failure.response }
      return nil
    }
    guard end.upperBound <= maxHead,
          let header = String(data: bytes[..<end.lowerBound], encoding: .ascii)
    else { throw Failure.response }
    let lines = header.components(separatedBy: "\r\n")
    let statusLine = lines[0].split(separator: " ", maxSplits: 2)
    guard statusLine.count >= 2, statusLine[0] == "HTTP/1.1",
          let status = Int(statusLine[1]), (200...599).contains(status), !(300...399).contains(status)
    else { throw Failure.response }
    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      guard let colon = line.firstIndex(of: ":") else { throw Failure.response }
      let name = line[..<colon].lowercased()
      guard name.range(of: #"\A[a-z0-9-]+\z"#, options: .regularExpression) != nil,
            headers[name] == nil else { throw Failure.response }
      headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }
    guard headers["transfer-encoding"] == nil,
          let raw = headers["content-length"], let length = Int(raw),
          (0...maxBody).contains(length), raw == String(length) else { throw Failure.response }
    let size = bytes.count - end.upperBound
    if size < length { return nil }
    guard size == length else { throw Failure.response }
    return Response(status: status, headers: headers, body: Data(bytes[end.upperBound...]))
  }
}

/// One direct TCP request. No DNS, proxy, redirects, or replay on path change.
final class CompanionHTTP {
  private let connection: NWConnection
  private let request: Data
  private var completion: ((Result<CompanionWire.Response, Error>) -> Void)?
  private var received = Data()
  private var sent = false

  init(wifi: CameraWiFi, request: Data) {
    let parameters = NWParameters.tcp
    parameters.preferNoProxies = true
    parameters.requiredInterface = wifi.interface
    parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(wifi.address), port: .any)
    connection = NWConnection(host: "192.168.0.1", port: 18743, using: parameters)
    self.request = request
  }

  func start(isCurrent: @escaping () -> Bool, completion: @escaping (Result<CompanionWire.Response, Error>) -> Void) {
    self.completion = completion
    connection.stateUpdateHandler = { [weak self] state in
      guard let self = self else { return }
      switch state {
      case .ready:
        guard !self.sent else { return }
        guard isCurrent() else {
          self.finish(.failure(CompanionWire.Failure.disconnected))
          return
        }
        self.sent = true
        self.connection.send(content: self.request, completion: .contentProcessed { error in
          if let error = error { self.finish(.failure(error)) }
          else { self.receive() }
        })
      case .waiting(let error) where self.sent: self.finish(.failure(error))
      case .failed(let error): self.finish(.failure(error))
      case .cancelled: self.finish(.failure(CompanionWire.Failure.disconnected))
      default: break
      }
    }
    connection.start(queue: .main)
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
      self?.finish(.failure(CompanionWire.Failure.timeout))
    }
  }

  func cancel() { finish(.failure(CompanionWire.Failure.disconnected)) }

  private func receive() {
    guard completion != nil else { return }
    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, ended, error in
      guard self.completion != nil else { return }
      if let error = error { self.finish(.failure(error)); return }
      if let data = data { self.received.append(data) }
      do {
        guard self.received.count <= CompanionWire.maxHead + CompanionWire.maxBody else {
          throw CompanionWire.Failure.response
        }
        if let response = try CompanionWire.response(self.received) { self.finish(.success(response)) }
        else if ended { throw CompanionWire.Failure.response }
        else { self.receive() }
      } catch { self.finish(.failure(error)) }
    }
  }

  private func finish(_ result: Result<CompanionWire.Response, Error>) {
    guard let callback = completion else { return }
    completion = nil
    connection.stateUpdateHandler = nil
    connection.cancel()
    callback(result)
  }
}
