@main struct PhotoPolicyTests {
  static func main() {
    assert(PhotoPolicy.editable("R0001.JPG"))
    assert(PhotoPolicy.editable("IMG_1.jpeg"))
    for value in ["IMG_1.HEIC", "IMG_1.PNG", "R0001.DNG", "photo.jpg.exe"] { assert(!PhotoPolicy.editable(value)) }
    assert(PhotoPolicy.modifiedSeconds(1792371000.5) == 1792371000)
    print("JPEG policy and timestamp tests passed")
  }
}
