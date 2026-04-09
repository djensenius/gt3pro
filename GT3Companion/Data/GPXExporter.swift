#if os(iOS)
import Foundation

struct GPXCoordinate {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let timestamp: Date
    let speed: Double
}

enum GPXExporter {
    static func export(
        rideName: String,
        date: Date,
        coordinates: [GPXCoordinate]
    ) -> String {
        let dateFormatter = ISO8601DateFormatter()
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="GT3Companion">
          <trk>
            <name>\(rideName)</name>
            <trkseg>
        """
        for coord in coordinates {
            let trkpt = """

                  <trkpt lat="\(coord.latitude)" lon="\(coord.longitude)">
                    <ele>\(coord.altitude)</ele>
                    <time>\(dateFormatter.string(from: coord.timestamp))</time>
                    <speed>\(coord.speed)</speed>
                  </trkpt>
            """
            gpx += trkpt
        }
        let closing = """

            </trkseg>
          </trk>
        </gpx>
        """
        gpx += closing
        return gpx
    }

    static func exportToFileURL(
        rideName: String,
        date: Date,
        coordinates: [GPXCoordinate]
    ) -> URL? {
        let gpxString = export(rideName: rideName, date: date, coordinates: coordinates)
        let fileName = "GT3_\(rideName)_\(ISO8601DateFormatter().string(from: date)).gpx"
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "-")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try gpxString.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            return nil
        }
    }
}
#endif
