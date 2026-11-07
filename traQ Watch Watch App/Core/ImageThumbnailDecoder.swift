import Foundation
import ImageIO
import CoreGraphics

/// 圧縮画像を全解像度へ展開せず、必要なサイズの先頭フレームを生成する。
nonisolated enum ImageThumbnailDecoder {
    static func thumbnail(_ data: Data, maximumPixels: Int) throws -> CGImage {
        guard data.count <= ImageHTTPClient.maximumBytes, (1...480).contains(maximumPixels),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192,
              width * height <= 40_000_000 else { throw ImageLoadError.unsupportedImage }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageLoadError.unsupportedImage
        }
        return image
    }
}
