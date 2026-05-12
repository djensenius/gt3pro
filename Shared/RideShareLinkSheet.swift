//
//  RideShareLinkSheet.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import Foundation
import SwiftUI

/// Expiration presets for ride share links.
enum ShareExpiry: String, CaseIterable, Identifiable {
    case oneHour, oneDay, sevenDays, thirtyDays, never

    var id: String { rawValue }

    var serverValue: String {
        switch self {
        case .oneHour:    return "1h"
        case .oneDay:     return "24h"
        case .sevenDays:  return "7d"
        case .thirtyDays: return "30d"
        case .never:      return "never"
        }
    }

    var label: String {
        switch self {
        case .oneHour:    return "1 Hour"
        case .oneDay:     return "24 Hours"
        case .sevenDays:  return "7 Days"
        case .thirtyDays: return "30 Days"
        case .never:      return "Never"
        }
    }

    var description: String {
        switch self {
        case .oneHour:    return "Link expires in 1 hour"
        case .oneDay:     return "Link expires in 24 hours"
        case .sevenDays:  return "Link expires in 7 days"
        case .thirtyDays: return "Link expires in 30 days"
        case .never:      return "Link never expires"
        }
    }
}

/// Server response when creating a share link.
struct ShareLinkResponse: Codable {
    let id: String
    let token: String
    let expiresAt: Date?
    let createdAt: Date
    let status: String
}

actor RideShareService {
    func createShareLink(rideId: String, expiresIn: ShareExpiry) async throws -> URL {
        guard let url = URL(string: "\(GT3APIConfig.baseURL)/gt3/rides/\(rideId)/shares") else {
            throw URLError(.badURL)
        }

        _ = await AuthManager.shared.ensureValidToken()
        let payload = ["expiresIn": expiresIn.serverValue]
        let body = try JSONSerialization.data(withJSONObject: payload)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        if let auth = AuthManager.shared.authorizationHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        return try await sendShareRequest(request)
    }

    nonisolated func shareURL(for token: String) -> URL? {
        var components = URLComponents(string: "\(GT3APIConfig.baseURL)/gt3/ride.html")
        components?.queryItems = [URLQueryItem(name: "share", value: token)]
        return components?.url
    }

    private func sendShareRequest(_ request: URLRequest) async throws -> URL {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                return try await retryAfterRefresh(request: request)
            }
            guard (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
        }
        return try decodeShareURL(from: data)
    }

    private func retryAfterRefresh(request: URLRequest) async throws -> URL {
        let refreshed = await AuthManager.shared.refreshTokenIfNeeded()
        guard refreshed else { throw URLError(.userAuthenticationRequired) }

        var retry = request
        if let auth = AuthManager.shared.authorizationHeader() {
            retry.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: retry)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw URLError(.badServerResponse)
        }
        return try decodeShareURL(from: data)
    }

    private func decodeShareURL(from data: Data) throws -> URL {
        let decoded = try shareDecoder.decode(ShareLinkResponse.self, from: data)
        guard let shareURL = shareURL(for: decoded.token) else {
            throw URLError(.badURL)
        }
        return shareURL
    }
}

private let shareDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

struct RideShareLinkSheet: View {
    let rideId: String
    @Environment(\.dismiss) private var dismiss
    @State private var phase: RideSharePhase = .pickExpiry

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                content.padding()
            }
            .navigationTitle("Share Ride")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 360)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .pickExpiry:
            RideShareExpiryPicker(createLink: createLink)
        case .creating:
            VStack(spacing: Theme.Spacing.large) {
                ProgressView()
                Text("Creating share link...")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        case .shareReady(let url):
            RideShareReadyView(url: url)
        case .error(let message):
            RideShareErrorView(message: message) {
                phase = .pickExpiry
            }
        }
    }

    private func createLink(expiry: ShareExpiry) {
        Task {
            phase = .creating
            do {
                let url = try await RideShareService().createShareLink(rideId: rideId, expiresIn: expiry)
                phase = .shareReady(url)
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }
}

private enum RideSharePhase {
    case pickExpiry
    case creating
    case shareReady(URL)
    case error(String)
}

private struct RideShareExpiryPicker: View {
    let createLink: (ShareExpiry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text("Choose how long the ride link should stay active.")
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
            ForEach(ShareExpiry.allCases) { expiry in
                Button {
                    createLink(expiry)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(expiry.label)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(expiry.description)
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .buttonStyle(.gt3Primary)
            }
        }
    }
}

private struct RideShareReadyView: View {
    let url: URL

    var body: some View {
        VStack(spacing: Theme.Spacing.large) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.success)
            Text("Link Created")
                .font(Theme.Fonts.headerLarge())
            Text(url.absoluteString)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            ShareLink(item: url) {
                Label("Share Link", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.gt3Primary)
        }
    }
}

private struct RideShareErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.large) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.error)
            Text("Failed to Create Link")
                .font(Theme.Fonts.headerLarge())
            Text(message)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again", action: retry)
                .buttonStyle(.gt3Primary)
        }
    }
}
