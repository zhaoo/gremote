import Foundation
@main struct Tests {
 static func main() throws {
  let props = try CameraEndpoint.url("/v1/props"); assert(props.absoluteString == "http://192.168.0.1/v1/props")
  for value in ["https://example.com/v1/props", "http://192.168.0.1@evil.com/v1/props", "file:///etc/passwd", "//evil.com/v1/props"] {
   do { _ = try CameraEndpoint.url(value); fatalError("accepted unsafe URL") } catch {}
  }
  for value in ["../DCIM", "a/b", "", ".", "..", "a?b"] {
   do { _ = try CameraEndpoint.photo(directory:value, file:"R0001.JPG"); fatalError("accepted unsafe component") } catch {}
  }
  let photo = try CameraEndpoint.photo(directory:"100RICOH",file:"R0001.DNG"); assert(photo.path == "/v1/photos/100RICOH/R0001.DNG")
  print("Camera endpoint safety tests passed")
 }
}
