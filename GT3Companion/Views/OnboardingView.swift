//
//  OnboardingView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import SwiftUI

struct OnboardingView: View {
    @State private var currentStep = 0
    @Binding var isComplete: Bool
    @StateObject private var permissions = PermissionsManager()
    @State private var isRequesting = false

    private let steps: [OnboardingStep] = [
        OnboardingStep(
            icon: "antenna.radiowaves.left.and.right",
            title: "Bluetooth",
            description: "GT3 Companion uses Bluetooth to connect to your scooter and read ride data.",
            isRequired: true,
            permission: .bluetooth
        ),
        OnboardingStep(
            icon: "location.fill",
            title: "Location",
            description: "We record your GPS route during rides to map your trips and calculate distance.",
            isRequired: true,
            permission: .locationWhenInUse
        ),
        OnboardingStep(
            icon: "location.fill.viewfinder",
            title: "Background Location",
            description: "To track rides automatically when your phone is in your pocket, "
                + "we need 'Always' location access. This only activates during rides.",
            isRequired: true,
            permission: .locationAlways
        ),
        OnboardingStep(
            icon: "heart.fill",
            title: "Health Data",
            description: "Connect your Apple Watch to track heart rate during rides "
                + "and save workouts to Apple Health.",
            isRequired: false,
            permission: .health
        ),
        OnboardingStep(
            icon: "waveform.path",
            title: "Motion Sensors",
            description: "We use your phone's motion sensors to detect road surface quality during rides.",
            isRequired: false,
            permission: .motion
        ),
        OnboardingStep(
            icon: "bell.fill",
            title: "Notifications",
            description: "Get a summary notification when your ride ends.",
            isRequired: false,
            permission: .notifications
        )
    ]

    var body: some View {
        VStack(spacing: Theme.Spacing.extraLarge) {
            Spacer()

            if currentStep < steps.count {
                stepView(steps[currentStep])
            } else {
                completionView
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(0...steps.count, id: \.self) { index in
                    Circle()
                        .fill(
                            index <= currentStep
                                ? Theme.Colors.accent
                                : Theme.Colors.textSecondary.opacity(0.3)
                        )
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 30)
        }
        .background(Theme.Colors.background)
    }

    private func stepView(_ step: OnboardingStep) -> some View {
        Group {
            Image(systemName: step.icon)
                .font(.system(size: 60))
                .foregroundStyle(Theme.Colors.accent)

            Text(step.title)
                .font(Theme.Fonts.headerXL())
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(step.description)
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(step.permission == .none ? "Continue" : "Allow Access") {
                Task {
                    isRequesting = true
                    await permissions.request(step.permission)
                    isRequesting = false
                    withAnimation { currentStep += 1 }
                }
            }
            .buttonStyle(.gt3Primary)
            .disabled(isRequesting)
            .padding(.horizontal, 40)

            if !step.isRequired {
                Button("Skip") {
                    withAnimation { currentStep += 1 }
                }
                .foregroundStyle(Theme.Colors.textSecondary)
                .disabled(isRequesting)
            }
        }
    }

    private var completionView: some View {
        Group {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.Colors.success)

            Text("You're All Set!")
                .font(Theme.Fonts.headerXL())
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Just hop on your scooter and GT3 Companion handles the rest.")
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Get Started") {
                isComplete = true
            }
            .buttonStyle(.gt3Primary)
            .padding(.horizontal, 40)
        }
    }
}

struct OnboardingStep {
    let icon: String
    let title: String
    let description: String
    let isRequired: Bool
    let permission: PermissionRequest
}
