//
//  ShareRideSheet.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if os(iOS)
import SwiftUI
import UIKit
import os

private let logger = Logger(subsystem: "org.davidjensenius.GT3Companion", category: "Share")

/// A sheet that lets the user pick an expiration for a shareable ride link,
/// creates it via the API, and presents the standard iOS share sheet.
struct ShareRideSheet: View {
    let rideId: String
    @Environment(\.dismiss) private var dismiss

    enum Phase {
        case pickExpiry
        case creating
        case shareReady(URL)
        case error(String)
    }

    @State private var phase: Phase = .pickExpiry
    @State private var showActivitySheet = false
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                content
            }
            .navigationTitle("Share Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showActivitySheet) {
            if let url = shareURL {
                ActivitySheet(items: [url])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .pickExpiry:
            expiryPicker
        case .creating:
            VStack(spacing: Theme.Spacing.large) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Creating share link…")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        case .shareReady(let url):
            VStack(spacing: Theme.Spacing.large) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.Colors.success)
                Text("Link Created!")
                    .font(Theme.Fonts.headerLarge())
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(url.absoluteString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button {
                    shareURL = url
                    showActivitySheet = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(Theme.Fonts.bodyMedium)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.Colors.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                }
                .padding(.horizontal)
            }
        case .error(let message):
            VStack(spacing: Theme.Spacing.large) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.Colors.error)
                Text("Failed to Create Link")
                    .font(Theme.Fonts.headerLarge())
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(message)
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Try Again") {
                    phase = .pickExpiry
                }
                .foregroundStyle(Theme.Colors.accent)
            }
        }
    }

    private var expiryPicker: some View {
        List {
            Section {
                ForEach(ShareExpiry.allCases) { expiry in
                    Button {
                        Task { await createLink(expiry: expiry) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(expiry.label)
                                    .font(Theme.Fonts.bodyMedium)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text(expiry.description)
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    .listRowBackground(Theme.Colors.elevatedBackground)
                }
            } header: {
                Text("Link Expiration")
            } footer: {
                Text("Anyone with the link can view the ride details, route, and telemetry.")
                    .font(Theme.Fonts.caption)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func createLink(expiry: ShareExpiry) async {
        phase = .creating
        let client = GT3APIClient()
        do {
            let response = try await client.createShareLink(rideId: rideId, expiresIn: expiry)
            if let url = client.shareURL(for: response.token) {
                logger.info("Share link created: \(url.absoluteString)")
                phase = .shareReady(url)
            } else {
                phase = .error("Failed to construct share URL")
            }
        } catch let error as APIError {
            switch error {
            case .httpError(let code):
                phase = .error("Server returned \(code). Make sure the ride is uploaded.")
            case .invalidURL:
                phase = .error("Invalid URL")
            case .encodingError:
                phase = .error("Failed to encode request")
            }
        } catch {
            phase = .error(error.localizedDescription)
        }
    }
}

/// Wraps UIActivityViewController for SwiftUI presentation.
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
