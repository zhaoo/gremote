import Foundation

enum RicohRecordedFilm {
  struct Record {
    let code: Int
    let capturedAt: String?
    let exposureRecipe: String?
  }

  static func read(_ file: FileHandle) throws -> Record? {
    guard let prefix = try file.read(upToCount: 256 * 1024) else { return nil }
    let bytes = [UInt8](prefix)
    let root = Directory(bytes: bytes, range: bytes.indices)
    guard root.byte(0) == 255, root.byte(1) == 216 else {
      return readTiff(root, jpeg: false)
    }
    var marker = 2
    while root.byte(marker) == 255 {
      repeat { marker += 1 } while root.byte(marker) == 255
      guard let type = root.byte(marker), type != 0xda, type != 0xd9 else { break }
      marker += 1
      guard let size = root.word(marker), size >= 2, root.contains(marker, size) else { break }
      if type == 0xe1, size >= 8, root.magic(marker + 2, "Exif\0\0") {
        return readTiff(Directory(bytes: bytes, range: (marker + 8)..<(marker + size)), jpeg: true)
      }
      marker += size
    }
    return nil
  }

  private static func readTiff(_ root: Directory, jpeg: Bool) -> Record? {
    guard let tiff = root.withByteOrder(0), tiff.word(2) == 42,
          let first = tiff.offset(4) else { return nil }
    let exif = tiff.value(first, 0x8769, 4, size: 4).flatMap { tiff.offset($0.lowerBound) }
    let noteRange = jpeg ? exif.flatMap { tiff.value($0, 0x927c, 7) }
                         : tiff.value(first, 0xc634, 1)
    guard let noteRange else { return nil }
    let base = tiff.range.lowerBound
    let note = Directory(bytes: tiff.bytes, range: (base + noteRange.lowerBound)..<(base + noteRange.upperBound))
    guard note.magic(0, "RICOH\0"), let maker = note.withByteOrder(6),
          let tone = maker.value(8, 0x004f, 3, size: 2),
          let code = maker.word(tone.lowerBound),
          (0x1001...0x104e).contains(code) || (0x1121...0x114e).contains(code) ||
          (0x2000..<(0x2000 + 210 * 235)).contains(code) else { return nil }
    let timestamp = exif.flatMap { tiff.value($0, 0x9003, 2, size: 20) }.flatMap { field -> String? in
      guard tiff.byte(field.upperBound - 1) == 0 else { return nil }
      let date = String(decoding: tiff.bytes[(base + field.lowerBound)..<(base + field.upperBound - 1)], as: UTF8.self)
      return date.range(of: #"^[0-9]{4}:[0-9]{2}:[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$"#,
                        options: .regularExpression) == nil ? nil : date
    }
    return Record(code: code, capturedAt: timestamp, exposureRecipe: readRecipe(maker))
  }

  private static func readRecipe(_ maker: Directory) -> String? {
    guard let field = maker.value(8, 0xc7f1, 7) else { return nil }
    let signature: String
    switch field.count {
    case 80: signature = "MCR1"
    case 176: signature = "MCR2"
    default: return nil
    }
    guard maker.magic(field.lowerBound, signature) else { return nil }
    let first = maker.range.lowerBound + field.lowerBound
    let end = maker.range.lowerBound + field.upperBound
    var crc: UInt32 = 0xffffffff
    for byte in maker.bytes[first..<(end - 4)] {
      crc ^= UInt32(byte)
      for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xedb88320) }
    }
    let expected = (0..<4).reduce(UInt32(0)) { $0 | UInt32(maker.bytes[end - 4 + $1]) << ($1 * 8) }
    guard crc ^ 0xffffffff == expected else { return nil }
    return maker.bytes[first..<end].map { String(format: "%02x", $0) }.joined()
  }

  private struct Directory {
    let bytes: [UInt8]
    let range: Range<Int>
    var little = false

    func contains(_ at: Int, _ size: Int) -> Bool {
      at >= 0 && size >= 0 && at <= range.count - size
    }
    func byte(_ at: Int) -> UInt8? {
      contains(at, 1) ? bytes[range.lowerBound + at] : nil
    }
    func magic(_ at: Int, _ text: String) -> Bool {
      text.utf8.enumerated().allSatisfy { byte(at + $0.offset) == $0.element }
    }
    func withByteOrder(_ at: Int) -> Self? {
      if magic(at, "II") { return Self(bytes: bytes, range: range, little: true) }
      return magic(at, "MM") ? self : nil
    }
    func word(_ at: Int) -> Int? {
      guard let a = byte(at), let b = byte(at + 1) else { return nil }
      return little ? Int(a) | (Int(b) << 8) : (Int(a) << 8) | Int(b)
    }
    func offset(_ at: Int) -> Int? {
      guard let a = word(at), let b = word(at + 2) else { return nil }
      return little ? a | (b << 16) : (a << 16) | b
    }
    func value(_ ifd: Int, _ tag: Int, _ type: Int, size fixedSize: Int? = nil) -> Range<Int>? {
      guard let count = word(ifd), contains(ifd, 2 + count * 12) else { return nil }
      for row in 0..<count {
        let entry = ifd + 2 + row * 12
        guard word(entry) == tag else { continue }
        guard word(entry + 2) == type, let units = offset(entry + 4), units > 0 else { return nil }
        let unitSize = type == 3 ? 2 : type == 4 ? 4 : 1
        guard unitSize == 1 || units == 1 else { return nil }
        let size = units * unitSize
        guard fixedSize == nil || size == fixedSize else { return nil }
        guard let start = size <= 4 ? entry + 8 : offset(entry + 8) else { return nil }
        let length = min(size, range.count - start)
        guard length > 0, length == size || tag == 0xc634 else { return nil }
        return start..<(start + length)
      }
      return nil
    }
  }
}
