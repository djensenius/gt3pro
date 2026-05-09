#if os(iOS)
import PhotosUI
import UIKit

enum RidePhotoPickerSupport {
    /// 0.82 keeps route-photo text/details clear while significantly reducing upload/persistence size.
    static let compressionQuality: CGFloat = 0.82

    static func compressJPEGData(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return image.jpegData(compressionQuality: compressionQuality)
    }

    static func loadCompressedImageData(from item: PhotosPickerItem) async -> Data? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return compressJPEGData(data)
    }
}
#endif
