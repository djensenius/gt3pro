//
//  ShareRideSheet.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if os(iOS)
import SwiftUI

struct ShareRideSheet: View {
    let rideId: String

    var body: some View {
        RideShareLinkSheet(rideId: rideId)
    }
}
#endif
