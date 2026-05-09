#if os(iOS)
import PhotosUI
import UIKit

enum RidePhotoPickerSupport {
    static func loadCompressedImageData(from item: PhotosPickerItem) async -> Data? {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return nil }
        return image.jpegData(compressionQuality: 0.82)
    }
}
#endif
