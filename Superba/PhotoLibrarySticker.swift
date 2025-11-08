import Photos
import PhotosUI
import Vision
import CoreImage
import UIKit
import AVFoundation
import ImageIO
import MobileCoreServices
import SceneKit

class PhotoLibraryStickerService {
    static let shared = PhotoLibraryStickerService()
    private init() {}
    
    // MARK: - Main Photo Processing Methods
    
    /// Load UIImage from PHAsset local identifier
    func loadUIImage(from localIdentifier: String) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else {
            print("❌ Asset not found for identifier: \(localIdentifier)")
            return nil
        }
        
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
    
    /// Process photo from picker - handles both regular photos and Live Photos
    func processPhotoFromPicker(asset: PHAsset) async -> (UIImage?, URL?) {
        print("🔍 Processing photo from picker...")
        
        // Check if it's a Live Photo
        if asset.mediaSubtypes.contains(.photoLive) {
            print("📸 Detected Live Photo - processing as animated sticker")
            let result = await processLivePhotoAsAnimatedSticker(asset: asset)
            return result
        } else {
            print("📷 Regular photo - processing with subject lifting")
            if let image = await processRegularPhoto(asset: asset) {
                return (image, nil)
            }
            return (nil, nil)
        }
    }
    
    /// Process regular photo with subject lifting
    private func processRegularPhoto(asset: PHAsset) async -> UIImage? {
        guard let image = await loadUIImage(from: asset.localIdentifier) else {
            return nil
        }
        
        let normalized = normalizeOrientation(of: image)
        return await liftSubject(from: normalized) ?? normalized
    }
    
    /// Process Live Photo and create animated GIF with subject lifting
    func processLivePhotoAsAnimatedSticker(asset: PHAsset) async -> (UIImage?, URL?) {
        return await withCheckedContinuation { continuation in
            let resources = PHAssetResource.assetResources(for: asset)
            guard let videoResource = resources.first(where: { $0.type == .pairedVideo }) else {
                print("❌ No video resource found in Live Photo")
                continuation.resume(returning: (nil, nil))
                return
            }
            
            // Extract all frames and create animated GIF with subject lifting
            extractFramesAndCreateAnimatedGIFWithURL(from: videoResource, asset: asset) { previewImage, gifURL in
                continuation.resume(returning: (previewImage, gifURL))
            }
        }
    }
    
    /// Export paired MOV from asset identifier
    func exportPairedMOV(from assetIdentifier: String) async -> URL? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = assets.firstObject else { 
            print("❌ Could not fetch PHAsset for Live Photo export")
            return nil 
        }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let videoRes = resources.first(where: { $0.type == .pairedVideo || $0.type == .video }) else { 
            print("❌ No paired video resource found in Live Photo")
            return nil 
        }

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("live-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: tmp)

        let opts = PHAssetResourceRequestOptions()
        opts.isNetworkAccessAllowed = true

        print("🎬 Exporting Live Photo video to: \(tmp.lastPathComponent)")
        
        return await withCheckedContinuation { cont in
            PHAssetResourceManager.default().writeData(for: videoRes, toFile: tmp, options: opts) { err in
                if let err = err {
                    print("❌ Failed to export Live Photo video: \(err.localizedDescription)")
                    cont.resume(returning: nil)
                } else {
                    print("✅ Successfully exported Live Photo video")
                    cont.resume(returning: tmp)
                }
            }
        }
    }
    
    /// Process Live Photo video URL to create animated GIF with subject lifting
    func processLivePhotoVideoURL(videoURL: URL) async -> (UIImage?, URL?) {
        print("🎬 Processing Live Photo video URL: \(videoURL.lastPathComponent)")
        
        // Extract frames from the video and apply subject lifting
        let frames = await extractFramesWithSubjectLifting(from: videoURL)
        
        guard !frames.isEmpty else {
            print("❌ No frames extracted from Live Photo video")
            return (nil, nil)
        }
        
        print("🎭 Extracted \(frames.count) frames with subject lifting")
        
        // Create animated GIF from the processed frames
        return await withCheckedContinuation { continuation in
            createAnimatedGIF(with: frames) { gifURL in
                continuation.resume(returning: (frames.first, gifURL))
            }
        }
    }
    
