import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
  func testJPEGEditingScope() {
    XCTAssertTrue(PhotoPolicy.editable("R0001.JPG"))
    XCTAssertTrue(PhotoPolicy.editable("IMG_1.jpeg"))
    for name in ["IMG_1.HEIC", "photo.PNG", "R0001.DNG", "photo.jpg.exe"] {
      XCTAssertFalse(PhotoPolicy.editable(name))
    }
  }
  func testModificationTimestampUsesSeconds() {
    XCTAssertEqual(PhotoPolicy.modifiedSeconds(1792371000.5),1792371000)
  }
  func testCameraURLCannotEscapeLocalHost() throws {
    XCTAssertEqual(try CameraEndpoint.url("/v1/props").absoluteString,"http://192.168.0.1/v1/props")
    for value in ["https://example.com/v1/props", "http://192.168.0.1@evil.com/v1/props", "//evil.com/v1/props", "file:///etc/passwd"] {
      XCTAssertThrowsError(try CameraEndpoint.url(value))
    }
  }
  func testPhotoPathCannotTraverse() throws {
    for value in ["../DCIM", "a/b", "", ".", "..", "a?b"] {
      XCTAssertThrowsError(try CameraEndpoint.photo(directory:value,file:"R0001.JPG"))
    }
    XCTAssertEqual(try CameraEndpoint.photo(directory:"100RICOH",file:"R0001.DNG").path,"/v1/photos/100RICOH/R0001.DNG")
  }
}
