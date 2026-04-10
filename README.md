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

Requires macOS with Xcode 16+.

```bash
brew install swiftlint
open GT3Companion.xcodeproj
```

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

## License

MIT
