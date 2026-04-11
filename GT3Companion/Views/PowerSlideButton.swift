//
//  PowerSlideButton.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if os(iOS)
import SwiftUI

/// A slide-to-confirm button that prevents accidental power-off.
/// The user drags the thumb from left to right to trigger the action.
struct PowerSlideButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let onComplete: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isComplete = false
    @GestureState private var isDragging = false

    private let thumbSize: CGFloat = 50
    private let trackHeight: CGFloat = 56
    private let completionThreshold: CGFloat = 0.8

    var body: some View {
        GeometryReader { geometry in
            let maxOffset = geometry.size.width - thumbSize - 8

            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(color.opacity(0.15))
                    .overlay(
                        Capsule()
                            .strokeBorder(color.opacity(0.3), lineWidth: 1)
                    )

                // Progress fill
                Capsule()
                    .fill(color.opacity(0.25))
                    .frame(width: dragOffset + thumbSize + 8)

                // Label
                HStack {
                    Spacer()
                    Label(title, systemImage: systemImage)
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundStyle(color)
                        .opacity(labelOpacity(maxOffset: maxOffset))
                    Spacer()
                }

                // Thumb
                Circle()
                    .fill(color)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(isComplete ? 90 : 0))
                    )
                    .shadow(color: color.opacity(0.4), radius: isDragging ? 8 : 4)
                    .scaleEffect(isDragging ? 1.08 : 1.0)
                    .offset(x: 4 + dragOffset)
                    .gesture(
                        DragGesture()
                            .updating($isDragging) { _, state, _ in
                                state = true
                            }
                            .onChanged { value in
                                guard !isComplete else { return }
                                let newOffset = max(0, min(value.translation.width, maxOffset))
                                dragOffset = newOffset

                                // Haptic at threshold
                                if newOffset / maxOffset >= completionThreshold {
                                    triggerCompletion(maxOffset: maxOffset)
                                }
                            }
                            .onEnded { _ in
                                guard !isComplete else { return }
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    dragOffset = 0
                                }
                            }
                    )
            }
            .frame(height: trackHeight)
        }
        .frame(height: trackHeight)
        .allowsHitTesting(!isComplete)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint("Double tap to confirm")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            triggerAccessibilityCompletion()
        }
        .onChange(of: isComplete) { _, complete in
            if complete {
                // Reset after a short delay
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        dragOffset = 0
                        isComplete = false
                    }
                }
            }
        }
    }

    private func labelOpacity(maxOffset: CGFloat) -> Double {
        guard maxOffset > 0 else { return 1 }
        let progress = dragOffset / maxOffset
        return max(0, 1 - progress * 2.5)
    }

    private func triggerCompletion(maxOffset: CGFloat) {
        guard !isComplete else { return }
        isComplete = true

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            dragOffset = maxOffset
        }

        onComplete()
    }

    private func triggerAccessibilityCompletion() {
        guard !isComplete else { return }
        isComplete = true
        onComplete()
    }
}
#endif
