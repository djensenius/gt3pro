# GT3 Companion

A native SwiftUI app for the **Segway SuperScooter GT3 Pro** that connects over Bluetooth Low Energy, reads live telemetry, records GPS routes, tracks surface roughness, monitors heart rate via Apple Watch, and optionally syncs everything to a self-hosted [FluxHaus Server](https://github.com/djensenius/FluxHaus-Server).

## Features

- **Live Dashboard** — Real-time speed, battery, range, and gear mode with Live Activity on the Lock Screen and Dynamic Island
- **Automatic Ride Logging** — Rides start and stop based on speed. GPS routes, surface roughness, and BLE telemetry are recorded automatically
- **Turn-by-Turn Navigation** — MapKit directions with Dynamic Island integration
- **Apple Watch Companion** — Speed, battery, and distance on your wrist. HealthKit workout tracking with heart rate
- **Detailed Telemetry** — Battery voltage/current/temperature, body temp, gear mode, trip stats, estimated range, error codes
- **Ride History** — Browse past rides with charts, maps, and aggregate analytics. Export routes as GPX
- **Scooter Diagnostics** — Odometer, firmware versions, serial number, battery health, BMS cell voltages
- **Multi-Platform** — iPhone, iPad, Mac (Catalyst), Apple Vision Pro

## Architecture

```
GT3 Pro ←—BLE—→ iPhone ←—WCSession—→ Apple Watch
                   │                      │
                   ↓                      ├── Heart Rate
            FluxHaus Server               ├── HKWorkoutSession
                   │                      └── Wrist Display
            PostgreSQL + InfluxDB → Grafana
```

The iPhone is the central hub — it connects to the scooter via BLE, collects telemetry, records GPS, and optionally uploads data to your [FluxHaus Server](https://github.com/djensenius/FluxHaus-Server) instance. The Apple Watch acts as a health sensor and secondary display, communicating with the iPhone over WatchConnectivity.

## Server Setup (Optional)

Cloud sync requires a self-hosted [FluxHaus Server](https://github.com/djensenius/FluxHaus-Server) instance. The server provides:

- **Ride storage** — PostgreSQL for ride history and metadata
- **Telemetry streaming** — InfluxDB for time-series telemetry data
- **Dashboards** — Grafana for visualization and analytics
- **Authentication** — OIDC via [Authentik](https://goauthentik.io/) (or any OIDC provider)

See the [FluxHaus Server README](https://github.com/djensenius/FluxHaus-Server#readme) for setup instructions. The app works fully offline without a server — all data is stored locally on-device.

### Configuring the App for Your Server

By default the app points to `api.fluxhaus.io`. To use your own server, set these keys in `Info.plist`:

| Key | Description | Default |
|-----|-------------|---------|
| `OIDCIssuerBase` | Your OIDC issuer URL | `https://auth.fluxhaus.io/application/o/gt3-companion` |
| `OIDCClientID` | OIDC client ID | `gt3companion` |

The API base URL is configured in `GT3APIClient.swift`.

## Building

Requires **macOS** with **Xcode 16+** and **SwiftLint**.

```bash
brew install swiftlint
open GT3Companion.xcodeproj
```

### Command-Line Builds

```bash
# iOS
xcodebuild -project GT3Companion.xcodeproj \
  -scheme "GT3Companion" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO

# macOS
xcodebuild -project GT3Companion.xcodeproj \
  -scheme "GT3CompanionMac" \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

> **⚠️ Do not run `xcodegen generate` locally.** The checked-in `.xcodeproj` is the source of truth. XcodeGen is only used in CI. Running it locally resets code signing, capabilities, and entitlements.

## First-Time Setup: Extracting the Pairing Password

GT3 Companion needs your scooter's pairing password to connect. The easiest way to get it is from an existing Segway Mobility app backup — no physical button press required.

### Step 1: Create an Unencrypted iPhone Backup

1. Connect your iPhone to your Mac via USB
2. Open **Finder** (macOS Catalina+) or **iTunes** (older macOS)
3. Select your iPhone in the sidebar
4. **Uncheck** "Encrypt local backup" if it's checked
5. Click **Back Up Now** and wait for it to complete

### Step 2: Find the Segway App Preferences

The backup is stored at `~/Library/Application Support/MobileSync/Backup/`. Each backup is a folder of hashed filenames with a `Manifest.db` SQLite database mapping them.

```bash
# Find your latest backup directory
ls -lt ~/Library/Application\ Support/MobileSync/Backup/ | head -5

# Enter the backup directory (use the most recent one)
cd ~/Library/Application\ Support/MobileSync/Backup/YOUR_BACKUP_ID/

# Find the Segway Mobility app preferences file
sqlite3 Manifest.db "SELECT fileID, relativePath FROM Files
    WHERE domain = 'AppDomain-com.ninebot.segway'
    AND relativePath LIKE '%Preferences%plist'"
```

This will output something like:
```
abc123def456|Library/Preferences/com.ninebot.segway.plist
```

### Step 3: Extract the Password

```bash
# Copy the file using the hash from Step 2 (first two chars are subdirectory)
cp ab/abc123def456 /tmp/segway.plist

# Find the decrypt key for your scooter
plutil -p /tmp/segway.plist | grep _decrypt
```

You'll see output like:
```
"N2GWD1234567890_decrypt" => "BASE64ENCODEDSTRING=="
```

### Step 4: Convert to Hex

```bash
echo "BASE64ENCODEDSTRING==" | base64 -d | xxd -p
```

This gives you a **32-character hex string** (representing 16 bytes).

### Step 5: Enter in the App

1. Open GT3 Companion
2. Go to **Settings** → **Pair Scooter**
3. Choose **Recover from Segway App (Recommended)**
4. Paste the 32-character hex string
5. Tap **Save Password**

That's it! The app will use this password to authenticate instantly on every connection — fully automatic, no button press needed.

> **Note**: If you don't have the Segway Mobility app installed, you can do a fresh pair instead. This requires pressing a button on the GT3 Pro dashboard when prompted.

## Running Tests

```bash
xcodebuild test \
  -project GT3Companion.xcodeproj \
  -scheme "GT3Companion" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Unit tests cover crypto, frame parsing, telemetry parsing, and data models. BLE and HealthKit functionality require a physical device and cannot be tested in the simulator.

## Project Structure

```
GT3Companion/
├── App/          # @main entry point, AppDelegate, AppCoordinator
├── BLE/          # CoreBluetooth transport, frame codec
├── Crypto/       # AES-128, key derivation, auth handshake
├── Data/         # Register reader, parser, GPS, ride tracker
├── Upload/       # API client, upload queue
├── Views/        # SwiftUI views and components
├── Navigation/   # MapKit turn-by-turn
├── Health/       # WatchConnectivity, HealthKit bridge
GT3CompanionWatch/  # watchOS companion app
GT3CompanionWidgets/ # Live Activity widget extension
GT3CompanionMac/    # macOS target
GT3CompanionVision/ # visionOS target
Shared/             # Code shared between targets (SwiftData models, AuthManager)
docs/               # BLE protocol spec, Grafana dashboard
```

## Privacy

See the [Privacy Policy](PRIVACY.md) for details on what data the app collects and how it is used.

## License

Apache 2.0 — see [LICENSE](LICENSE) for details.
