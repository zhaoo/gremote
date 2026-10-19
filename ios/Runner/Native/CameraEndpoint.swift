import Foundation

enum CameraEndpoint {
  enum Invalid: Error { case url, component }
  static func url(_ value: String, socket: Bool = false) throws -> URL {
    guard !value.hasPrefix("//"), let url = URL(string: value, relativeTo: URL(string: "http://192.168.0.1"))?.absoluteURL,
          url.host == "192.168.0.1", url.user == nil, url.password == nil,
          url.port == nil || url.port == 80, url.scheme == "http", url.path.hasPrefix("/v1/") else { throw Invalid.url }
    if socket {
      var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
      components.scheme = "ws"
      return components.url!
    }
    return url
  }
  static func photo(directory: String, file: String) throws -> URL {
    for value in [directory, file] {
      guard !value.isEmpty, value != ".", value != "..",
            value.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil else { throw Invalid.component }
    }
    guard ["jpg", "jpeg", "dng"].contains((file as NSString).pathExtension.lowercased()) else { throw Invalid.component }
    return try url("/v1/photos/\(directory)/\(file)?size=full")
  }
}
