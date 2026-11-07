import UIKit

/// UIKitへの変換だけを画面側に置き、画像の検証・縮小はCoreでテストする。
enum ImageDecoder {
    nonisolated static func decode(_ data: Data, maximumPixels: Int = 480, pointSize: Double? = nil) throws -> UIImage {
        let image = try ImageThumbnailDecoder.thumbnail(data, maximumPixels: maximumPixels)
        let scale = pointSize.map { Double(max(image.width, image.height)) / $0 } ?? 1
        return UIImage(cgImage: image, scale: scale, orientation: .up)
    }
}
