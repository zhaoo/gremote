import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// iOS masks app icons itself; the submitted source must be opaque RGB.
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
for url in files where url.pathExtension.lowercased() == "png" {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let original = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: original.width, height: original.height,
                                  bitsPerComponent: 8, bytesPerRow: original.width * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("Cannot decode icon: \(url.path)") }
    context.setFillColor(CGColor(red: 17.0 / 255, green: 17.0 / 255, blue: 17.0 / 255, alpha: 1))
    let bounds = CGRect(x: 0, y: 0, width: original.width, height: original.height)
    context.fill(bounds)
    context.draw(original, in: bounds)
    guard let result = context.makeImage() else { fatalError("Cannot flatten icon") }
    CGImageDestinationAddImage(destination, result, nil)
    guard CGImageDestinationFinalize(destination),
          let check = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(check, 0, nil) as? [CFString: Any],
          (properties[kCGImagePropertyHasAlpha] as? Bool) != true
    else { fatalError("Icon still has alpha: \(url.path)") }
    print("Opaque RGB: \(url.lastPathComponent) \(original.width)x\(original.height)")
}
