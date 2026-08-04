#if os(iOS)
import SwiftUI

struct HROverlayView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            SectionHeader(title: "Heart Rate")

            HStack(spacing: Theme.Spacing.medium) {
                StatCard(title: "Avg HR", value: "—", icon: "heart.fill", color: Theme.Colors.error)
                StatCard(title: "Max HR", value: "—", icon: "heart.circle.fill", color: Theme.Colors.warning)
            }

            // HR Zone breakdown placeholder
            VStack(alignment: .leading) {
                Text("HR Zones")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(height: 100)
                    .overlay {
                        Text("Zone breakdown chart coming soon")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
            }

            // HR over time placeholder
            VStack(alignment: .leading) {
                Text("Heart Rate Over Time")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(height: 150)
                    .overlay {
                        Text("HR timeline chart coming soon")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
            }
        }
    }
}

#if DEBUG
#Preview {
    HROverlayView()
        .padding()
}
#endif
#endif
