#if os(iOS)
import SwiftUI

private struct RidePhotoStatusAlertModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert("Ride Photos", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }
}

extension View {
    func ridePhotoStatusAlert(_ message: Binding<String?>) -> some View {
        modifier(RidePhotoStatusAlertModifier(message: message))
    }
}
#endif
