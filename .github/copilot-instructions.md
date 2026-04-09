# GT3 Companion — Segway GT3 Pro Ride Tracker

GT3 Companion is a native Swift/SwiftUI iOS app that connects to a Segway SuperScooter GT3 Pro over Bluetooth Low Energy (BLE), reads live telemetry, records GPS routes, tracks surface roughness via CoreMotion, and uploads everything to the FluxHaus monitoring stack. It includes an Apple Watch companion for HealthKit workout tracking with heart rate monitoring.

**Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the information here.**

## Working Effectively

### Prerequisites and Setup
- **macOS with Xcode 16+** required for building
- **Apple Developer Account** needed for testing on physical devices (BLE requires real hardware)
- **SwiftLint** installed (`brew install swiftlint`)
- The app connects to api.fluxhaus.io for data upload (OIDC authentication)

### Building the Application
The application uses Xcode with multiple targets:

#### Core Build Commands (NEVER CANCEL - Set 90+ minute timeouts)
```bash
# Open the project in Xcode
open GT3Companion.xcodeproj

# Command line builds
xcodebuild -project GT3Companion.xcodeproj -scheme "GT3Companion" -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build CODE_SIGNING_ALLOWED=NO
xcodebuild -project GT3Companion.xcodeproj -scheme "GT3CompanionWatch" -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

**CRITICAL BUILD TIMING:**
- **Initial build: 10-20 minutes** (includes compilation)
- **Incremental builds: 1-5 minutes**
- **NEVER CANCEL** builds before 30 minutes

### Testing
```bash
# Run unit tests (takes 5-10 minutes)
xcodebuild test -project GT3Companion.xcodeproj -scheme "GT3Companion" -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

**Important**: BLE and HealthKit functionality cannot be tested in the simulator. Unit tests cover crypto, frame parsing, telemetry parsing, and data models. Integration testing requires a real GT3 Pro scooter.

### Code Quality and Linting
```bash
# Run linting (required before every commit)
swiftlint --config .swiftlint.yml

# Run with strict mode (as used in CI)
swiftlint --strict --config .swiftlint.yml
```

**SwiftLint Configuration** (`.swiftlint.yml`):
- Excludes `Packages/` and `GT3CompanionWatch/` directories
- Limits: file_length: 500, function_body_length: 100, type_body_length: 400
- **ALWAYS run SwiftLint before committing** — CI will fail otherwise

## Architecture

