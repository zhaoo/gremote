import Foundation

@main
struct CompanionWireTests {
  static func rejects(_ operation: () throws -> Void) {
    do {
      try operation()
      fatalError("Expected rejection")
    } catch {}
  }

  static func main() throws {
    let hotspot = try CompanionWire.request(method: "GET", path: CompanionWire.hotspot,
      headers: ["X-M10V-Hotspot": "1"], body: Data())
    precondition(String(decoding: hotspot, as: UTF8.self) ==
      "GET /m10v/v1/hotspot HTTP/1.1\r\nHost: 192.168.0.1:18743\r\nConnection: close\r\nx-m10v-hotspot: 1\r\n\r\n")

    rejects { _ = try CompanionWire.request(method: "GET", path: CompanionWire.hotspot, headers: [:], body: Data()) }
    for path in ["/m10v/v1/state?x=1", "/m10v/v1/state\n", "//192.168.0.1/m10v/v1/state", "/v1/camera/shoot"] {
      rejects { _ = try CompanionWire.request(method: "GET", path: path, headers: [:], body: Data()) }
    }
    rejects { _ = try CompanionWire.request(method: "GET", path: "/m10v/v1/state",
      headers: ["X-M10V-Nonce": "a", "x-m10v-nonce": "b"], body: Data()) }
    rejects { _ = try CompanionWire.request(method: "GET", path: "/m10v/v1/state",
      headers: ["Host": "outside"], body: Data()) }

    let payload = Data("{\"field\":\"hdf\",\"value\":2}".utf8)
    let write = try CompanionWire.request(method: "POST", path: "/m10v/v1/extensions/operations",
      headers: ["X-M10V-Signature": String(repeating: "a", count: 64)], body: payload)
    precondition(write.suffix(payload.count) == payload)
    precondition(String(decoding: write, as: UTF8.self).contains("Content-Length: \(payload.count)\r\n"))

    let head = "HTTP/1.1 200 Response\r\nX-M10V-Boot: 123\r\nContent-Length: 2\r\n\r\n"
    let truncated = try CompanionWire.response(Data((head + "{").utf8))
    precondition(truncated == nil)
    let complete = try CompanionWire.response(Data((head + "{}").utf8))
    precondition(complete?.status == 200 && complete?.headers["x-m10v-boot"] == "123")
    precondition(complete?.body == Data("{}".utf8))
    for response in [
      "HTTP/1.1 302 Redirect\r\nLocation: http://outside\r\nContent-Length: 0\r\n\r\n",
      "HTTP/1.1 200 Response\r\nContent-Length: 16385\r\n\r\n",
      "HTTP/1.1 200 Response\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n",
      "HTTP/1.1 200 Response\r\nContent-Length: 0\r\nTransfer-Encoding: chunked\r\n\r\n",
      head + "{}x",
    ] {
      rejects { _ = try CompanionWire.response(Data(response.utf8)) }
    }
    print("Companion HTTP framing checks passed")
  }
}
