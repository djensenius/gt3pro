#if os(iOS)
import Foundation
import os

private let logger = Logger(subsystem: "io.fluxhaus.GT3Companion", category: "API")

/// API client for FluxHaus GT3 endpoints.
/// Note: Authentication (OIDC via AuthManager) will be integrated in a future PR.
/// Currently sends unauthenticated requests.
actor GT3APIClient {
    private let baseURL = "https://api.fluxhaus.io"
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

    // MARK: - Private

    @discardableResult
    private func post(path: String, body: Data) async throws -> Data {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            logger.error("POST \(path) failed: \(statusCode)")
            throw APIError.httpError(statusCode: statusCode)
        }
        return data
    }

    private func get(path: String) async throws -> Data {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            logger.error("GET \(path) failed: \(statusCode)")
            throw APIError.httpError(statusCode: statusCode)
        }
        return data
    }
}

enum APIError: Error {
    case httpError(statusCode: Int)
    case encodingError
    case invalidURL
}
#endif
