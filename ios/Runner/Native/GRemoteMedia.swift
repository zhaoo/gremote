import CoreLocation
import Darwin
import Flutter
import ImageIO
import Photos
import UIKit

final class GRemoteMedia: MediaHostApi {
  private weak var controller: UIViewController?
  private let location: GRemoteLocation
  private var ids: [String: Int64] = [:]
  private var identifiers: [Int64: String] = [:]
  private var nextID: Int64 = 1
  init(controller: UIViewController, location: GRemoteLocation) {
    self.controller = controller; self.location = location
    let stored = UserDefaults.standard.dictionary(forKey:"gremote.photoIDs") ?? [:]
    for (key, value) in stored { if let value = value as? NSNumber { ids[key] = value.int64Value; identifiers[value.int64Value] = key; nextID = max(nextID,value.int64Value+1) } }
  }
  private func id(_ identifier: String) -> Int64 {
    if let id = ids[identifier] { return id }
    let value = nextID; nextID += 1; ids[identifier] = value; identifiers[value] = identifier
    UserDefaults.standard.set(ids,forKey:"gremote.photoIDs"); return value
  }
  private func asset(_ id: Int64) -> PHAsset? {
    guard let identifier = identifiers[id] else { return nil }
    return PHAsset.fetchAssets(withLocalIdentifiers:[identifier],options:nil).firstObject
  }
  func access() throws -> NativeMediaAccess { Self.map(PHPhotoLibrary.authorizationStatus(for:.readWrite)) }
  private static func map(_ status: PHAuthorizationStatus) -> NativeMediaAccess {
    switch status { case .authorized:return .granted; case .limited:return .partial; default:return .denied }
  }
  func requestAccess(completion: @escaping (Result<NativeMediaAccess, Error>) -> Void) {
    PHPhotoLibrary.requestAuthorization(for:.readWrite) { onMain(completion,.success(Self.map($0))) }
  }
  func hasLocationAccess() throws -> Bool { location.allowed }
  func requestLocationAccess(completion: @escaping (Result<Bool, Error>) -> Void) { location.requestPermission { completion(.success($0)) } }
  func queryImages(completion: @escaping (Result<[NativeMediaEntry], Error>) -> Void) {
    guard (try? access()) != .denied else { completion(.failure(nativeError("permissionDenied","请允许访问照片"))); return }
    let options = PHFetchOptions(); options.sortDescriptors = [NSSortDescriptor(key:"creationDate",ascending:false)]
    let assets = PHAsset.fetchAssets(with:.image,options:options)
    var entries: [NativeMediaEntry] = []
    assets.enumerateObjects { asset,_,_ in
      let name = PHAssetResource.assetResources(for:asset).first?.originalFilename ?? ""
      guard PhotoPolicy.editable(name) else { return }
      entries.append(NativeMediaEntry(id:self.id(asset.localIdentifier),uri:"ph://"+asset.localIdentifier,displayName:name,dateModified:PhotoPolicy.modifiedSeconds((asset.modificationDate ?? asset.creationDate ?? Date()).timeIntervalSince1970),dateTaken:asset.creationDate.map { Int64($0.timeIntervalSince1970*1000) },width:Int64(asset.pixelWidth),height:Int64(asset.pixelHeight)))
    }
    completion(.success(entries))
  }
  private func data(_ id: Int64, completion: @escaping (Result<Data, Error>) -> Void) {
    guard let asset = asset(id) else { completion(.failure(nativeError("photoUnavailable","照片已删除或不在授权范围内"))); return }
    guard let resource = PHAssetResource.assetResources(for:asset).first(where: { PhotoPolicy.editable($0.originalFilename) }) else {
      completion(.failure(nativeError("unsupportedFormat","暗房仅支持 JPEG 照片"))); return
    }
    let options = PHAssetResourceRequestOptions(); options.isNetworkAccessAllowed = false
    let lock = NSLock(); var bytes = Data()
    PHAssetResourceManager.default().requestData(for:resource,options:options,dataReceivedHandler: { chunk in
      lock.lock(); bytes.append(chunk); lock.unlock()
    },completionHandler: { error in
      if error != nil { onMain(completion,.failure(nativeError("photoUnavailable","请先在系统照片中下载原图，再重试"))) }
      else { lock.lock(); let result = bytes; lock.unlock(); onMain(completion,.success(result)) }
    })
  }
  func readExif(ids: [Int64], completion: @escaping (Result<[NativeExifSummary], Error>) -> Void) {
    var results: [NativeExifSummary] = []
    func next(_ index: Int) {
      guard index < ids.count else { completion(.success(results)); return }
      let id = ids[index]
      self.data(id) { result in
        switch result {
        case .failure: next(index+1) // A cloud-only or revoked item must not abort the whole library.
        case .success(let data):
          guard let source = CGImageSourceCreateWithData(data as CFData,nil), let props = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any] else { next(index+1); return }
          let exif = props[kCGImagePropertyExifDictionary as String] as? [String:Any] ?? [:]
          let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String:Any] ?? [:]
          func number(_ key: CFString) -> Double? { (exif[key as String] as? NSNumber)?.doubleValue }
          let iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.int64Value
          results.append(NativeExifSummary(id:id,width:(props[kCGImagePropertyPixelWidth as String] as? NSNumber)?.int64Value ?? 0,height:(props[kCGImagePropertyPixelHeight as String] as? NSNumber)?.int64Value ?? 0,orientation:(props[kCGImagePropertyOrientation as String] as? NSNumber)?.int64Value ?? 1,make:tiff[kCGImagePropertyTIFFMake as String] as? String,model:tiff[kCGImagePropertyTIFFModel as String] as? String,fNumber:number(kCGImagePropertyExifFNumber),exposureTime:number(kCGImagePropertyExifExposureTime),iso:iso,focal35:number(kCGImagePropertyExifFocalLenIn35mmFilm).map { Int64($0) },focal:number(kCGImagePropertyExifFocalLength),takenAt:exif[kCGImagePropertyExifDateTimeOriginal as String] as? String,hasGps:props[kCGImagePropertyGPSDictionary as String] != nil))
          next(index+1)
        }
      }
    }
    next(0)
  }
  func thumbnail(id: Int64, edge: Int64, completion: @escaping (Result<FlutterStandardTypedData?, Error>) -> Void) {
    guard let asset = asset(id) else { completion(.failure(nativeError("photoUnavailable","照片不可用"))); return }
    let options = PHImageRequestOptions(); options.deliveryMode = .highQualityFormat; options.isNetworkAccessAllowed = false
    let size = CGFloat(min(max(edge,32),2048))
    PHImageManager.default().requestImage(for:asset,targetSize:CGSize(width:size,height:size),contentMode:.aspectFit,options:options) { image,info in
      if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
      onMain(completion,.success(image?.jpegData(compressionQuality:0.85).map { FlutterStandardTypedData(bytes:$0) }))
    }
  }
  func openReadFd(id: Int64, completion: @escaping (Result<Int64, Error>) -> Void) {
    data(id) { result in
      do {
        let bytes = try result.get()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try bytes.write(to:url,options:.atomic)
        let fd = Darwin.open(url.path,O_RDONLY)
        try? FileManager.default.removeItem(at:url)
        guard fd >= 0 else { throw nativeError("photoReadFailed","无法打开照片") }
        completion(.success(Int64(fd)))
      } catch { completion(.failure(error)) }
    }
  }
  static func savePhoto(_ url: URL, name: String, completion: @escaping (Result<String, Error>) -> Void) {
    PHPhotoLibrary.requestAuthorization(for:.addOnly) { status in
      guard status == .authorized || status == .limited else { onMain(completion,.failure(nativeError("permissionDenied","请允许保存照片"))); return }
      var identifier: String?
      PHPhotoLibrary.shared().performChanges({
        let request = PHAssetCreationRequest.forAsset()
        let options = PHAssetResourceCreationOptions(); options.originalFilename = name; options.shouldMoveFile = false
        request.addResource(with:.photo,fileURL:url,options:options)
        identifier = request.placeholderForCreatedAsset?.localIdentifier
      }) { success,error in
        if success, let identifier = identifier { onMain(completion,.success("ph://"+identifier)) }
        else { onMain(completion,.failure(error ?? nativeError("publishFailed","保存照片失败"))) }
      }
    }
  }
  func publishExport(tempPath: String, sourceId: Int64, displayName: String, keepGps: Bool, width: Int64, height: Int64, completion: @escaping (Result<String, Error>) -> Void) {
    // The exported JPEG is a newly rendered file. Carry only explicit shooting facts.
    data(sourceId) { result in
      do {
        let original = try result.get()
        let input = URL(fileURLWithPath:tempPath)
        let tempRoot = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path+"/"
        let cacheRoot = (NSSearchPathForDirectoriesInDomains(.cachesDirectory,.userDomainMask,true).first ?? "")+"/"
        let resolved = input.resolvingSymlinksInPath().path
        guard resolved.hasPrefix(tempRoot) || resolved.hasPrefix(cacheRoot), width > 0, height > 0 else { throw nativeError("invalidExport","导出路径或尺寸无效") }
        guard let originalSource = CGImageSourceCreateWithData(original as CFData,nil),
              let source = CGImageSourceCreateWithURL(input as CFURL,nil) else { throw nativeError("invalidPhoto","无法读取导出照片") }
        let originalProps = CGImageSourceCopyPropertiesAtIndex(originalSource,0,nil) as? [String:Any] ?? [:]
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".jpg")
        defer { try? FileManager.default.removeItem(at:output) }
        guard let dest = CGImageDestinationCreateWithURL(output as CFURL,"public.jpeg" as CFString,1,nil) else { throw nativeError("exportFailed","无法创建 JPEG") }
        let exif = originalProps[kCGImagePropertyExifDictionary as String] as? [String:Any] ?? [:]
        let tiff = originalProps[kCGImagePropertyTIFFDictionary as String] as? [String:Any] ?? [:]
        let exifKeys = [kCGImagePropertyExifExposureTime,kCGImagePropertyExifFNumber,kCGImagePropertyExifISOSpeedRatings,kCGImagePropertyExifFocalLength,kCGImagePropertyExifFocalLenIn35mmFilm,kCGImagePropertyExifDateTimeOriginal,kCGImagePropertyExifDateTimeDigitized]
        var keptExif: [String:Any] = [:]; for key in exifKeys { keptExif[key as String] = exif[key as String] }
        keptExif[kCGImagePropertyExifPixelXDimension as String] = width; keptExif[kCGImagePropertyExifPixelYDimension as String] = height
        var props: [String:Any] = [kCGImagePropertyOrientation as String:1,kCGImagePropertyExifDictionary as String:keptExif,kCGImagePropertyTIFFDictionary as String:[kCGImagePropertyTIFFMake as String:tiff[kCGImagePropertyTIFFMake as String] ?? "",kCGImagePropertyTIFFModel as String:tiff[kCGImagePropertyTIFFModel as String] ?? "",kCGImagePropertyTIFFSoftware as String:"GRemote"]]
        if keepGps && self.location.allowed { props[kCGImagePropertyGPSDictionary as String] = originalProps[kCGImagePropertyGPSDictionary as String] }
        CGImageDestinationAddImageFromSource(dest,source,0,props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw nativeError("exportFailed","JPEG 写入失败") }
        // savePhoto is asynchronous; keep the file until Photos finishes copying it.
        let savedCopy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".jpg")
        try FileManager.default.copyItem(at:output,to:savedCopy)
        Self.savePhoto(savedCopy,name:displayName) { result in try? FileManager.default.removeItem(at:savedCopy); completion(result) }
      } catch { completion(.failure(error)) }
    }
  }
  func share(uri: String) throws {
    guard uri.hasPrefix("ph://"), let controller = controller,
          let asset = PHAsset.fetchAssets(withLocalIdentifiers:[String(uri.dropFirst(5))],options:nil).firstObject else { throw nativeError("photoUnavailable","照片不可用") }
    let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = false; options.version = .original
    PHImageManager.default().requestImageDataAndOrientation(for:asset,options:options) { data,_,_,_ in
      guard let data = data else { return }
      DispatchQueue.main.async {
        let sheet = UIActivityViewController(activityItems:[data],applicationActivities:nil)
        sheet.popoverPresentationController?.sourceView = controller.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x:controller.view.bounds.midX,y:controller.view.bounds.midY,width:1,height:1)
        controller.present(sheet,animated:true)
      }
    }
  }
}
