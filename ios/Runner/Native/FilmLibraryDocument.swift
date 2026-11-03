/// Basic native envelope validation; Dart validates every film record first.
enum FilmLibraryDocument {
  enum ValidationError: Error { case invalid }
  static func validate(_ bytes: [UInt8]) throws {
    func require(_ condition: Bool) throws {
      if !condition { throw ValidationError.invalid }
    }
    try require(bytes.count >= 4096 && bytes.count <= 4096 + 256 * 12288)
    try require(bytes.prefix(8).elementsEqual("M10VSD1\0".utf8))
    func field(_ offset: Int) -> UInt32 {
      (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
    }
    let count = field(16)
    try require(field(8) == 1 && count > 0 && count <= 256 &&
        field(12) == UInt32(bytes.count) && field(20) == 12288 &&
        bytes.count == 4096 + Int(count) * 12288 &&
        field(24) == 239 && field(28) == 1)
    var crc = UInt32.max
    for byte in bytes.prefix(4092) {
      crc ^= UInt32(byte)
      for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
    }
    try require(~crc == field(4092))
  }
}
