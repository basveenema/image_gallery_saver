import Flutter
import UIKit
import Photos

public class SwiftImageGallerySaverPlugin: NSObject, FlutterPlugin {
    let errorMessage = "Failed to save, please check whether the permission is enabled"
    
    var result: FlutterResult?;

    public static func register(with registrar: FlutterPluginRegistrar) {
      let channel = FlutterMethodChannel(name: "image_gallery_saver", binaryMessenger: registrar.messenger())
      let instance = SwiftImageGallerySaverPlugin()
      registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      self.result = result
      if call.method == "saveImageToGallery" {
        let arguments = call.arguments as? [String: Any] ?? [String: Any]()
        guard let imageData = (arguments["imageBytes"] as? FlutterStandardTypedData)?.data,
            let image = UIImage(data: imageData),
            let quality = arguments["quality"] as? Int,
			let albumName = arguments["albumName"] as? String,
            let _ = arguments["name"],
            let isReturnImagePath = arguments["isReturnImagePathOfIOS"] as? Bool
            else { return }
        let newImage = image.jpegData(compressionQuality: CGFloat(quality / 100))!
		  saveImage(image: UIImage(data: newImage) ?? image, albumName: albumName, isReturnImagePath: isReturnImagePath)
      } else if (call.method == "saveFileToGallery") {
        guard let arguments = call.arguments as? [String: Any],
              let path = arguments["file"] as? String,
			  let albumName = arguments["albumName"] as? String,
              let _ = arguments["name"],
              let isReturnFilePath = arguments["isReturnPathOfIOS"] as? Bool else { return }
        if (isImageFile(filename: path)) {
			saveImage(url: path, albumName: albumName, isReturnImagePath: isReturnFilePath)
        } else {
            if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(path)) {
                saveVideo(path, albumName: albumName, isReturnImagePath: isReturnFilePath)
            }else{
                self.saveResult(isSuccess:false,error:self.errorMessage)
            }
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    
    func saveVideo(_ path: String, albumName: String?, isReturnImagePath: Bool) {
		if let albumName = albumName {
			if  let assetCollection = fetchAssetCollectionForAlbum(albumName: albumName) {
				self.saveVideoInAlbum(path: path, assetCollection: assetCollection)
			} else {
				if PHPhotoLibrary.authorizationStatus() == PHAuthorizationStatus.authorized {
					self.createAlbum(albumName: albumName) { success in
						if (success) {
							self.saveVideoInAlbum(path: path, assetCollection: self.fetchAssetCollectionForAlbum(albumName: albumName))
						} else {
							self.saveResult(isSuccess: false, error: self.errorMessage)
						}
					}
				} else {
					self.saveResult(isSuccess: false, error: self.errorMessage)
				}
			}
		} else if !isReturnImagePath {
            UISaveVideoAtPathToSavedPhotosAlbum(path, self, #selector(didFinishSavingVideo(videoPath:error:contextInfo:)), nil)
            return
		} else {
			saveVideoInAlbum(path: path)
		}
    }
	
	func saveVideoInAlbum(path: String, assetCollection: PHAssetCollection? = nil) {
		var videoIds: [String] = []
		
		PHPhotoLibrary.shared().performChanges( {
			let req = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: URL.init(fileURLWithPath: path))
			
			if let assetCollection = assetCollection,  let albumChangeRequest = PHAssetCollectionChangeRequest(for: assetCollection), let request = req {
				let enumeration: NSArray = [request]
				albumChangeRequest.addAssets(enumeration)
			}
			
			if let videoId = req?.placeholderForCreatedAsset?.localIdentifier {
				videoIds.append(videoId)
			}
		}, completionHandler: { [unowned self] (success, error) in
			DispatchQueue.main.async {
				if (success && videoIds.count > 0) {
					let assetResult = PHAsset.fetchAssets(withLocalIdentifiers: videoIds, options: nil)
					if (assetResult.count > 0) {
						let videoAsset = assetResult[0]
						PHImageManager().requestAVAsset(forVideo: videoAsset, options: nil) { (avurlAsset, audioMix, info) in
							if let urlStr = (avurlAsset as? AVURLAsset)?.url.absoluteString {
								self.saveResult(isSuccess: true, filePath: urlStr)
							}
						}
					}
				} else {
					self.saveResult(isSuccess: false, error: self.errorMessage)
				}
			}
		})
	}
    
	func saveImageInAlbum(url: String? = nil, image: UIImage? = nil,  assetCollection: PHAssetCollection? = nil) {
		var imageIds: [String] = []
		PHPhotoLibrary.shared().performChanges( {
			
			var request: PHAssetChangeRequest?
			if let image = image {
				request = PHAssetChangeRequest.creationRequestForAsset(from: image)
			} else {
				if let url = url, let fileUrl = URL(string: url) {
					request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileUrl)
				}
			}
			
			if let assetCollection = assetCollection,  let albumChangeRequest = PHAssetCollectionChangeRequest(for: assetCollection), let request = request {
				let enumeration: NSArray = [request]
				albumChangeRequest.addAssets(enumeration)
			}
			
			if let imageId = request?.placeholderForCreatedAsset?.localIdentifier {
				imageIds.append(imageId)
			}
		}, completionHandler: { [unowned self] (success, error) in
			DispatchQueue.main.async {
				if (success && imageIds.count > 0) {
					let assetResult = PHAsset.fetchAssets(withLocalIdentifiers: imageIds, options: nil)
					if (assetResult.count > 0) {
						let imageAsset = assetResult[0]
						let options = PHContentEditingInputRequestOptions()
						options.canHandleAdjustmentData = { (adjustmeta)
							-> Bool in true }
						imageAsset.requestContentEditingInput(with: options) { [unowned self] (contentEditingInput, info) in
							if let urlStr = contentEditingInput?.fullSizeImageURL?.absoluteString {
								self.saveResult(isSuccess: true, filePath: urlStr)
							}
						}
					}
				} else {
					self.saveResult(isSuccess: false, error: self.errorMessage)
				}
			}
		})
    }
	
	func saveImage(url: String? = nil, image: UIImage? = nil, albumName: String?, isReturnImagePath: Bool) {
		if let albumName = albumName {
			if  let assetCollection = fetchAssetCollectionForAlbum(albumName: albumName) {
				self.saveImageInAlbum(url: url, image: image, assetCollection: assetCollection)
			} else {
				if PHPhotoLibrary.authorizationStatus() == PHAuthorizationStatus.authorized {
					self.createAlbum(albumName: albumName) { success in
						if (success) {
							self.saveImageInAlbum(url: url, image: image, assetCollection: self.fetchAssetCollectionForAlbum(albumName: albumName))
						} else {
							self.saveResult(isSuccess: false, error: self.errorMessage)
						}
					}
				} else {
					self.saveResult(isSuccess: false, error: self.errorMessage)
				}
			}
		} else if !isReturnImagePath  {
            if let url = url ,let image = UIImage(contentsOfFile: url) {
                UIImageWriteToSavedPhotosAlbum(image, self, #selector(didFinishSavingImage(image:error:contextInfo:)), nil)
			} else if let image = image {
				UIImageWriteToSavedPhotosAlbum(image, self, #selector(didFinishSavingImage(image:error:contextInfo:)), nil)
			}
            return
        } else {
			saveImageInAlbum(url: url, image: image)
		}
		
    }
	
	func createAlbum(albumName: String, completion: @escaping (Bool) -> Void = { _ in }) {
		PHPhotoLibrary.shared().performChanges({
			PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
		}) { success, error in
			if success {
				completion(true)
			} else {
				self.saveResult(isSuccess: false, error: self.errorMessage)
			}
		}
	}
	
	func fetchAssetCollectionForAlbum(albumName: String) -> PHAssetCollection? {
		let fetchOptions = PHFetchOptions()
		fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
		let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)

		if let _: AnyObject = collection.firstObject {
			return collection.firstObject
		}
		return nil
	}
    
    /// finish saving，if has error，parameters error will not nill
    @objc func didFinishSavingImage(image: UIImage, error: NSError?, contextInfo: UnsafeMutableRawPointer?) {
        saveResult(isSuccess: error == nil, error: error?.description)
    }
    
    @objc func didFinishSavingVideo(videoPath: String, error: NSError?, contextInfo: UnsafeMutableRawPointer?) {
        saveResult(isSuccess: error == nil, error: error?.description)
    }
    
    func saveResult(isSuccess: Bool, error: String? = nil, filePath: String? = nil) {
        var saveResult = SaveResultModel()
        saveResult.isSuccess = error == nil
        saveResult.errorMessage = error?.description
        saveResult.filePath = filePath
        result?(saveResult.toDic())
    }

    func isImageFile(filename: String) -> Bool {
        return filename.hasSuffix(".jpg")
            || filename.hasSuffix(".png")
            || filename.hasSuffix(".jpeg")
            || filename.hasSuffix(".JPEG")
            || filename.hasSuffix(".JPG")
            || filename.hasSuffix(".PNG")
            || filename.hasSuffix(".gif")
            || filename.hasSuffix(".GIF")
            || filename.hasSuffix(".heic")
            || filename.hasSuffix(".HEIC")
    }
}

public struct SaveResultModel: Encodable {
    var isSuccess: Bool!
    var filePath: String?
    var errorMessage: String?
    
    func toDic() -> [String:Any]? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self) else { return nil }
        if (!JSONSerialization.isValidJSONObject(data)) {
            return try? JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String:Any]
        }
        return nil
    }
}
