//
//  InfoRow.swift
//  GT3Companion
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
    }
}
