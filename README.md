# GT3 Companion

A native SwiftUI app for the Segway SuperScooter GT3 Pro that provides:

- **Live Activity** — Speed, battery, trip data on Dynamic Island and Lock Screen
- **Automatic ride logging** — BLE telemetry, GPS routes, surface roughness
- **Turn-by-turn navigation** — MapKit directions with Dynamic Island integration
- **Apple Watch companion** — Heart rate tracking, HealthKit workouts, wrist display
- **Ride data explorer** — Charts, maps, aggregate analytics
- **Multi-platform** — iPhone, iPad, Mac, Apple Vision Pro

## Architecture

```
GT3 Pro ←—BLE—→ iPhone ←—WCSession—→ Apple Watch
                   │                      │
                   ↓                      ├── Heart Rate
              fluxhaus-server             ├── Workouts
                   │                      └── Wrist Display
              PostgreSQL + InfluxDB → Grafana
```

## Building

Requires macOS with Xcode 16+. Uses [xcodegen](https://github.com/yonaskolb/XcodeGen) for project generation.

```bash
brew install xcodegen swiftlint
xcodegen generate
open GT3Companion.xcodeproj
```

## License

MIT
