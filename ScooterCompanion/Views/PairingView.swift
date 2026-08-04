//
//  PairingView.swift
//  ScooterCompanion
//
//  Created by David Jensenius.
//

import SwiftUI

struct PairingView: View {
    @State private var pairingMode: PairingMode = .selection
    @State private var recoveredPassword = ""
    @State private var isPairing = false
    @State private var pairingStatus = ""
    @State private var passwordSaved = false

    enum PairingMode {
        case selection
        case freshPair
        case recoverPassword
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.extraLarge) {
                switch pairingMode {
                case .selection:
                    selectionView
                case .freshPair:
                    freshPairView
                case .recoverPassword:
                    recoverPasswordView
                }
            }
            .padding()
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Pair Scooter")
        .onAppear {
            if let existingHex = ScooterKeychain.loadPasswordHex(), pairingMode == .selection {
                recoveredPassword = existingHex
                pairingMode = .recoverPassword
            }
        }
    }

    private var selectionView: some View {
        VStack(spacing: Theme.Spacing.large) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundStyle(Theme.Colors.accent)

            Text("How would you like to pair?")
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)

            Button {
                pairingMode = .recoverPassword
            } label: {
                Label(
                    "Recover from Official App (Recommended)",
                    systemImage: "key.fill"
                )
            }
            .buttonStyle(.gt3Primary)

            Button {
                pairingMode = .freshPair
            } label: {
                Label(
                    "Fresh Pair (requires button press)",
                    systemImage: "antenna.radiowaves.left.and.right"
                )
            }
            .buttonStyle(.gt3Primary)
        }
    }

    private var freshPairView: some View {
        VStack(spacing: Theme.Spacing.large) {
            if isPairing {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Press the button on your GT3 Pro dashboard")
                    .font(Theme.Fonts.bodyLarge)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                Text(pairingStatus)
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                Text("Make sure your GT3 Pro is powered on and nearby")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Button("Start Pairing") { isPairing = true }
                    .buttonStyle(.gt3Primary)
            }
        }
    }

    private var recoverPasswordView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            Text("Recover Password")
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("1. Create an unencrypted backup of your iPhone via Finder")
                .font(Theme.Fonts.bodySmall)
            Text("2. Find the official mobility app plist in the backup")
                .font(Theme.Fonts.bodySmall)
            Text("3. Look for the {serial}_decrypt key (Base64 encoded)")
                .font(Theme.Fonts.bodySmall)
            Text("4. Base64-decode the value, then convert the raw bytes to hex")
                .font(Theme.Fonts.bodySmall)
            Text("5. Paste the resulting 32-character hex string below")
                .font(Theme.Fonts.bodySmall)

            TextField("Hex password (32 characters)", text: $recoveredPassword)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: recoveredPassword) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed != newValue { recoveredPassword = trimmed }
                }

            if passwordSaved {
                Label("Password saved!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.success)
                    .font(Theme.Fonts.bodyMedium)
            }

            Button("Save Password") {
                if ScooterKeychain.savePassword(hex: recoveredPassword) {
                    passwordSaved = true
                }
            }
            .buttonStyle(.gt3Primary)
            .disabled(!Self.isValidHex(recoveredPassword))
        }
    }

    /// Validates that the input is exactly 32 hex characters (0-9, a-f, A-F).
    private static func isValidHex(_ value: String) -> Bool {
        let hexPattern = /^[0-9a-fA-F]{32}$/
        return value.wholeMatch(of: hexPattern) != nil
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PairingView()
    }
}
#endif
