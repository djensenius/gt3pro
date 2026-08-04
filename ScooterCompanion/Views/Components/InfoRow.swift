//
//  InfoRow.swift
//  ScooterCompanion
//
//  Created by David Jensenius.
//

import SwiftUI

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .listRowBackground(Theme.Colors.elevatedBackground)
    }
}

#if DEBUG
#Preview {
    List {
        InfoRow(label: "Device", value: "Scooter")
        InfoRow(label: "Serial", value: "N4GSD1234567890")
        InfoRow(label: "Odometer", value: "1,234 km")
    }
}
#endif
