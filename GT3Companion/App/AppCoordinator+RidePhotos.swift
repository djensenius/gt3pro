#if os(iOS)
import SwiftData
import os

private let ridePhotoLogger = Logger(
    subsystem: "org.davidjensenius.GT3Companion",
    category: "RidePhotos"
)

extension AppCoordinator {
    /// Attach a photo while a ride is in progress.
    func addPhotoToCurrentRide(imageData: Data) async -> Bool {
        guard let normalized = normalizedPhotoData(imageData) else { return false }
        guard let rideId = await rideTracker.getCurrentRideId() else { return false }

        let context = PersistenceController.shared.context
        let (lat, lon) = currentPhotoCoordinates()
        let photo = PersistedRidePhoto(
            imageData: normalized,
            latitude: lat,
            longitude: lon,
            pendingRideId: rideId
        )
        context.insert(photo)
        try? context.save()
        ridePhotoLogger.info("Queued photo for active ride \(rideId)")
        return true
    }

    /// Attach a photo to an already persisted ride.
    func addPhoto(imageData: Data, to ride: PersistedRide) async -> Bool {
        guard let normalized = normalizedPhotoData(imageData) else { return false }

        let context = PersistenceController.shared.context
        var (lat, lon) = currentPhotoCoordinates()
        if lat == nil || lon == nil {
            (lat, lon) = fallbackRideCoordinate(for: ride)
        }
        let photo = PersistedRidePhoto(
            imageData: normalized,
            latitude: lat,
            longitude: lon,
            ride: ride
        )
        context.insert(photo)
        try? context.save()

        if ride.uploaded {
            await uploadRidePhoto(photo, for: ride)
        }
        return true
    }

    /// Bind photos captured during an active ride to the persisted ride, then upload if possible.
    func processPendingRidePhotos(for ride: PersistedRide, localRideId: String? = nil) async {
        let context = PersistenceController.shared.context
        let pendingRideId = localRideId ?? ride.rideId
        let pred = #Predicate<PersistedRidePhoto> {
            $0.pendingRideId == pendingRideId && $0.ride == nil
        }
        let descriptor = FetchDescriptor<PersistedRidePhoto>(predicate: pred)
        let pending = (try? context.fetch(descriptor)) ?? []

        if !pending.isEmpty {
            for photo in pending {
                photo.ride = ride
                photo.pendingRideId = nil
            }
            try? context.save()
            ridePhotoLogger.info("Attached \(pending.count) queued photo(s) to ride \(ride.rideId)")
        }

        guard ride.uploaded else { return }
        for photo in ride.sortedPhotos where !photo.uploaded {
            await uploadRidePhoto(photo, for: ride)
        }
    }

    func retryPendingRidePhotoUploads() async {
        let context = PersistenceController.shared.context
        let rides = (try? context.fetch(FetchDescriptor<PersistedRide>())) ?? []
        for ride in rides where ride.uploaded {
            await processPendingRidePhotos(for: ride)
        }
    }

    private func uploadRidePhoto(_ photo: PersistedRidePhoto, for ride: PersistedRide) async {
        let payload = RidePhotoUploadPayload(
            capturedAt: photo.createdAt,
            latitude: photo.latitude,
            longitude: photo.longitude,
            mimeType: photo.mimeType,
            imageData: photo.imageData
        )
        let uploadedId = await uploadQueue.uploadRidePhoto(rideId: ride.rideId, payload: payload)
        photo.uploadAttemptedAt = Date()
        photo.uploaded = uploadedId != nil
        do {
            try PersistenceController.shared.context.save()
        } catch {
            ridePhotoLogger.error("Failed saving photo upload state: \(error.localizedDescription)")
        }
    }

    private func currentPhotoCoordinates() -> (Double?, Double?) {
        if let sample = gpsTracker.latestSample {
            return (sample.latitude, sample.longitude)
        }
        if let last = gpsTracker.lastKnownLocation {
            return (last.coordinate.latitude, last.coordinate.longitude)
        }
        return (nil, nil)
    }

    private func normalizedPhotoData(_ imageData: Data) -> Data? {
        RidePhotoPickerSupport.compressJPEGData(imageData)
    }

    private func fallbackRideCoordinate(for ride: PersistedRide) -> (Double?, Double?) {
        let latestValid = (ride.samples ?? []).reduce(nil as PersistedSample?) { latest, sample in
            guard sample.latitude != nil, sample.longitude != nil else { return latest }
            guard let latest else { return sample }
            return sample.timestamp > latest.timestamp ? sample : latest
        }
        if let match = latestValid {
            return (match.latitude, match.longitude)
        }
        return (nil, nil)
    }
}
#endif
