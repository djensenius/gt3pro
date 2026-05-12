#if os(iOS)
import Foundation
import UIKit
import os

private let logger = Logger(subsystem: "org.davidjensenius.GT3Companion", category: "API")

/// API client for FluxHaus GT3 endpoints.
/// Note: Authentication (OIDC via AuthManager) will be integrated in a future PR.
/// Currently sends unauthenticated requests.
actor GT3APIClient {
    private let baseURL = GT3APIConfig.baseURL
    private let session = URLSession(configuration: .default)

    /// Upload a batch of telemetry samples.
    func uploadTelemetry(_ samples: [TelemetrySample]) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(["samples": samples])
        try await post(path: "/gt3/telemetry", body: body)
        logger.info("Uploaded \(samples.count) telemetry samples")
    }

    /// Upload a completed ride.
    func uploadRide(_ ride: RideLog) async throws -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(ride)
        let data = try await post(path: "/gt3/ride", body: body)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let rideId = json["id"] as? String {
            logger.info("Uploaded ride: \(rideId)")
            return rideId
        }
        return nil
    }

    /// Upload a ride photo attachment.
    ///
    /// Server endpoint contract: `POST /gt3/rides/:rideId/photos`
    /// accepts this JSON payload and returns `{ "id": "<photoId>" }`.
    /// Payload fields:
    /// - `capturedAt`: ISO8601 capture timestamp
    /// - `latitude` / `longitude`: optional geotag used for route placement
    /// - `mimeType`: currently `image/jpeg`
    /// - `imageData`: base64 string in JSON (Swift `Data` Codable encoding)
    func uploadRidePhoto(rideId: String, payload: RidePhotoUploadPayload) async throws -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(payload)
        let data = try await post(path: "/gt3/rides/\(rideId)/photos", body: body)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let photoId = json["id"] as? String {
            logger.info("Uploaded ride photo: \(photoId)")
            return photoId
        }
        return nil
    }

    /// Upload a scooter snapshot.
    func uploadSnapshot(_ snapshot: [String: String]) async throws {
        let body = try JSONSerialization.data(withJSONObject: snapshot)
        try await post(path: "/gt3/snapshot", body: body)
        logger.info("Uploaded snapshot")
    }

    /// Fetch ride list.
    func fetchRides(page: Int = 1, limit: Int = 20) async throws -> Data {
        try await get(path: "/gt3/rides?page=\(page)&limit=\(limit)")
    }

    /// Fetch ride detail.
    func fetchRide(rideId: String) async throws -> Data {
        try await get(path: "/gt3/rides/\(rideId)")
    }

    /// Retry a previously failed POST with raw payload.
    func retryPost(path: String, body: Data) async throws -> Data {
        try await post(path: path, body: body)
    }

    /// Request the server to send a push-to-start APNs notification
    /// to create a Live Activity (used on background BLE reconnect).
    /// Request the server to send a push-to-start notification.
    /// Returns `true` if at least one push was sent successfully.
    func requestActivityStart() async throws -> Bool {
        let data = try await post(path: "/gt3/activity/start", body: Data("{}".utf8))
        if let responseStr = String(data: data, encoding: .utf8) {
            logger.info("Push-to-start response: \(responseStr)")
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let success = json["success"] as? Bool {
            return success
        }
        return false
    }

    /// Register a push-to-start token with the server.
    func registerPushToStartToken(_ tokenHex: String) async throws {
        let deviceName = await UIDevice.current.name
        let payload: [String: String] = [
            "pushToStartToken": tokenHex,
            "deviceName": deviceName,
            "bundleId": Bundle.main.bundleIdentifier ?? "org.davidjensenius.GT3Companion"
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        try await post(path: "/push-tokens/device", body: body)
        logger.info("Registered push-to-start token")
    }

    /// Create a shareable link for a ride.
    func createShareLink(rideId: String, expiresIn: ShareExpiry) async throws -> ShareLinkResponse {
        let payload: [String: String] = ["expiresIn": expiresIn.serverValue]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await post(path: "/gt3/rides/\(rideId)/shares", body: body)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(ShareLinkResponse.self, from: data)
        logger.info("Created share link for ride \(rideId), expires: \(expiresIn.serverValue)")
        return response
    }

    /// Build the full shareable URL from a token.
    nonisolated func shareURL(for token: String) -> URL? {
        var components = URLComponents(string: "\(GT3APIConfig.baseURL)/gt3/ride.html")
        components?.queryItems = [URLQueryItem(name: "share", value: token)]
        return components?.url
    }

    // MARK: - Private

    @discardableResult
    private func post(path: String, body: Data) async throws -> Data {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        let valid = await AuthManager.shared.ensureValidToken()
        if !valid {
            let hasToken = AuthManager.shared.authorizationHeader() != nil
            let detail = hasToken ? "proactive refresh failed" : "no access token"
            logger.warning("POST \(path): ensureValidToken=false (\(detail))")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        if let auth = AuthManager.shared.authorizationHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode == 401 {
            return try await retryAfterRefresh(request: request, path: path, method: "POST")
        }

        guard (200...299).contains(statusCode) else {
            let bodyStr = String(data: data.prefix(500), encoding: .utf8) ?? "(non-UTF8)"
            logger.error("POST \(path) failed: \(statusCode) — \(bodyStr)")
            Task { @MainActor in
                DebugLogStore.shared.log(
                    "POST \(path) → \(statusCode): \(bodyStr)",
                    category: "API", level: .error
                )
            }
            throw APIError.httpError(statusCode: statusCode)
        }
        return data
    }

    private func get(path: String) async throws -> Data {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        _ = await AuthManager.shared.ensureValidToken()
        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        if let auth = AuthManager.shared.authorizationHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        if statusCode == 401 {
            return try await retryAfterRefresh(request: request, path: path, method: "GET")
        }

        guard (200...299).contains(statusCode) else {
            let bodyStr = String(data: data.prefix(500), encoding: .utf8) ?? "(non-UTF8)"
            logger.error("GET \(path) failed: \(statusCode) — \(bodyStr)")
            throw APIError.httpError(statusCode: statusCode)
        }
        return data
    }

    /// Retry a request after forcing a token refresh (used on 401).
    private func retryAfterRefresh(request: URLRequest, path: String, method: String) async throws -> Data {
        logger.info("\(method) \(path): got 401, forcing token refresh")
        let refreshed = await AuthManager.shared.refreshTokenIfNeeded()
        guard refreshed else {
            logger.error("\(method) \(path) failed: 401 (token refresh also failed)")
            throw APIError.httpError(statusCode: 401)
        }
        var retryRequest = request
        if let auth = AuthManager.shared.authorizationHeader() {
            retryRequest.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        let (retryData, retryResponse) = try await session.data(for: retryRequest)
        let retryStatus = (retryResponse as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(retryStatus) else {
            logger.error("\(method) \(path) retry failed: \(retryStatus)")
            throw APIError.httpError(statusCode: retryStatus)
        }
        return retryData
    }
}

enum APIError: Error {
    case httpError(statusCode: Int)
    case encodingError
    case invalidURL
}

#endif
