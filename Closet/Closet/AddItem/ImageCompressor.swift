import UIKit

enum ImageCompressor {
    static func compress(_ image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.75) -> Data? {
        resize(image, maxDimension: maxDimension).jpegData(compressionQuality: quality)
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > maxDimension else { return image }
        let scale = maxDimension / longEdge
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
