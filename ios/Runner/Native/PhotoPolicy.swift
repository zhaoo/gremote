// The native imaging ABI accepts JPEG input. Do not expose unsupported formats.
enum PhotoPolicy {
  static func editable(_ filename: String) -> Bool {
    let name = filename.lowercased()
    return name.hasSuffix(".jpg") || name.hasSuffix(".jpeg")
  }
  static func modifiedSeconds(_ timestamp: Double) -> Int64 { Int64(timestamp) }
}
