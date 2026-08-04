#if os(iOS)
import PhotosUI
import SwiftUI
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

    static func compressJPEGData(from image: UIImage) -> Data? {
        image.jpegData(compressionQuality: compressionQuality)
    }
}

struct RideCameraPicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> StableCameraPickerController {
        let picker = StableCameraPickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: StableCameraPickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImagePicked: (UIImage) -> Void

        init(onImagePicked: @escaping (UIImage) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

final class StableCameraPickerController: UIImagePickerController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .allButUpsideDown
    }

    override var shouldAutorotate: Bool {
        true
    }
}
#endif
