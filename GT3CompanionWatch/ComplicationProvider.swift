import WidgetKit
import SwiftUI

struct GT3ComplicationEntry: TimelineEntry {
    let date: Date
    let batteryPercent: Int
    let lastRideDistance: Double
}

struct GT3ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> GT3ComplicationEntry {
        GT3ComplicationEntry(date: Date(), batteryPercent: 85, lastRideDistance: 12.4)
    }

    func getSnapshot(in context: Context, completion: @escaping (GT3ComplicationEntry) -> Void) {
        completion(GT3ComplicationEntry(date: Date(), batteryPercent: 85, lastRideDistance: 12.4))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GT3ComplicationEntry>) -> Void) {
        let entry = GT3ComplicationEntry(date: Date(), batteryPercent: 0, lastRideDistance: 0)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct GT3BatteryComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GT3Battery", provider: GT3ComplicationProvider()) { entry in
            GT3BatteryComplicationView(entry: entry)
        }
        .configurationDisplayName("GT3 Battery")
        .description("Shows your scooter's battery level")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular, .accessoryCorner])
    }
}

struct GT3BatteryComplicationView: View {
    let entry: GT3ComplicationEntry

    var body: some View {
        VStack {
            Image(systemName: "scooter")
                .font(.caption)
            Text("\(entry.batteryPercent)%")
                .font(.headline)
        }
    }
}
