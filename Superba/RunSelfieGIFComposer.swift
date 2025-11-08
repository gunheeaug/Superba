import UIKit
import ImageIO
import UniformTypeIdentifiers

public enum RunSelfieGIFComposer {
    // MARK: - Public API
    // URL 입력을 받아 네트워크로 GIF를 불러온 후 합성하여 임시파일 URL 반환
    public static func generate(from sourceGIFURL: URL) async throws -> URL {
        let (data, _) = try await URLSession.shared.data(from: sourceGIFURL)
        return try generate(from: data)
    }

    // Data 입력을 받아 합성하여 임시파일 URL 반환
    public static func generate(from sourceGIFData: Data) throws -> URL {
        guard let source = CGImageSourceCreateWithData(sourceGIFData as CFData, nil) else {
            throw ComposerError.failedToCreateImageSource
        }
        return try composeAndWrite(from: source)
    }

    // MARK: - Internal Core Logic
    private static func composeAndWrite(from source: CGImageSource) throws -> URL {
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { throw ComposerError.noFrames }

        // 첫 프레임으로 원본 크기 파악
        guard let firstCGImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ComposerError.failedFirstFrame
        }
        let originalWidth = CGFloat(firstCGImage.width)
        let originalHeight = CGFloat(firstCGImage.height)

        // 메모리 절약을 위해 최대 500px 폭으로 스케일
        let maxWidth: CGFloat = 500
        let scale = min(1.0, maxWidth / max(originalWidth, 1))
        let gifWidth = max(originalWidth * scale, 1)
        let gifHeight = max(originalHeight * scale, 1)

        // 캔버스/레이아웃 계산 (runView의 profileGifPulse와 동일한 규칙)
        let diameter = gifWidth
        let circleRadius = diameter / 2
        let leavesWidth = diameter * 1.8
        let leavesHeight = leavesWidth // 정사각 비율
        let circleOffsetY: CGFloat = 2
        let leavesOffsetY = diameter * 0.2
        let canvasWidth = max(diameter, leavesWidth)
        let canvasHeight = gifHeight + leavesOffsetY

        // 출력 경로 및 Destination 생성
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("run-selfie-\(UUID().uuidString).gif")
        guard let destination = CGImageDestinationCreateWithURL(tempURL as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
            throw ComposerError.failedToCreateDestination
        }

        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        // 각 프레임 합성
        for i in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }

            // 프레임 지연시간
            let frameProperties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as Dictionary?
            let gifDict = frameProperties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gifDict?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ??
                        (gifDict?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1

            // 합성 렌더링
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvasWidth, height: canvasHeight))
            let compositeImage = renderer.image { ctx in
                // 1) 파란 원형 배경 (GIF 하단 기준, 소폭 아래 오프셋)
                let circleY = gifHeight - diameter + circleOffsetY
                let circleRect = CGRect(x: (canvasWidth - diameter) / 2, y: circleY, width: diameter, height: diameter)
                ctx.cgContext.setFillColor(UIColor(red: 0x5C/255.0, green: 0xBA/255.0, blue: 0xF2/255.0, alpha: 1.0).cgColor)
                ctx.cgContext.fillEllipse(in: circleRect)

                // 2) 흰색 원형 스트로크
                ctx.cgContext.setStrokeColor(UIColor.white.cgColor)
                ctx.cgContext.setLineWidth(28)
                ctx.cgContext.strokeEllipse(in: circleRect)

                // 3) 셀피 GIF 프레임 (하단 라운드 코너로 클리핑), 상단 정렬
                let gifRect = CGRect(x: (canvasWidth - gifWidth) / 2, y: 0, width: gifWidth, height: gifHeight)
                ctx.cgContext.saveGState()
                let cornerRadius: CGFloat = circleRadius
                let clipPath = UIBezierPath(
                    roundedRect: gifRect,
                    byRoundingCorners: [.bottomLeft, .bottomRight],
                    cornerRadii: CGSize(width: cornerRadius, height: cornerRadius)
                )
                clipPath.addClip()
                UIImage(cgImage: cgImage).draw(in: gifRect)
                ctx.cgContext.restoreGState()

                // 4) 잎사귀 오버레이 (runselfieleaves)
                if let leavesImage = UIImage(named: "runselfieleaves") {
                    let circleCenterY = circleY + diameter / 2
                    let leavesY = circleCenterY - leavesHeight / 2 + leavesOffsetY
                    let leavesRect = CGRect(x: (canvasWidth - leavesWidth) / 2, y: leavesY, width: leavesWidth, height: leavesHeight)
                    leavesImage.draw(in: leavesRect)
                }
            }

            guard let compositeCGImage = compositeImage.cgImage else { continue }
            let frameProps: [String: Any] = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFDelayTime as String: delay
                ]
            ]
            CGImageDestinationAddImage(destination, compositeCGImage, frameProps as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else { throw ComposerError.finalizeFailed }
        return tempURL
    }

    // MARK: - Errors
    public enum ComposerError: Error {
        case failedToCreateImageSource
        case noFrames
        case failedFirstFrame
        case failedToCreateDestination
        case finalizeFailed
    }
}