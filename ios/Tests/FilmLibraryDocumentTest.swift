@main
struct FilmLibraryDocumentTest {
  static func main() throws {
    func library() -> [UInt8] {
      var bytes = [UInt8](repeating: 0, count: 4096 + 12288)
      bytes.replaceSubrange(0..<8, with: Array("M10VSD1\0".utf8))
      func field(_ offset: Int, _ value: UInt32) {
        for index in 0..<4 { bytes[offset + index] = UInt8((value >> (8 * index)) & 255) }
      }
      field(8, 1); field(12, UInt32(bytes.count)); field(16, 1)
      field(20, 12288); field(24, 239); field(28, 1)
      // Known CRC32 of this fixed 4092-byte header, independently generated.
      field(4092, 0x9ba20b23)
      return bytes
    }
    try FilmLibraryDocument.validate(library())
    for bad in [[UInt8](), [UInt8](repeating: 0, count: 4096 + 256 * 12288 + 1),
                [UInt8](repeating: 0, count: 16384)] {
      do { try FilmLibraryDocument.validate(bad); fatalError("invalid library accepted") }
      catch { }
    }
    var corrupt = library(); corrupt[4092] ^= 1
    do { try FilmLibraryDocument.validate(corrupt); fatalError("bad CRC accepted") }
    catch { }
    print("FilmLibraryDocument validation passed")
  }
}
