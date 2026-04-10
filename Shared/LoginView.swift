//
//  LoginView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import SwiftUI

struct LoginView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: Theme.Spacing.extraLarge) {
            Spacer()

            Image(systemName: "scooter")
                .font(.system(size: 72))
                .foregroundStyle(Theme.Colors.accent)

            Text("GT3 Companion")
                .font(Theme.Fonts.headerXL())
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Sign in to sync your rides across all your devices.")
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if let error = errorMessage {
                Text(error)
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.error)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                Task { await signIn() }
            } label: {
                if isSigningIn {
                    ProgressView()
                        .tint(Theme.Colors.textPrimary)
                } else {
                    Label("Sign In", systemImage: "person.badge.key")
                }
            }
            .buttonStyle(.gt3Primary)
            .disabled(isSigningIn)
            .padding(.horizontal, 40)

            Button {
                auth.enterDemoMode()
            } label: {
                Label("Try Demo", systemImage: "play.circle")
            }
            .foregroundStyle(Theme.Colors.textSecondary)
            .disabled(isSigningIn)

            Spacer()
        }
        .background(Theme.Colors.background)
    }

    private func signIn() async {
        isSigningIn = true
        errorMessage = nil
        do {
            try await AuthManager.shared.signInWithOIDC()
        } catch AuthError.cancelled {
            // user dismissed — no error message needed
        } catch {
            errorMessage = error.localizedDescription
        }
        isSigningIn = false
    }
}