    /// Extract frames from video URL with subject lifting applied
    private func extractFramesWithSubjectLifting(from videoURL: URL) async -> [UIImage] {
        let avAsset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: avAsset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        let duration = CMTimeGetSeconds(avAsset.duration)
        let frameRate: Double = 10 // 10 FPS
        let frameCount = Int(duration * frameRate)
        
        var processedFrames: [UIImage] = []
        
        print("🎬 Extracting \(frameCount) frames at \(frameRate) FPS from Live Photo video")
        
        for i in 0..<frameCount {
            let time = CMTime(seconds: Double(i) / frameRate, preferredTimescale: 600)
            
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let uiImage = UIImage(cgImage: cgImage)
                
                // Apply subject lifting to each frame
                if let liftedImage = await liftSubject(from: uiImage) {
                    processedFrames.append(liftedImage)
                } else {
                    // If subject lifting fails, use the original frame
                    processedFrames.append(uiImage)
                }
            } catch {
                print("⚠️ Failed to extract frame at time \(CMTimeGetSeconds(time)): \(error.localizedDescription)")
            }
        }
        
        print("✅ Successfully processed \(processedFrames.count) frames with subject lifting")
        return processedFrames
    }
    
    /// Process Live Photo directly from PHLivePhoto object when asset identifier is not available
    func processLivePhotoDirectly(livePhoto: PHLivePhoto) async -> (UIImage?, URL?) {
        print("🔍 Processing PHLivePhoto directly...")
        print("❌ Cannot extract video from PHLivePhoto without asset identifier")
        print("💡 Live Photo video extraction requires PHAsset access through itemIdentifier")
        
        // We cannot extract the video component from PHLivePhoto without the asset identifier
        // The video extraction requires PHAssetResourceManager which needs PHAsset
        return (nil, nil)
    }
    
    /// Process selfie video into animated GIF sticker with subject lifting
    func processSelfieVideoAsAnimatedSticker(videoURL: URL) async -> URL? {
        print("🤳 Processing selfie video: \(videoURL)")
        
        // Extract frames from selfie video with subject lifting
        let frames = await extractFramesWithSubjectLifting(from: videoURL)
        
        guard !frames.isEmpty else {
            print("❌ No frames extracted from selfie video")
            return nil
        }
        
        print("🎬 Extracted \(frames.count) frames from selfie video")
        
        // Apply rounded corners directly into the GIF frames so AR plane doesn't need masking
        // Approximate a 35pt continuous corner look by using 35px at 1x scale; since frames are pixel-based,
        // this bakes the rounding into the asset itself.
        let cornerRadiusPixels: CGFloat = 35
        let roundedFrames = frames.map { self.imageWithRoundedCorners($0, radius: cornerRadiusPixels) }

        // Create animated GIF from processed frames
        return await withCheckedContinuation { continuation in
            createAnimatedGIF(with: roundedFrames) { gifURL in
                continuation.resume(returning: gifURL)
            }
        }
    }

    // MARK: - Image rounding helper
    private func imageWithRoundedCorners(_ image: UIImage, radius: CGFloat) -> UIImage {
        let size = image.size
        let scale = image.scale
        let rect = CGRect(origin: .zero, size: size)
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        // Use standard rounded path; visually close to continuous in rasterized output
        UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
        image.draw(in: rect)
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
    
    // MARK: - Live Photo Processing
    
    private func extractFramesAndCreateAnimatedGIFWithURL(from videoResource: PHAssetResource, asset: PHAsset, completion: @escaping (UIImage?, URL?) -> Void) {
        let tempDir = NSTemporaryDirectory()
        let videoFileName = UUID().uuidString + ".mov"
        let videoURL = URL(fileURLWithPath: (tempDir as NSString).appendingPathComponent(videoFileName))
        
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        
        PHAssetResourceManager.default().writeData(for: videoResource, toFile: videoURL, options: options) { error in
            if let error = error {
                print("❌ Failed to write video file: \(error.localizedDescription)")
                completion(nil, nil)
                return
            }
            
            print("🎬 Starting animated GIF creation from Live Photo...")
            
            // Extract frames and create animated GIF
            self.extractFramesAndRemoveBackground(from: videoURL, asset: asset) { frames in
                guard !frames.isEmpty else {
                    print("❌ No frames extracted from Live Photo")
                    completion(nil, nil)
                    return
                }
                
                print("🎭 Extracted \(frames.count) frames with subject lifting")
                
                // Create animated GIF from frames
                self.createAnimatedGIF(with: frames) { gifURL in
                    if let gifURL = gifURL {
                        // Load the GIF as a UIImage (first frame for preview)
                        if let gifData = try? Data(contentsOf: gifURL),
                           let firstFrameImage = UIImage(data: gifData) {
                            print("✅ Animated GIF created successfully for Live Photo")
                            // Return both preview image and GIF URL (don't clean up yet)
                            completion(firstFrameImage, gifURL)
                        } else {
                            print("❌ Failed to load created GIF")
                            completion(nil, nil)
                        }
                    } else {
                        print("❌ Failed to create animated GIF")
                        completion(nil, nil)
                    }
                }
                
                // Clean up temp video file
                try? FileManager.default.removeItem(at: videoURL)
            }
        }
    }
    
    private func extractFramesAndRemoveBackground(from videoURL: URL, asset: PHAsset, completion: @escaping ([UIImage]) -> Void) {
        var frames: [UIImage] = []
        let avAsset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: avAsset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        let duration = CMTimeGetSeconds(avAsset.duration)
        let frameRate = 10.0 // 10 frames per second
        let totalFrames = Int(duration * frameRate)
        
        print("🎬 Extracting \(totalFrames) frames from Live Photo (duration: \(duration)s)")
        
        // Get original orientation to maintain consistency
        let originalOrientation = getOrientationFromPHAsset(asset)
        
        let dispatchGroup = DispatchGroup()
        let frameQueue = DispatchQueue(label: "frame.processing", qos: .userInitiated)
        var processedFrames: [(index: Int, image: UIImage)] = []
        let lock = NSLock()
        
        for i in 0..<totalFrames {
            dispatchGroup.enter()
            frameQueue.async {
                let time = CMTime(seconds: Double(i) / frameRate, preferredTimescale: 600)
                
                do {
                    let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                    let ciImage = CIImage(cgImage: cgImage)
                    
                    // Apply subject lifting with proper orientation handling
                    if let liftedImage = self.liftSubjectFromCIImage(ciImage) {
                        // Ensure the lifted image maintains the original orientation with .up facing north
                        let orientedImage = self.ensureProperOrientation(liftedImage, originalOrientation: originalOrientation)
                        
                        lock.lock()
                        processedFrames.append((index: i, image: orientedImage))
                        lock.unlock()
                    }
                } catch {
                    print("⚠️ Error generating frame \(i): \(error)")
                }
                
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            // Sort frames by index to maintain correct order
            let sortedFrames = processedFrames.sorted { $0.index < $1.index }.map { $0.image }
            print("✅ Successfully processed \(sortedFrames.count)/\(totalFrames) frames")
            completion(sortedFrames)
        }
    }
    
    private func createAnimatedGIF(with frames: [UIImage], completion: @escaping (URL?) -> Void) {
        guard !frames.isEmpty else {
            completion(nil)
            return
        }
        
        let fileName = UUID().uuidString + ".gif"
        let tempDir = NSTemporaryDirectory()
        let filePath = (tempDir as NSString).appendingPathComponent(fileName)
        let fileURL = URL(fileURLWithPath: filePath)
        
        guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, kUTTypeGIF, frames.count, nil) else {
            print("❌ Unable to create GIF destination")
            completion(nil)
            return
        }
        
        let frameDuration = 0.1 // Each frame duration: 0.1 seconds (10 FPS)
        
        // Set GIF properties for infinite loop
        let gifProperties = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0 // 0 = infinite loop
            ]
        ] as CFDictionary
        
        CGImageDestinationSetProperties(destination, gifProperties)
        
        // Add each frame to the GIF
        for frame in frames {
            if let cgImage = frame.cgImage {
                let frameProperties = [
                    kCGImagePropertyGIFDictionary as String: [
                        kCGImagePropertyGIFUnclampedDelayTime as String: frameDuration
                    ]
                ] as CFDictionary
                CGImageDestinationAddImage(destination, cgImage, frameProperties)
            }
        }
        
        if CGImageDestinationFinalize(destination) {
            print("🎉 Animated GIF created successfully at: \(filePath)")
            completion(fileURL)
        } else {
            print("❌ Failed to finalize GIF creation")
            completion(nil)
        }
    }
    
    // MARK: - Subject Lifting (Adapted from your code)
    
    /// Lift subject from UIImage using Vision framework
    func liftSubject(from image: UIImage) async -> UIImage? {
        let normalized = normalizeOrientation(of: image)
        guard let cgImage = normalized.cgImage else {
            print("❌ Failed to get CGImage from UIImage")
            return nil
        }
        
        print("🔍 Starting subject lifting process...")
        let inputCI = CIImage(cgImage: cgImage)
        
        // Get original orientation for proper handling
        let originalOrientation = cgImagePropertyOrientation(from: image.imageOrientation)
        
        // Try your improved subject lifting method
        if let liftedImage = liftSubjectFromCIImage(inputCI) {
            // Ensure proper orientation with .up facing north
            let orientedImage = ensureProperOrientation(liftedImage, originalOrientation: originalOrientation)
            print("✅ Subject lifting successful with proper orientation!")
            return orientedImage
        }
        
        // Fallback to original image with proper orientation
        print("⚠️ Subject lifting failed, using original image with proper orientation")
        let orientedOriginal = ensureProperOrientation(normalized, originalOrientation: originalOrientation)
        return orientedOriginal
    }
    
    /// Convert UIImage.Orientation to CGImagePropertyOrientation
    private func cgImagePropertyOrientation(from uiOrientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch uiOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
    
    /// Lift subject from CIImage using your Vision framework approach
    private func liftSubjectFromCIImage(_ image: CIImage) -> UIImage? {
        guard #available(iOS 17.0, *) else {
            print("❌ VNGenerateForegroundInstanceMaskRequest requires iOS 17.0+")
            return nil
        }
        
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            print("❌ Error performing Vision request: \(error)")
            return nil
        }
        
        guard let result = request.results?.first as? VNInstanceMaskObservation else {
            print("❌ No subject mask results found")
            return nil
        }
        
        do {
            // Generate mask with original size (not cropped)
            let mask = try result.generateMaskedImage(ofInstances: [1], from: handler, croppedToInstancesExtent: false)
            let maskCI = CIImage(cvPixelBuffer: mask)
            
            print("🎭 Subject mask dimensions: \(maskCI.extent.width) x \(maskCI.extent.height)")
            print("📏 Original image dimensions: \(image.extent.width) x \(image.extent.height)")
            
            return makeUIImageFromMask(maskCI)
        } catch {
            print("❌ Error generating subject mask: \(error)")
            return nil
        }
    }
    
    /// Convert mask CIImage to UIImage (8-bit sRGB, keep alpha) without downscaling
    private func makeUIImageFromMask(_ mask: CIImage) -> UIImage {
        let scaledCI: CIImage = mask

        // 3) Render to 8-bit sRGB with alpha
        let ciContext = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        ])
        guard let cgImage = ciContext.createCGImage(scaledCI, from: scaledCI.extent) else {
            print("❌ Failed to create CGImage from CIImage for mask")
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }

        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let finalImage = renderer.image { _ in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
        }
        print("🎉 Final lifted UIImage size: \(finalImage.size.width) x \(finalImage.size.height)")

        return finalImage
    }

    /// PNG compression using ImageIO (lossless). Level parameter is currently ignored by platform.
    func pngCompressedData(from image: UIImage, level: Int = 9) -> Data? {
        guard let cg = image.cgImage else { return image.pngData() }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, kUTTypePNG, 1, nil) else { return image.pngData() }
        // Note: Some SDKs do not expose a tunable PNG compression level key.
        // Use default PNG properties; system will apply lossless compression.
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return image.pngData() }
        return data as Data
    }
    
    // MARK: - Image Orientation Helpers (From your code)
    
    /// Normalize UIImage orientation to .up by redraw - FIXED to preserve logical dimensions
    private func normalizeOrientation(of image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        
        guard let cgImage = image.cgImage else { return image }
        
        // Use the LOGICAL image size (respects orientation) not the raw CGImage dimensions
        let logicalWidth = Int(image.size.width * image.scale)
        let logicalHeight = Int(image.size.height * image.scale)
        
        print("🔍 Original image - Logical size: \(image.size), Pixel size: \(logicalWidth)x\(logicalHeight), CGImage size: \(cgImage.width)x\(cgImage.height), Orientation: \(image.imageOrientation.rawValue)")
        
        // Create a context with the LOGICAL dimensions (preserves portrait/landscape)
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = cgImage.bitmapInfo.rawValue
        
        guard let context = CGContext(
            data: nil,
            width: logicalWidth,
            height: logicalHeight,
            bitsPerComponent: cgImage.bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            print("❌ Failed to create CGContext for orientation normalization")
            return image
        }
        
        // Apply the correct transformation based on the original orientation
        switch image.imageOrientation {
        case .down, .downMirrored:
            context.translateBy(x: CGFloat(logicalWidth), y: CGFloat(logicalHeight))
            context.rotate(by: .pi)
        case .left, .leftMirrored:
            context.translateBy(x: CGFloat(logicalWidth), y: 0)
            context.rotate(by: .pi / 2)
        case .right, .rightMirrored:
            context.translateBy(x: 0, y: CGFloat(logicalHeight))
            context.rotate(by: -.pi / 2)
        default:
            break
        }
        
        // Handle mirroring
        if [.upMirrored, .downMirrored, .leftMirrored, .rightMirrored].contains(image.imageOrientation) {
            context.translateBy(x: CGFloat(logicalWidth), y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        
        // Draw the image with proper orientation transformation
        let drawRect: CGRect
        if [.left, .leftMirrored, .right, .rightMirrored].contains(image.imageOrientation) {
            // For rotated images, swap width/height in draw rect
            drawRect = CGRect(x: 0, y: 0, width: logicalHeight, height: logicalWidth)
        } else {
            drawRect = CGRect(x: 0, y: 0, width: logicalWidth, height: logicalHeight)
        }
        
        context.draw(cgImage, in: drawRect)
        
        guard let normalizedCGImage = context.makeImage() else {
            print("❌ Failed to create normalized CGImage")
            return image
        }
        
        // Create UIImage with .up orientation and original scale
        let normalizedImage = UIImage(cgImage: normalizedCGImage, scale: image.scale, orientation: .up)
        print("✅ Normalized image size: \(normalizedImage.size) (preserved aspect ratio)")
        
        return normalizedImage
    }
    
    /// Extract orientation from PHAsset (adapted from your code)
    private func getOrientationFromPHAsset(_ asset: PHAsset) -> CGImagePropertyOrientation {
        var orientation: CGImagePropertyOrientation = .up
        let semaphore = DispatchSemaphore(value: 0)
        
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { (_, _, imageOrientation, _) in
            // Convert UIImage.Orientation to CGImagePropertyOrientation
            switch imageOrientation {
            case .up: orientation = .up
            case .down: orientation = .down
            case .left: orientation = .left
            case .right: orientation = .right
            case .upMirrored: orientation = .upMirrored
            case .downMirrored: orientation = .downMirrored
            case .leftMirrored: orientation = .leftMirrored
            case .rightMirrored: orientation = .rightMirrored
            @unknown default: orientation = .up
            }
            semaphore.signal()
        }
        
        // Wait max 3 seconds
        _ = semaphore.wait(timeout: .now() + 3.0)
        return orientation
    }
    
    /// Apply orientation to UIImage (from your code)
    private func applyOrientationToUIImage(_ image: UIImage, orientation: CGImagePropertyOrientation) -> UIImage? {
        guard orientation != .up else {
            return image
        }
        
        guard let cgImage = image.cgImage else {
            return image
        }
        
        let ciImage = CIImage(cgImage: cgImage)
        let orientedCIImage = ciImage.oriented(orientation)
        
        let context = CIContext()
        guard let orientedCGImage = context.createCGImage(orientedCIImage, from: orientedCIImage.extent) else {
            return image // Return original if orientation fails
        }
        
        return UIImage(cgImage: orientedCGImage)
    }
    
    /// Ensure proper orientation with .up facing north (fixes orientation issues)
    private func ensureProperOrientation(_ image: UIImage, originalOrientation: CGImagePropertyOrientation) -> UIImage {
        // The lifted image from Vision framework should maintain the original photo's orientation
        // but we need to ensure .up always faces north in the AR scene
        
        guard let cgImage = image.cgImage else {
            print("⚠️ Could not get CGImage for orientation correction")
            return image
        }
        
        // Create a properly oriented image that maintains the original photo's spatial relationship
        // but ensures .up faces north in AR space
        let ciImage = CIImage(cgImage: cgImage)
        
        // Apply the original orientation to maintain the subject's correct spatial relationship
        let orientedCIImage: CIImage
        switch originalOrientation {
        case .up:
            orientedCIImage = ciImage
        case .down:
            orientedCIImage = ciImage.oriented(.down)
        case .left:
            orientedCIImage = ciImage.oriented(.left)
        case .right:
            orientedCIImage = ciImage.oriented(.right)
        case .upMirrored:
            orientedCIImage = ciImage.oriented(.upMirrored)
        case .downMirrored:
            orientedCIImage = ciImage.oriented(.downMirrored)
        case .leftMirrored:
            orientedCIImage = ciImage.oriented(.leftMirrored)
        case .rightMirrored:
            orientedCIImage = ciImage.oriented(.rightMirrored)
        }
        
        let context = CIContext()
        guard let orientedCGImage = context.createCGImage(orientedCIImage, from: orientedCIImage.extent) else {
            print("⚠️ Failed to create oriented CGImage, using original")
            return image
        }
        
        // Force the final UIImage to have .up orientation for AR consistency
        let finalImage = UIImage(cgImage: orientedCGImage, scale: 1.0, orientation: .up)
        
        print("🧭 Applied orientation correction: \(originalOrientation) → .up for AR")
        return finalImage
    }
    
    // MARK: - Public Convenience Methods
    
    /// Public convenience: normalize image externally
    func normalizeForExternal(_ image: UIImage) -> UIImage {
        return normalizeOrientation(of: image)
    }
    
    /// Material transform to render upright in SceneKit
    func materialTransformForUpright() -> SCNMatrix4 {
        let flipY = SCNMatrix4MakeScale(1, -1, 1)
        let translateY = SCNMatrix4MakeTranslation(0, 1, 0)
        return SCNMatrix4Mult(flipY, translateY)
    }
}