### Key Design Decisions
- **Swift 6 strict concurrency**: Use `actor` for BLE and crypto state to avoid data races
- **Catppuccin theming**: Latte (light) / Mocha (dark) — see `Theme.swift`. Primary accent: Sky/Sapphire.
- **OIDC auth**: Same `AuthManager` pattern as FluxHaus app. Server: api.fluxhaus.io
- **SwiftData** for local persistence (rides, samples, upload queue)
- **ActivityKit** for Live Activity / Dynamic Island
- **Core Bluetooth directly** — no third-party BLE libraries. The Ninebot protocol requires low-level GATT control.
- **CommonCrypto** for AES-128-ECB (CryptoKit doesn't expose raw ECB)
- **CryptoKit** for SHA-1 (`Insecure.SHA1`) and SHA-256
- **WatchConnectivity** for iPhone ↔ Watch communication (phone is BLE hub, watch is health sensor + display)

### Component Architecture
```
┌────────────────────────────────────────────────────────────┐
│                     GT3 Companion App                      │
├──────────┬──────────┬──────────┬──────────┬────────────────┤
│ BLE Layer│ Crypto   │ Data     │ UI Layer │ Upload Layer   │
│          │ Layer    │ Layer    │          │                │
│ CoreBT   │ AES-128  │ RideStore│ SwiftUI  │ GT3APIClient   │
│ Manager  │ NbCrypto │ GPS+IMU  │ Live Act │ UploadQueue    │
│ Transport│ Auth SM  │ SwiftData│ MapKit   │ BG URLSession  │
├──────────┴──────────┴──────────┴──────────┴────────────────┤
│                    Background Services                      │
│  BLE State Restoration · Background Upload · Live Activity  │
│  CoreLocation GPS · CoreMotion Roughness · WatchConnectivity│
└────────────────────────────────────────────────────────────┘

GT3 Pro ←—BLE—→ iPhone ←—WCSession—→ Apple Watch
                   │                      │
                   ↓                      ├── Heart Rate
                fluxhaus-server           ├── HKWorkoutSession
                   │                      └── Wrist Display
              PostgreSQL + InfluxDB → Grafana
```

### Ninebot BLE Protocol
- **Service UUID**: `6e400001-0000-0000-006e-696e65626f74`
- **Write characteristic**: `0002` (app → device)
- **Notify characteristic**: `0004` (device → app) — **NOT 0003!**
- **Encryption**: AES-128 CTR + CBC-MAC (custom CCM-like, "Encryption2" protocol)
- **Authentication**: 3-phase handshake (PRE_COMM → SET_PWD → AUTH)
- **Frame format**: `[5A A5 LEN BT_ID TARGET CMD INDEX PAYLOAD]`

### Data Flow
1. iPhone connects to GT3 Pro via BLE, authenticates with stored password
2. Polls 58 registers at 1-2 Hz (speed, battery, BMS, temps, GPS, roughness)
3. Watch records heart rate via HKWorkoutSession
4. iPhone batches telemetry → POSTs to fluxhaus-server
5. Server stores rides in PostgreSQL, streams telemetry to InfluxDB
6. Grafana dashboards visualize everything

## Project Structure
```
GT3Companion/
├── GT3Companion.xcodeproj
├── GT3Companion/                    # Main iOS app target
│   ├── App/                         # @main entry, AppDelegate
│   ├── BLE/                         # CoreBluetooth, transport, frame codec
│   ├── Crypto/                      # AES, key derivation, auth handshake
│   ├── Data/                        # Register reader, parser, ride tracker
│   ├── Upload/                      # API client, upload queue
│   ├── Views/                       # SwiftUI views + components
│   ├── Navigation/                  # MapKit turn-by-turn
│   ├── Health/                      # WatchConnectivity, HealthKit
│   └── Utilities/                   # Keychain, logging
├── GT3CompanionWidgets/             # Widget Extension (Live Activity)
├── GT3CompanionWatch/               # watchOS app
├── GT3CompanionTests/               # Unit tests
├── Shared/                          # Shared between app + widget
├── Icons/                           # App icon source files
└── docs/                            # Specification and documentation
```

## Common Development Patterns

### BLE Communication
All BLE state is managed by `ScooterConnectionManager` (an actor). Never access `CBCentralManager` or `CBPeripheral` outside this actor.

### Crypto
The encryption engine (`NinebotCrypto`) handles both non-SN mode (PRE_COMM) and SN mode (normal communication). Key derivation uses SHA-1. The Java LCG PRNG port (`JavaLCG`) must exactly replicate `java.util.Random` behavior for password generation.

### Data Upload
All uploads go through `UploadQueue` → `GT3APIClient` → fluxhaus-server. Never write directly to InfluxDB from the app. The API client uses OIDC tokens via `AuthManager` with CSRF token protection.

### Theming
Use `Theme.Colors`, `Theme.Fonts`, `Theme.Spacing` from `Theme.swift`. Never use raw color literals. The theme uses Catppuccin Latte/Mocha with dynamic light/dark adaptation.

## Troubleshooting

### Build Failures
- **"Bundle.module not found"**: Normal on Linux — Apple platforms only
- **SwiftLint violations**: Run `swiftlint --config .swiftlint.yml` and fix
- **Signing errors**: Use `CODE_SIGNING_ALLOWED=NO` for CI/simulator builds

### BLE Issues
- Notify characteristic is `0004`, NOT `0003` — this is the #1 source of bugs
- After reconnect, toggle CCCD off→300ms→on→200ms drain before auth
- Echo detection: if PRE_COMM response equals request, disconnect and retry
- Only one app can hold the BLE connection — force-quit Segway Mobility app

### Background Execution
- Live Activity keeps app alive longer in background
- Persist samples to SwiftData frequently (every few seconds)
- Detect orphaned rides on launch and finalize them
