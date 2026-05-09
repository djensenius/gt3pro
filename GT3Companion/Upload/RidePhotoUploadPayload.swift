#if os(iOS)
import Foundation

struct RidePhotoUploadPayload: Codable {
    let capturedAt: Date
    let latitude: Double?
    let longitude: Double?
    let mimeType: String
    let imageData: Data
}
#endif
