# GT3 Companion — iOS App Specification

> A native Swift iOS app for the Segway GT3 Pro that provides live ride telemetry via Dynamic Island / Live Activity, automatic background data sync, and upload to a self-hosted monitoring stack.

---

## Table of Contents

1. [Overview & Goals](#1-overview--goals)
2. [Additional v1 Goals](#2-additional-v1-goals)
3. [Target Device & Protocol Summary](#3-target-device--protocol-summary)
4. [App Architecture](#4-app-architecture)
5. [BLE Communication Layer](#5-ble-communication-layer)
6. [Encryption & Authentication](#6-encryption--authentication)
7. [GT3 Register Map & Data Model](#7-gt3-register-map--data-model)
8. [Live Activity & Dynamic Island](#8-live-activity--dynamic-island)
9. [Background Sync](#9-background-sync)
10. [Data Upload & Server Integration](#10-data-upload--server-integration)
11. [Local Persistence](#11-local-persistence)
12. [UI Design](#12-ui-design)
13. [First-Time Pairing Flow](#13-first-time-pairing-flow)
14. [iOS Configuration & Entitlements](#14-ios-configuration--entitlements)
15. [Project Structure](#15-project-structure)
16. [Dependencies](#16-dependencies)
17. [Key Risks & Mitigations](#17-key-risks--mitigations)
18. [Reference Materials](#18-reference-materials)
19. [First-Launch Onboarding](#19-first-launch-onboarding)
20. [Apple Watch Integration](#20-apple-watch-integration)

---

## 1. Overview & Goals

**GT3 Companion** is a personal-use iOS app that connects to a Segway SuperScooter GT3 Pro over Bluetooth Low Energy (BLE), reads telemetry and diagnostic data, and uploads it to a self-hosted monitoring stack (InfluxDB → Grafana) via the fluxhaus-server API.

### Primary Goals

- **Live Activity while riding**: Show speed, battery %, trip distance, and estimated range on the Dynamic Island and Lock Screen without opening the app.
- **Automatic background sync**: When the GT3 Pro powers on and the phone detects the BLE advertisement, the app wakes in the background, connects, reads cumulative stats, and uploads them — no user interaction required.
- **Ride logging**: Record timestamped telemetry during rides (speed, power draw, battery state, temperature) and upload completed ride logs.
- **Grafana integration**: Push all data to the existing FluxHaus monitoring infrastructure so GT3 data lives alongside EV6, TrueNAS, Home Assistant, and other dashboards.

### Non-Goals (for v1)

- Modifying scooter settings (speed modes, lights, etc.) — read-only to start.
- Firmware updates.
- App Store distribution — sideloaded via Xcode / personal signing.

---

## 2. Additional v1 Goals

The following features are included in the v1 scope:

- **GPS route tracking** at 1–2 Hz paired with every telemetry sample — each `TelemetrySample` includes lat/lon/altitude/speed/course from CoreLocation so rides have full spatial context.
- **CoreMotion surface roughness detection** — accelerometer-based RMS scoring to classify road surface quality along the route.
- **Turn-by-turn navigation** via MapKit — search for destinations, get directions, and follow guided navigation with voice/haptic cues while riding.
- **Apple Watch companion** with HealthKit workout tracking — continuous heart rate, calorie burn, and HR zone monitoring during rides via `HKWorkoutSession`.
- **Full ride data exploration** — timeline scrubber synced to map and charts, aggregate analytics (trends, battery health over time, heatmaps, personal records).

---

## 3. Target Device & Protocol Summary

### Device Identification

| Property | Value |
|---|---|
| Model | Segway SuperScooter GT3 (also GT3 Pro) |
| Hardware ID | 257 (0x101) |
| Server ID | 10257 |
| Protocol | BleEncryption2Protocol2 (Enc2) |
| Total documented commands | 192 |
| BLE advertising name pattern | `NB-*` or similar Ninebot prefix |

### Protocol Stack

```
┌─────────────────────────────────────┐
│  Application (register read/write)  │
├─────────────────────────────────────┤
│  Ninebot Frame Format (5A A5)      │
├─────────────────────────────────────┤
│  Encryption2 (AES-128 CTR + MAC)   │
├─────────────────────────────────────┤
│  BLE GATT (Ninebot Custom Service) │
├─────────────────────────────────────┤
│  Core Bluetooth (iOS)              │
└─────────────────────────────────────┘
```

### BLE Service UUIDs (Ninebot Custom — "Hospitality")

| Role | UUID |
|---|---|
| Service | `6e400001-0000-0000-006e-696e65626f74` |
| Write (app → device) | `6e400002-0000-0000-006e-696e65626f74` |
| RCTP Write (secondary) | `6e400003-0000-0000-006e-696e65626f74` |
| **Notify (device → app)** | `6e400004-0000-0000-006e-696e65626f74` |

> **Critical**: The notify characteristic is `0004`, NOT `0003`. Characteristic `0003` is the RCTP secondary write channel. This is a common source of bugs.

The UUID suffix `006e-696e65626f74` decodes to `\x00ninebot` in ASCII.

---

## 4. App Architecture

### High-Level Components

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          GT3 Companion App                               │
├──────────────┬──────────────┬──────────────┬──────────────┬──────────────┤
│  BLE Layer   │  Crypto      │  Data Layer  │  UI Layer    │  Sensors     │
│              │  Layer       │              │              │              │
│ CoreBluetooth│ NinebotCrypto│ RideStore    │ SwiftUI Views│ GPSTracker   │
│ Manager      │ (AES-128)   │ (SwiftData)  │ Live Activity│ (CoreLoc.)   │
│ Transport    │ Auth State   │ UploadQueue  │ Widget       │ SurfaceRough-│
│ FrameCodec   │ Machine      │              │              │ nessTracker  │
│              │              │              │              │ (CoreMotion) │
├──────────────┴──────────────┴──────────────┴──────────────┤              │
│                       Navigation                          │ Navigation-  │
│                    NavigationManager (MapKit)              │ Manager      │
│                                                           │ (MapKit)     │
├───────────────────────────────────────────────────────────┴──────────────┤
│                    Background Services                                   │
│  - BLE State Restoration                                                 │
│  - Background Upload (URLSession background)                             │
│  - Live Activity Management (ActivityKit)                                │
│  - WatchConnectivity Relay (phone ↔ Watch)                               │
├──────────────────────────────────────────────────────────────────────────┤
│                    Watch App (separate target)                            │
│  - HKWorkoutSession + HKLiveWorkoutBuilder                               │
│  - Heart rate / calorie streaming                                        │
│  - WatchConnectivity (watch → phone: HR, phone → watch: telemetry)       │
│  - Ride-in-progress UI + complications                                   │
└──────────────────────────────────────────────────────────────────────────┘
```

### Key Architectural Decisions

- **Swift 6 + strict concurrency**: Use actors for BLE and crypto state to avoid data races.
- **SwiftData** for local persistence (rides, telemetry samples, upload queue).
- **ActivityKit** for Live Activity / Dynamic Island.
- **No third-party BLE libraries**: Core Bluetooth directly — the protocol requires low-level GATT control.
- **CryptoKit + CommonCrypto** for AES-128-ECB (CryptoKit doesn't expose raw ECB, so CommonCrypto's `CCCrypt` is needed for single-block ECB operations).
- **GPSTracker (CoreLocation)**: Captures lat/lon/altitude/speed/course at 1–2 Hz, paired with each telemetry sample.
- **SurfaceRoughnessTracker (CoreMotion)**: Uses accelerometer data to compute an RMS roughness score per sample.
- **NavigationManager (MapKit)**: Provides turn-by-turn directions with voice/haptic guidance.
- **WatchConnectivity relay**: Bridges telemetry from phone to Watch and health data from Watch to phone.

---

## 5. BLE Communication Layer

### 5.1 Connection Manager (`ScooterConnectionManager`)

An actor wrapping `CBCentralManager` that manages the full BLE lifecycle.

**Responsibilities:**
- Scanning for GT3 Pro by service UUID
- Connecting / reconnecting with state restoration
- Service and characteristic discovery
- MTU negotiation
- Delegating frame I/O to the transport layer

**State Machine:**

```
                    ┌─────────────┐
                    │ Disconnected│
                    └──────┬──────┘
                           │ scanForPeripherals / connectPeripheral
                           ▼
                    ┌─────────────┐
                    │ Connecting  │
                    └──────┬──────┘
                           │ didConnect
                           ▼
                    ┌─────────────┐
                    │ Discovering │ (services → characteristics → subscribe notify)
                    └──────┬──────┘
                           │ ready
                           ▼
                    ┌──────────────┐
                    │Authenticating│ (PRE_COMM → SET_PWD → AUTH)
                    └──────┬───────┘
                           │ authenticated
                           ▼
                    ┌─────────────┐
                    │  Connected  │ (normal encrypted communication)
                    └──────┬──────┘
                           │ didDisconnect
                           ▼
                    ┌──────────────┐
                    │ Reconnecting │ (connectPeripheral — never times out)
                    └──────────────┘
```

**State Restoration**: The manager is initialized with `CBCentralManagerOptionRestoreIdentifierKey` so iOS can relaunch the app and restore BLE state after termination.

```swift
centralManager = CBCentralManager(
    delegate: self,
    queue: bleQueue,
    options: [
        CBCentralManagerOptionRestoreIdentifierKey: "GT3CompanionCentral"
    ]
)
```

**iOS Bonded Device Handling** (critical for reliable reconnection):

On iOS, bonded (previously connected) peripherals don't appear in normal BLE scans. The app must also query system-connected peripherals:

```swift
let connected = centralManager.retrieveConnectedPeripherals(
    withServices: [CBUUID(string: "6e400001-0000-0000-006e-696e65626f74")]
)
```

Additionally, on reconnect iOS caches CCCD state, which can cause stale notifications. The workaround is to toggle notifications off → wait 300ms → on before starting the auth handshake:

```swift
peripheral.setNotifyValue(false, for: notifyCharacteristic)
try await Task.sleep(for: .milliseconds(300))
peripheral.setNotifyValue(true, for: notifyCharacteristic)
// Wait ~200ms to drain stale cached notifications
try await Task.sleep(for: .milliseconds(200))
// Now begin PRE_COMM
```

**Echo Detection**: On some iOS reconnections, the device echoes back writes instead of processing them. After sending PRE_COMM, compare the response bytes to the request. If identical, disconnect, wait 1–2s (escalating), and retry. Up to 3 retries with delays of 1s, 2s.

### 5.2 Frame Transport (`NinebotTransport`)

Handles frame serialization, fragmentation, and reassembly over the GATT characteristics.

**Outbound (app → device):**

1. Build plaintext Ninebot frame
2. Encrypt via `NinebotCrypto`
3. Fragment into MTU-sized chunks (MTU - 3 bytes per chunk, default 20 bytes)
4. Write each chunk sequentially to characteristic `0002` with ~10ms inter-fragment delay

**Inbound (device → app):**

1. Receive notification chunks from characteristic `0004`
2. Reassemble using frame state machine (look for `5A A5` sync, read length, accumulate)
3. Decrypt via `NinebotCrypto`
4. Parse frame fields and dispatch to caller

**Frame Reassembly State Machine:**

```
IDLE ─── see 0x5A ───► HAVE_HEAD ─── see 0xA5 ───► HAVE_BEGIN ──► accumulate
                        │                                           │
                        └── other ──► IDLE              until LENGTH + 13 bytes
                                                                    │
                                                                    ▼
                                                              deliver frame
```

### 5.3 Frame Format (Encryption2)

**Plaintext frame (before encryption):**

```
Offset  Size  Field
  0      1    0x5A (sync)
  1      1    0xA5 (sync — becomes 0xB5 after encryption)
  2      1    LENGTH (payload bytes only, excludes header)
  3      1    BT_ID (always 0x3E)
  4      1    TARGET_ID (destination board)
  5      1    CMD (command byte)
  6      1    INDEX (register address)
  7..    N    PAYLOAD (N = LENGTH - 4 data bytes)
```

**Encrypted frame (on the wire):**

```
[header 3B unchanged] [encrypted payload] [4B encrypted MAC] [2B counter BE]
```

Total encrypted frame = plaintext length + 6 bytes.

**Board Target IDs:**

| Board | ID |
|---|---|
| BLE | 0x04 |
| ESC/VCU | 0x02 |
| BMS1 | 0x06 |
| BMS2 | 0x07 |
| MCU | 0x05 |
| TFT | 0x09 |

---

## 6. Encryption & Authentication

### 6.1 Encryption2 Algorithm

The GT3 uses the Enc2 protocol: AES-128 in a custom CTR-like mode with CBC-MAC authentication.

| Property | Value |
|---|---|
| Block cipher | AES-128-ECB (single-block operations) |
| Mode | Custom CTR with CBC-MAC (CCM-like) |
| Key size | 128 bits (16 bytes) |
| Key derivation | SHA-1 of concatenated key pair, first 16 bytes |
| MAC tag size | 4 bytes (truncated from 16-byte CBC-MAC) |
| Counter | 16-bit, big-endian, monotonically increasing |
| Replay protection | Yes — counter must strictly increase per session |

### 6.2 Key Derivation

```
func deriveKey(key1: Data, key2: Data?) -> Data {
    let k1 = key1.padded(to: 16)       // right-pad with 0x00 to 16 bytes
    let k2 = key2?.padded(to: 16) ?? Data(count: 16)
    let combined = k1 + k2             // 32 bytes
    let hash = SHA1.hash(data: combined)
    return Data(hash.prefix(16))       // first 16 bytes of SHA-1
}
```

**Key evolution through handshake phases:**

| Phase | key1 | key2 | Counter mode |
|---|---|---|---|
| PRE_COMM | BLE device name (UTF-8) | null (16 zero bytes) | Non-SN (counter = 0) |
| SET_PWD | BLE device name (UTF-8) | auth_param (16B from device) | SN (counter > 0) |
| AUTH | session password (16B) | auth_param (16B from device) | SN (counter > 0) |
| COMM (normal) | session password (16B) | auth_param (16B from device) | SN (counter > 0) |

### 6.3 Nonce Construction (13 bytes)

```
nonce = counter_bigEndian(4 bytes) + auth_param[0..<8] + 0x00
```

### 6.4 CTR Encryption

For each 16-byte block `i` (starting at 1):

```
A_i = [0x01] + nonce(13B) + [0x00, i]
keystream = AES_ECB(aes_key, A_i)
ciphertext_block = plaintext_block XOR keystream
```

The MAC tag is encrypted with `A_0`:

```
A_0 = [0x01] + nonce(13B) + [0x00, 0x00]
encrypted_tag = raw_tag[0..<4] XOR AES_ECB(aes_key, A_0)[0..<4]
```

### 6.5 CBC-MAC Computation

```
B_0 = [0x59] + nonce(13B) + [0x00, payload_length]
X = AES_ECB(key, B_0)

// Associated data (3-byte header, zero-padded to 16)
aad = plaintext[0..<3] + zeros(13)
X = AES_ECB(key, X XOR aad)

// Each 16-byte block of payload
for block in plaintext[3...].chunked(size: 16) {
    X = AES_ECB(key, X XOR block.padded(to: 16))
}

tag = X[0..<4]
```

### 6.6 Non-SN Mode (counter == 0)

Used only for PRE_COMM (first message):

```
keystream = AES_ECB(key, zeros(16))  // static keystream — same for every block
for each 16-byte block:
    ciphertext_block = plaintext_block XOR keystream  // same keystream reused
tail = [0x00, 0x00, checksum_lo, checksum_hi, 0x00, 0x00]
```

Where checksum = `(~sum(plaintext[3...])) & 0xFFFF`

### 6.7 Authentication Handshake

**State Machine:**

```
INITIAL → PRE_COMM → SET_PWD → AUTH → COMM
                       ↑         │
                       └─────────┘  (retry on auth failure)
```

**Phase 1 — PRE_COMM (cmd 0x5B):**

```
Setup:  counter = 0, key = SHA1(bt_name + zeros)
Send:   cmd=0x5B, index=0x00, data=[] to BLE board (0x04)
Receive: 30+ bytes → auth_param(16B) + serial_number(14B ASCII)
         response INDEX: 0 = no stored password, ≠0 = has stored password
Then:   store auth_param, enable SN mode (counter starts at 1)
```

**Phase 2 — SET_PWD (cmd 0x5C):**

```
Setup:  key = SHA1(bt_name + auth_param)
Generate: 16-byte session password using Java LCG PRNG seeded with
          (currentTimeMillis + f(auth_param))
          → SHA-256 of random bytes → first 16 bytes
Send:   cmd=0x5C, index=0x00, data=password(16B) to BLE board (0x04)
Receive: INDEX=1 → accepted, INDEX=0 → waiting for physical button press
Retry:  Every 2s, timeout 60s for user interaction
```

**Password Generation Detail (Java LCG):**

The PRNG uses `java.util.Random` semantics — a 48-bit Linear Congruential Generator:

```
seed = (seed ^ 0x5DEECE66D) & 0xFFFFFFFFFFFF  // mask to 48 bits
next_bits(n) → seed = (seed * 0x5DEECE66D + 0xB) & 0xFFFFFFFFFFFF
               return (seed >> (48 - n))
```

The seed combines `currentTimeMillis()` with a function of auth_param using Java 32-bit int shift semantics (shift amount masked with `& 31`).

This is one of the trickier parts to port to Swift — the Java int overflow and shift behavior must be replicated exactly.

**Phase 3 — AUTH (cmd 0x5D):**

```
Setup:  key = SHA1(password + auth_param)
Send:   cmd=0x5D, index=0x00, data=serial_number(14B) to BLE board (0x04)
Receive: INDEX=1 → authenticated (transition to COMM state)
         INDEX=0 → failed (clear stored password, retry from SET_PWD)
```

**Retry Limits:**

| Phase | Max retries | Timeout per attempt |
|---|---|---|
| PRE_COMM | 10 | 2,000 ms |
| SET_PWD | 30 (60s/2s) | 2,000 ms |
| AUTH | 3 per attempt, 5 restarts from SET_PWD | 2,000 ms |

### 6.8 Password Persistence

After successful AUTH, store the password in iOS Keychain keyed by device serial number. On subsequent connections:

1. Send PRE_COMM as normal (non-SN, counter=0)
2. If response INDEX ≠ 0 → device has stored password
3. Skip SET_PWD entirely
4. Set key = SHA1(stored_password + auth_param)
5. Send AUTH with counter=2 (same counter value as normal flow where SET_PWD would have used counter 2)
6. If AUTH fails → clear stored password, fall back to SET_PWD

**Recovering password from official Segway Mobility app** (one-time, avoids re-pairing):

From an unencrypted iTunes/Finder backup:

```
File: Library/Preferences/com.ninebot.segway.plist
Key:  {SerialNumber}_decrypt
Value: Base64-encoded 16-byte password
```

```bash
sqlite3 Manifest.db "SELECT fileID, relativePath FROM Files
    WHERE domain = 'AppDomain-com.ninebot.segway'
    AND relativePath LIKE '%Preferences%plist'"
plutil -p com.ninebot.segway.plist | grep _decrypt
```

---

## 7. GT3 Register Map & Data Model

### 7.1 Live Telemetry Registers (poll during rides)

These are the registers to poll on a timer (~1–2 Hz) while riding:

| Register | Board | Index | Size | Description | Unit (estimated) |
|---|---|---|---|---|---|
| `rSpeed` | VCU (0x02) | 0x57 | 2B | Current speed | 0.1 km/h (÷10) |
| `rBattery` | VCU (0x02) | 0x55 | 2B | Combined battery % | % |
| `rSingleMileage` | VCU (0x02) | 0x68 | 2B | Current trip distance | 0.01 km (÷100) |
| `rSingleRideTime` | VCU (0x02) | 0x6A | 2B | Current trip time | seconds |
| `rRunningTime` | VCU (0x02) | 0x69 | 2B | Current session running time | seconds |
| `rLeftMileage` | VCU (0x02) | 0x5F | 2B | Estimated remaining range | 0.01 km |
| `rBodyTemp` | VCU (0x02) | 0x6B | 2B | Controller/body temperature | 0.1°C |
| `rGearMode` | VCU (0x02) | 0x5A | 2B | Current riding mode | enum |
| `rErrorCode` | VCU (0x02) | 0x58 | 2B | Active error code | code |
| `rWarnCode` | VCU (0x02) | 0x59 | 2B | Active warning code | code |
| `rBMSVolt` | BMS1 (0x06) | 0x8C | 2B | Battery 1 voltage | 0.01V (÷100) |
| `rBMSCur` | BMS1 (0x06) | 0x8D | 2B | Battery 1 current | 0.01A (signed) |
| `rBmsSOC` | BMS1 (0x06) | 0x8F | 2B | Battery 1 state of charge | % |
| `rBmsTmp` | BMS1 (0x06) | 0x96 | 4B | Battery 1 temperature | 0.1°C |
| `rBMSVolt2` | BMS2 (0x07) | 0x8C | 2B | Battery 2 voltage | 0.01V |
| `rBMSCur2` | BMS2 (0x07) | 0x8D | 2B | Battery 2 current | 0.01A (signed) |
| `rBmsSOC2` | BMS2 (0x07) | 0x8F | 2B | Battery 2 state of charge | % |
| `rBmsTmp2` | BMS2 (0x07) | 0x96 | 4B | Battery 2 temperature | 0.1°C |

### 7.2 Cumulative / Diagnostic Registers (read on connect)

These don't change during a ride — read once per connection:

| Register | Board | Index | Size | Description |
|---|---|---|---|---|
| `rMileage` | VCU (0x02) | 0x62 | 4B | Total odometer |
| `rRuntime` | VCU (0x02) | 0x64 | 4B | Total power-on time |
| `rRideTime` | VCU (0x02) | 0x66 | 4B | Total ride time |
| `rSN` | VCU (0x02) | 0x10 | 14B | Serial number |
| `rCtrlV` | VCU (0x02) | 0x17 | 2B | Controller firmware version |
| `rMCUV` | VCU (0x02) | 0x18 | 2B | MCU firmware version |
| `rBmsV` | VCU (0x02) | 0x19 | 2B | BMS1 firmware version |
| `rBms2V` | VCU (0x02) | 0x1A | 2B | BMS2 firmware version |
| `rBleV` | BLE (0x04) | 0x01 | 2B | BLE firmware version |
| `rBmsCycleCountLT` | BMS1 (0x06) | 0x59 | 2B | Battery 1 charge cycles |
| `rBms2CycleCountLT` | BMS2 (0x07) | 0x59 | 2B | Battery 2 charge cycles |
| `rBmsEnergyThroughputLT` | BMS1 (0x06) | 0xE3 | 4B | Battery 1 total energy throughput |
| `rBms2EnergyThroughputLT` | BMS2 (0x07) | 0xE3 | 4B | Battery 2 total energy throughput |
| `rBmsCapacityThroughputLT` | BMS1 (0x06) | 0xE1 | 4B | Battery 1 total capacity throughput |
| `rBms2CapacityThroughputLT` | BMS2 (0x07) | 0xE1 | 4B | Battery 2 total capacity throughput |
| `rBmsDeepDischargeCountLT` | BMS1 (0x06) | 0x89 | 2B | Battery 1 deep discharge count |
| `rBms2DeepDischargeCountLT` | BMS2 (0x07) | 0x89 | 2B | Battery 2 deep discharge count |
| `rBmsRemainCapacityLT` | BMS1 (0x06) | 0x8A | 2B | Battery 1 remaining capacity |
| `rBms2RemainCapacityLT` | BMS2 (0x07) | 0x8A | 2B | Battery 2 remaining capacity |
| `rBmsManufactureDateLT` | BMS1 (0x06) | 0x0A | 2B | Battery 1 manufacture date |
| `rBms2ManufactureDateLT` | BMS2 (0x07) | 0x0A | 2B | Battery 2 manufacture date |
| `rBmsExtremeUseTimeLT` | BMS1 (0x06) | 0xF5 | 4B | Battery 1 extreme use time |
| `rBmsExtremeChargeTimeLT` | BMS1 (0x06) | 0xF7 | 4B | Battery 1 extreme charge time |
| `rBatterySN` | BMS1 (0x06) | 0x02 | 14B | Battery 1 serial number |
| `rBatterySN2` | BMS2 (0x07) | 0x02 | 14B | Battery 2 serial number |
| `rChargeStatus` | BMS1 (0x06) | 0x92 | 4B | Charging status |
| `rTimeFull` | BMS1 (0x06) | 0x94 | 2B | Time to full charge |
| `rPN` | VCU (0x02) | 0x20 | varies | Part number |
| `rPreciseMileage` | VCU (0x02) | 0x5E | 2B | High-precision mileage |

### 7.3 Additional Registers (also captured)

> **Note**: All §7.3 registers are captured during rides, not just the §7.1/§7.2 registers. The app captures everything the scooter exposes.

| Register | Board | Index | Description |
|---|---|---|---|
| `rGearED` | VCU | 0x47 | Energy recovery / regen braking level |
| `rGearSR` | VCU | 0x48 | Speed response level |
| `rLedMode` | VCU | 0x5B | Current LED mode |
| `rProjectionLightMode` | VCU | 0x5C | Projection light mode |
| `rTailLightMode` | VCU | 0x5D | Tail light mode |
| `rAlarmLevel` | VCU | 0x74 | Alarm sensitivity level |
| `rBumpyRoad` | VCU | 0x75 | Bumpy road mode setting |
| `rVoiceVolume` | VCU | 0x76 | Speaker volume |
| `rBmsCellVolFrequence` | BMS1 | 0xA0 | Individual cell voltages (26B) |
| `rBmsTempFrequence` | BMS1 | 0x96 | Temperature sensor array (16B) |
| `rMaxPower` | BMS1 | 0x82 | Max power setting |
| `rBmsCapacity` | BMS1 | 0x13 | Battery design capacity |
| `rFindMyStatus` | BLE | 0x1D | Apple Find My integration status |
| `rFindMyEnable` | BLE | 0x20 | Find My enabled flag |

### 7.4 Data Models

```swift
struct TelemetrySample: Codable {
    let timestamp: Date
    let speed: Double           // km/h
    let battery: Int            // combined %
    let bms1Voltage: Double     // V
    let bms1Current: Double     // A (negative = discharging)
    let bms1SOC: Int            // %
    let bms1Temp: Double        // °C
    let bms2Voltage: Double
    let bms2Current: Double
    let bms2SOC: Int
    let bms2Temp: Double
    let tripDistance: Double     // km
    let tripTime: Int           // seconds
    let bodyTemp: Double        // °C
    let gearMode: Int
    let estimatedRange: Double  // km
    let errorCode: Int
    let warnCode: Int

    // GPS (CoreLocation)
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let gpsSpeed: Double?       // m/s from GPS
    let gpsCourse: Double?      // degrees
    let horizontalAccuracy: Double?

    // Surface quality (CoreMotion)
    let roughnessScore: Double? // CoreMotion RMS

    // Health (Apple Watch)
    let heartRate: Int?         // from Apple Watch
}

struct RideLog: Codable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let samples: [TelemetrySample]
    let totalDistance: Double
    let maxSpeed: Double
    let avgSpeed: Double
    let batteryUsed: Int        // % consumed
    let startBattery: Int
    let endBattery: Int
    let uploaded: Bool
}

struct ScooterSnapshot: Codable {
    let timestamp: Date
    let serialNumber: String
    let odometer: Double        // total km
    let totalRuntime: Int       // seconds
    let totalRideTime: Int      // seconds
    let bms1CycleCount: Int
    let bms2CycleCount: Int
    let bms1EnergyThroughput: Int
    let bms2EnergyThroughput: Int
    let bms1DeepDischargeCount: Int
    let bms2DeepDischargeCount: Int
    let controllerFW: String
    let mcuFW: String
    let bms1FW: String
    let bms2FW: String
    let bleFW: String
}
```

---

## 8. Live Activity & Dynamic Island

### 8.1 ActivityKit Integration

The Live Activity is managed by a separate Widget Extension target. It uses `ActivityKit` to start, update, and end activities from the main app.

**Activity Attributes:**

```swift
struct GT3RideAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        let speed: Double           // km/h
        let battery: Int            // %
        let tripDistance: Double     // km
        let estimatedRange: Double  // km
        let gearMode: Int
        let bms1Temp: Double        // °C
        let bms2Temp: Double
        let isCharging: Bool
    }

    let scooterName: String
    let startTime: Date
}
```

### 8.2 Dynamic Island Layouts

**Compact (minimal pill):**

```
┌─────────────────────────────────┐
│  ⚡ 72 km/h        🔋 85%      │
└─────────────────────────────────┘
```

**Expanded (long-press):**

```
┌─────────────────────────────────────┐
│  GT3 Pro                  ⚡ Sport  │
│                                     │
│     72 km/h           🔋 85%       │
│                                     │
│  Trip: 12.4 km    Range: 38 km     │
│  Time: 00:24:15   Temp: 42°C      │
└─────────────────────────────────────┘
```

**Lock Screen banner (same data as expanded).**

### 8.3 Lifecycle

| Event | Action |
|---|---|
| BLE connected + speed > 0 | Start Live Activity |
| BLE connected + speed == 0 + was riding | Keep Live Activity (stopped at light, etc.) |
| BLE connected + charging detected | Start charging Live Activity variant |
| BLE disconnected | End Live Activity after 30s grace period, show ride summary |
| App terminated by iOS | Live Activity persists (last known state), ends after stale timeout |

**Update frequency**: Push content state updates every ~2 seconds from the BLE polling loop. ActivityKit throttles updates internally so this is safe.

### 8.4 Automatic Start

The Live Activity should start automatically when the app connects to the scooter — including from background wake. The user should never need to manually trigger it. The flow:

1. iOS wakes app via BLE state restoration or background scan
2. App authenticates with GT3 Pro
3. App reads initial telemetry
4. App starts Live Activity with initial state
5. App begins polling loop, updating Live Activity each cycle

---

## 9. Background Sync

### 9.1 Background BLE Capabilities

With the `bluetooth-central` background mode enabled:

- **All Core Bluetooth delegate callbacks fire in background** — whether the user is on the home screen, in another app, or the device is locked.
- **Connection requests never time out** — call `connectPeripheral` once and iOS watches indefinitely for the device.
- **State Restoration** — if iOS terminates the app for memory, it saves BLE state and relaunches the app when the peripheral reappears, restoring the `CBCentralManager` and `CBPeripheral` objects.
- **Live Activity provides additional execution time** — iOS is more generous with background CPU when a Live Activity is active.

### 9.2 Background Sync Flow

```
Phone in pocket, GT3 powers on
           │
           ▼
iOS detects BLE advertisement
           │
           ▼
App wakes in background (state restoration)
           │
           ▼
Connect → Authenticate (PRE_COMM → AUTH with stored password)
           │
           ▼
Read cumulative registers (odometer, battery health, etc.)
           │
           ▼
Start Live Activity (Dynamic Island appears)
           │
           ▼
Begin polling loop (speed, battery, trip data)
           │
           ▼
Upload snapshot + telemetry over cellular
           │
           ▼
[Ride continues... polling + Live Activity updates]
           │
           ▼
GT3 powers off → BLE disconnects
           │
           ▼
End Live Activity → finalize ride log → upload ride log
           │
           ▼
Re-issue connectPeripheral (iOS watches for next power-on)
           │
           ▼
App goes back to sleep
```

### 9.3 Handling iOS Background Limitations

- **Polling frequency may be throttled in background**: Aim for 1-2 Hz in foreground, accept that iOS may reduce this in background. Log timestamps with each sample so gaps are visible.
- **If iOS terminates the app mid-ride**: The ride log is incomplete but whatever was persisted to SwiftData survives. On next launch, detect orphaned ride and finalize it with last known data.
- **Battery impact**: BLE is inherently low-power. Polling a few registers every 1-2s is comparable to a heart rate monitor app. The Live Activity itself adds minimal overhead.

---

## 10. Data Upload & Server Integration

### 10.1 Target Infrastructure

Data flows to the existing FluxHaus monitoring stack via the fluxhaus-server API (not directly to InfluxDB):

```
GT3 Companion ── HTTPS POST ──► fluxhaus-server
                                      │
                          ┌───────────┴───────────┐
                          │                       │
                          ▼                       ▼
                    PostgreSQL              InfluxDB
                 (ride metadata,         (time-series
                  GPS tracks,            telemetry)
                  health data)                │
                          │                   ▼
                          │              Grafana
                          │          (GT3 Dashboard)
                          └──────────────►│
```

**Endpoint**: `https://fluxhaus.io/api/gt3/` (fluxhaus-server REST API).

**Authentication**: OIDC — same `AuthManager` as the FluxHaus iOS app. The GT3 Companion authenticates using the shared OIDC provider and includes the bearer token in all API requests.

### 10.2 API Endpoints

```
POST /api/gt3/telemetry      — batch of TelemetrySample records
POST /api/gt3/rides           — completed ride log with GPS track
POST /api/gt3/snapshots       — scooter cumulative snapshot
GET  /api/gt3/rides           — list past rides
GET  /api/gt3/rides/:id       — single ride detail
GET  /api/gt3/analytics       — aggregate stats
```

### 10.3 Data Points

The fluxhaus-server writes time-series data to InfluxDB in line protocol format:

```
# Live telemetry (per sample, written by server to InfluxDB)
gt3_telemetry,scooter=GT3Pro speed=72.3,battery=85i,bms1_voltage=58.42,bms1_current=-12.3,bms1_soc=86i,bms1_temp=38.2,bms2_voltage=58.10,bms2_current=-11.8,bms2_soc=84i,bms2_temp=37.5,trip_distance=12.4,trip_time=1455i,body_temp=42.1,gear_mode=3i,range_estimate=38.2,error_code=0i,warn_code=0i,latitude=43.6532,longitude=-79.3832,altitude=76.0,gps_speed=20.1,roughness=0.42,heart_rate=128i {timestamp_ns}

# Cumulative snapshot (per connection, written by server to InfluxDB)
gt3_snapshot,scooter=GT3Pro odometer=1234.5,total_runtime=86400i,total_ride_time=43200i,bms1_cycles=42i,bms2_cycles=41i,bms1_energy_throughput=98765i,bms2_energy_throughput=97654i,bms1_deep_discharge=2i,bms2_deep_discharge=1i {timestamp_ns}

# Ride summary (per ride, written by server to InfluxDB)
gt3_ride,scooter=GT3Pro,ride_id={uuid} distance=12.4,max_speed=78.2,avg_speed=42.1,battery_used=34i,start_battery=95i,end_battery=61i,duration=1455i {timestamp_ns}
```

Ride metadata, GPS tracks, and health data are stored in PostgreSQL by the server (see §10.6).

### 10.4 Upload Strategy

- **Telemetry samples**: Batch into groups of 50–100 and POST to fluxhaus-server periodically (every 30–60s) during a ride. Server writes to InfluxDB.
- **Snapshots**: Upload immediately on connection.
- **Ride summaries**: Upload when ride ends (BLE disconnect). Includes full GPS track and health data as JSON.
- **Offline queue**: If upload fails (no connectivity), queue in SwiftData. Retry on next app wake with exponential backoff.
- **Background URLSession**: Use `URLSessionConfiguration.background` for uploads that survive app termination.

### 10.5 Authentication Flow

```
1. App launches → AuthManager checks for valid OIDC token
2. If expired → refresh via OIDC provider (same as FluxHaus app)
3. All API requests include: Authorization: Bearer {access_token}
4. Server validates token, extracts user_sub for data ownership
```

The OIDC configuration (issuer, client ID, scopes) is shared with the FluxHaus iOS app. Keychain items are shared via a shared app group if both apps are installed.

### 10.6 Server PostgreSQL Schema

The fluxhaus-server stores structured ride data in PostgreSQL alongside the time-series data in InfluxDB:

```sql
CREATE TABLE gt3_rides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_sub TEXT NOT NULL,
  start_time TIMESTAMPTZ NOT NULL,
  end_time TIMESTAMPTZ,
  distance DOUBLE PRECISION,
  max_speed DOUBLE PRECISION,
  avg_speed DOUBLE PRECISION,
  battery_used INTEGER,
  start_battery INTEGER,
  end_battery INTEGER,
  gps_track JSONB,
  health_data JSONB,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE gt3_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_sub TEXT NOT NULL,
  serial_number TEXT NOT NULL,
  odometer DOUBLE PRECISION,
  total_runtime INTEGER,
  total_ride_time INTEGER,
  bms1_cycle_count INTEGER,
  bms2_cycle_count INTEGER,
  firmware_versions JSONB,
  settings JSONB,
  timestamp TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

**`gps_track` JSONB format:**

```json
{
  "coordinates": [
    {"lat": 43.6532, "lon": -79.3832, "alt": 76.0, "ts": "2025-01-15T14:30:00Z", "speed": 20.1, "course": 180.5, "accuracy": 5.0},
    ...
  ],
  "bounding_box": {"min_lat": 43.65, "max_lat": 43.68, "min_lon": -79.40, "max_lon": -79.37}
}
```

**`health_data` JSONB format:**

```json
{
  "avg_heart_rate": 128,
  "max_heart_rate": 162,
  "calories": 245.5,
  "hr_zones": {"zone1": 120, "zone2": 480, "zone3": 300, "zone4": 60, "zone5": 0},
  "samples": [
    {"ts": "2025-01-15T14:30:00Z", "hr": 128},
    ...
  ]
}
```

---

## 11. Local Persistence

### 11.1 SwiftData Models

```swift
@Model
class PersistedRide {
    var id: UUID
    var startTime: Date
    var endTime: Date?
    var totalDistance: Double
    var maxSpeed: Double
    var avgSpeed: Double
    var batteryUsed: Int
    var startBattery: Int
    var endBattery: Int?
    var uploaded: Bool
    var samples: [PersistedSample]
}

@Model
class PersistedSample {
    var timestamp: Date
    var speed: Double
    var battery: Int
    var bms1Voltage: Double
    var bms1Current: Double
    var bms1SOC: Int
    var bms1Temp: Double
    var bms2Voltage: Double
    var bms2Current: Double
    var bms2SOC: Int
    var bms2Temp: Double
    var tripDistance: Double
    var bodyTemp: Double
    var gearMode: Int
    var estimatedRange: Double
}

@Model
class UploadQueueItem {
    var id: UUID
    var payload: Data       // encoded line protocol or JSON
    var endpoint: String
    var createdAt: Date
    var retryCount: Int
    var lastAttempt: Date?
}

@Model
class StoredCredential {
    var serialNumber: String
    var password: Data       // 16 bytes — also stored in Keychain as primary
    var btName: String
    var lastConnected: Date
}
```

### 11.2 Keychain Storage

Sensitive items stored in iOS Keychain (not SwiftData):

- OIDC tokens (access token, refresh token)
- Scooter pairing password (16 bytes, keyed by serial number)

---

## 12. UI Design

### 12.1 Main Views

The in-app UI is secondary to the Live Activity — most interaction happens via Dynamic Island. But the app needs:

**Dashboard View (main screen) — three context-aware modes:**

- **Riding mode** (glanceable): Large speed, battery %, trip distance, estimated range. Minimal chrome for quick glances while stopped at lights. Turn-by-turn navigation overlay when active.
- **Parked mode** (full status): Connection status, dual battery gauges (BMS1 + BMS2 voltage, SOC, temp), gear mode, detailed scooter status, charging progress when plugged in.
- **Disconnected mode** (history/planning): Ride history, route planning, analytics, scooter last-known status.

**Ride History View:**
- List of past rides with date, distance, duration, battery used
- Tap for detail: speed graph over time, battery drain curve, GPS route on map

**Ride Data Explorer:**
- Timeline scrubber synced to map position and telemetry charts
- Scrub through ride → map pin moves, charts highlight, surface roughness shown
- Speed, power, battery, temperature, heart rate charts
- GPS route colored by speed / roughness / heart rate

**Aggregate Analytics View:**
- Trends over time (distance per week/month, battery health degradation)
- Battery health tracking (cycle counts, capacity fade)
- Heatmap of frequently ridden routes
- Personal records (fastest speed, longest ride, most distance in a day)
- Efficiency metrics (Wh/km trends)

**Turn-by-Turn Navigation View:**
- Search for destinations via MapKit
- Route preview with estimated time/distance
- Active navigation with voice/haptic guidance
- Glanceable next-turn banner integrated with riding mode

**Scooter Info View:**
- Serial number, firmware versions
- Odometer, total ride time
- Battery health (cycle counts, capacity, deep discharge counts)
- Charge status

**Settings View:**
- Server endpoint configuration
- Polling frequency
- Live Activity preferences
- Re-pair / forget scooter
- Export ride data (CSV/JSON)
- Navigation preferences (voice, haptics)

### 12.2 Design Language — Catppuccin Theming

The app uses the [Catppuccin](https://catppuccin.com) color palette, matching the design system used across FluxHaus and Rhizome apps. Reference `Theme.swift` from FluxHaus/Rhizome for the shared implementation pattern.

**Palette:**

| Mode | Catppuccin Flavor | Base | Surface | Text |
|---|---|---|---|---|
| Light | Latte | `#eff1f5` | `#ccd0da` | `#4c4f69` |
| Dark (primary) | Mocha | `#1e1e2e` | `#313244` | `#cdd6f4` |

**Accent Colors (differentiated from FluxHaus):**

| Role | Color | Hex (Mocha) |
|---|---|---|
| Primary | Sky | `#89dceb` |
| Secondary | Sapphire | `#74c7ec` |
| Success | Green | `#a6e3a1` |
| Warning | Yellow | `#f9e2af` |
| Error | Red | `#f38ba8` |

> FluxHaus uses Peach/Mauve as primary accents; GT3 Companion uses Sky/Sapphire to visually distinguish the apps while maintaining the shared Catppuccin foundation.

**Typography:**

- **Headers**: New York (serif) — matches FluxHaus/Rhizome pattern
- **Body**: SF Pro (system default)
- **Monospace data** (speeds, voltages): SF Mono

**Button Style:**

`GT3ButtonStyle` following the same pattern as `FluxHausButtonStyle` / `RhizomeButtonStyle`:
- Catppuccin Surface background with Sky/Sapphire tint
- Rounded corners, consistent padding
- Pressed state with Overlay opacity

**Dark mode primary**: The app defaults to dark mode (Mocha) as the primary experience — matches riding at night and is OLED-friendly for battery savings. Light mode (Latte) is fully supported for daytime use.

**Additional design principles:**
- SF Symbols for icons
- Minimal chrome — data-forward layout
- Color coding: Green (good) → Yellow (caution) → Red (warning) for temps, battery, errors
- Landscape support for handlebar-mounted phone holders

### 12.3 App Icon

Sumi-e (ink wash) brush stroke scooter silhouette on Catppuccin Latte Base (`#eff1f5`) background.

This follows the established icon style across the app family:
- **FluxHaus**: Sumi-e house silhouette
- **Rhizome**: Sumi-e dog silhouette
- **GT3 Companion**: Sumi-e scooter silhouette

The icon uses bold, expressive brush strokes with intentional ink splatter/bleed for an organic, hand-drawn feel. The scooter is rendered in profile view, recognizable at small sizes (home screen, notifications).

---

## 13. First-Time Pairing Flow

### Option A: Fresh Pair (requires physical button press on GT3)

1. App scans for Ninebot BLE devices
2. User selects their GT3 Pro from the list
3. App connects and sends PRE_COMM
4. App sends SET_PWD with generated password
5. GT3 dashboard shows pairing prompt — user presses button on scooter
6. App receives acceptance, sends AUTH
7. Password stored in Keychain
8. Future connections skip SET_PWD

### Option B: Recover Password from Segway Mobility App (no button press needed)

1. User creates an unencrypted backup of their iPhone via Finder
2. App provides a helper utility / instructions to extract the `{serial}_decrypt` key from the backup's plist
3. User pastes the hex password into the app settings
4. App stores it in Keychain
5. On next connection, app skips SET_PWD and goes straight to AUTH

Option B is strongly preferred — it avoids the button press requirement and allows fully hands-free operation from the start.

---

## 14. iOS Configuration & Entitlements

### Info.plist Keys

```xml
<!-- Background BLE + Location -->
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
    <string>location</string>
</array>

<!-- Bluetooth usage descriptions -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>GT3 Companion connects to your Segway GT3 Pro to read ride telemetry and sync data.</string>

<key>NSBluetoothPeripheralUsageDescription</key>
<string>GT3 Companion needs Bluetooth to communicate with your Segway GT3 Pro.</string>

<!-- Location -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>GT3 Companion records your GPS route during rides.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>GT3 Companion needs background location to track rides when your phone is in your pocket.</string>

<!-- Health -->
<key>NSHealthShareUsageDescription</key>
<string>GT3 Companion reads heart rate data from your Apple Watch during rides.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>GT3 Companion saves ride workouts to Apple Health.</string>

<!-- Motion -->
<key>NSMotionUsageDescription</key>
<string>GT3 Companion uses motion sensors to detect road surface quality.</string>

<!-- Live Activity -->
<key>NSSupportsLiveActivities</key>
<true/>
```

### Capabilities

- **Background Modes**: Bluetooth LE accessories (Uses Bluetooth LE accessories), Location updates
- **HealthKit**
- **Keychain Sharing** (if sharing credentials between app and widget extension)

### Signing

Personal Team signing via Xcode for sideloading. Re-sign every 7 days (free) or use Apple Developer Program ($99/yr) for 1-year signing.

---

## 15. Project Structure

```
GT3Companion/
├── GT3Companion.xcodeproj
├── GT3Companion/                       # Main app target
│   ├── App/
│   │   ├── GT3CompanionApp.swift       # @main entry, SwiftData container setup
│   │   └── AppDelegate.swift           # State restoration handling
│   ├── BLE/
│   │   ├── ScooterConnectionManager.swift  # CBCentralManager actor
│   │   ├── NinebotTransport.swift          # Frame codec, fragmentation, reassembly
│   │   ├── NinebotFrameBuilder.swift       # Build read/write command frames
│   │   └── BLEConstants.swift              # UUIDs, board IDs, timeouts
│   ├── Crypto/
│   │   ├── NinebotCrypto.swift             # Encrypt/decrypt engine
│   │   ├── NinebotAuth.swift               # 3-phase handshake state machine
│   │   ├── KeyDerivation.swift             # SHA-1 key derivation
│   │   ├── JavaLCG.swift                   # Java Random PRNG port for SET_PWD
│   │   └── AESHelper.swift                 # Single-block AES-128-ECB via CommonCrypto
│   ├── Data/
│   │   ├── RegisterReader.swift            # High-level register read orchestration
│   │   ├── GT3Registers.swift              # Register definitions (board, index, size)
│   │   ├── TelemetryParser.swift           # Raw bytes → typed values
│   │   ├── RideTracker.swift               # Ride start/stop detection, sample collection
│   │   └── Models/
│   │       ├── TelemetrySample.swift
│   │       ├── RideLog.swift
│   │       ├── ScooterSnapshot.swift
│   │       └── SwiftDataModels.swift       # @Model persistence classes
│   ├── Navigation/
│   │   ├── NavigationManager.swift         # MapKit turn-by-turn navigation
│   │   └── RouteSearchView.swift           # Destination search UI
│   ├── Health/
│   │   ├── WatchConnectivityManager.swift  # WCSession phone-side relay
│   │   └── HealthKitManager.swift          # HealthKit read/write on phone
│   ├── Upload/
│   │   ├── FluxHausAPIClient.swift         # Server API client (replaces direct InfluxDB)
│   │   ├── UploadQueue.swift               # Offline queue with retry
│   │   └── BackgroundUploader.swift        # URLSession background config
│   ├── Views/
│   │   ├── DashboardView.swift
│   │   ├── RideHistoryView.swift
│   │   ├── RideDetailView.swift
│   │   ├── RideExplorerView.swift          # Timeline scrubber + map + charts
│   │   ├── AnalyticsView.swift             # Aggregate trends, heatmap, records
│   │   ├── NavigationView.swift            # Turn-by-turn riding view
│   │   ├── ScooterInfoView.swift
│   │   ├── SettingsView.swift
│   │   ├── OnboardingView.swift            # First-launch permission wizard
│   │   └── Components/
│   │       ├── BatteryGauge.swift
│   │       ├── SpeedDisplay.swift
│   │       ├── ConnectionStatusView.swift
│   │       └── CatppuccinTheme.swift       # Catppuccin color definitions
│   └── Utilities/
│       ├── AuthManager.swift               # OIDC authentication (shared with FluxHaus)
│       ├── KeychainHelper.swift
│       ├── GPSTracker.swift                # CoreLocation wrapper
│       ├── SurfaceRoughnessTracker.swift   # CoreMotion accelerometer RMS
│       └── Logger.swift
├── GT3CompanionWidgets/                # Widget Extension target (Live Activity)
│   ├── GT3RideAttributes.swift         # Shared ActivityAttributes definition
│   ├── GT3LiveActivity.swift           # Dynamic Island + Lock Screen layouts
│   └── GT3CompanionWidgetsBundle.swift
├── GT3CompanionWatch/                  # watchOS app target
│   ├── GT3CompanionWatchApp.swift      # @main entry for Watch app
│   ├── RideWorkoutManager.swift        # HKWorkoutSession + HKLiveWorkoutBuilder
│   ├── WatchRideView.swift             # Ride-in-progress Watch UI
│   └── ComplicationProvider.swift      # Watch face complications
└── Shared/                             # Shared between app and widget extension
    └── GT3RideAttributes.swift         # (if using framework or Swift package)
```

---

## 16. Dependencies

### No third-party dependencies required for core functionality.

| Component | Solution |
|---|---|
| BLE | Core Bluetooth (system framework) |
| Encryption (AES-128-ECB) | CommonCrypto (`CCCrypt`) — system framework |
| SHA-1 | CryptoKit (`Insecure.SHA1`) |
| SHA-256 | CryptoKit (`SHA256`) |
| Keychain | Security framework or small wrapper |
| Live Activity | ActivityKit + WidgetKit (system frameworks) |
| Persistence | SwiftData (system framework) |
| Networking | URLSession (system framework) |
| UI | SwiftUI (system framework) |
| GPS | CoreLocation (system framework) |
| Motion | CoreMotion (system framework) |
| Navigation | MapKit (system framework) |
| Health | HealthKit (system framework) |
| Watch | WatchConnectivity + WatchKit (system frameworks) |

### Optional nice-to-haves:

| Library | Purpose |
|---|---|
| [swift-log](https://github.com/apple/swift-log) | Structured logging |
| Charts (SwiftUI) | Ride detail speed/battery graphs (system framework in iOS 16+) |

---

## 17. Key Risks & Mitigations

### Protocol Compatibility

**Risk**: The GT3 Pro (GT3P) may have slightly different register behavior than the documented GT3. The NootNooot docs are extracted from the app's device config, not live-tested on a GT3 Pro specifically.

**Mitigation**: Start with basic reads (speed, battery, odometer) and verify values make sense. The register map is shared across the GT3 family. Log raw response bytes for debugging.

### Java LCG PRNG Port

**Risk**: The password generation uses Java's `java.util.Random` with exact 32-bit int overflow and shift semantics. Getting this wrong means SET_PWD silently generates the wrong password and AUTH always fails.

**Mitigation**: Write extensive unit tests comparing Swift output against known Java outputs for multiple seeds. Alternatively, recover the password from the Segway Mobility app backup to bypass SET_PWD entirely.

### iOS Background Execution

**Risk**: iOS may terminate the app during rides, interrupting telemetry logging.

**Mitigation**: Live Activity keeps the app alive longer. Persist samples to SwiftData frequently (every few seconds). Detect orphaned rides on next launch. Accept that background telemetry may have gaps.

### iOS Echo Bug on Reconnect

**Risk**: Documented iOS-specific issue where the device echoes back writes instead of processing them after reconnection.

**Mitigation**: Implement echo detection (compare PRE_COMM response to request bytes) and automatic disconnect/reconnect retry with escalating delays (1s, 2s). Up to 3 retries.

### Concurrent BLE Access with Segway Mobility App

**Risk**: If the official Segway Mobility app is also installed and tries to connect, two apps fighting over the same BLE peripheral will cause connection failures.

**Mitigation**: Document that users should force-quit the official app or disable its Bluetooth access in iOS Settings. Only one app can hold the BLE connection at a time.

### Register Value Interpretation

**Risk**: The exact units and scaling factors for register values aren't documented in the protocol spec. Values like `rSpeed` returning `723` probably means 72.3 km/h (÷10), but this is inferred.

**Mitigation**: Connect and read real values at known states (stationary = 0, check odometer against dashboard display) to calibrate. Log raw values alongside parsed values during development.

### MTU Fragmentation

**Risk**: If outgoing frames exceed `MTU - 3` bytes and aren't fragmented, the BLE stack silently truncates and the device never responds.

**Mitigation**: Always fragment writes. After MTU negotiation, store the effective payload size. AUTH frame (27 bytes encrypted) must be split into two writes at default MTU of 23.

---

## 18. Reference Materials

### Protocol Documentation

- **NootNooot BLE Protocol Docs**: https://nootnooot.codeberg.page/segway-ninebot-ble/
- **Source Repository**: https://codeberg.org/NootNooot/segway-ninebot-ble
- **GT3 Command Reference**: https://nootnooot.codeberg.page/segway-ninebot-ble/devices/segway-superscooter-gt3/
- **BLE Transport**: https://nootnooot.codeberg.page/segway-ninebot-ble/transport/
- **Encryption**: https://nootnooot.codeberg.page/segway-ninebot-ble/encryption/
- **Authentication**: https://nootnooot.codeberg.page/segway-ninebot-ble/authentication/
- **Frame Formats**: https://nootnooot.codeberg.page/segway-ninebot-ble/protocol/
- **Python Reference Client**: https://nootnooot.codeberg.page/segway-ninebot-ble/client/

### Other Protocol Work

- **NinebotCrypto (ScooterHacking)**: https://github.com/scooterhacking/NinebotCrypto
- **ninebot-ble (ownbee, HA integration focus)**: https://github.com/ownbee/ninebot-ble
- **etransport/ninebot-docs (legacy protocol wiki)**: https://github.com/etransport/ninebot-docs/wiki/protocol
- **M365-BLE-PROTOCOL (older Xiaomi scooters)**: https://github.com/CamiAlfa/M365-BLE-PROTOCOL

### Apple Documentation

- **Core Bluetooth Background Processing**: https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html
- **ActivityKit (Live Activities)**: https://developer.apple.com/documentation/activitykit
- **CBCentralManager State Restoration**: https://developer.apple.com/documentation/corebluetooth/cbcentralmanager

### Implementation Guides

- **Background Bluetooth Best Practices (Punch Through)**: https://punchthrough.com/leveraging-background-bluetooth-for-a-great-user-experience/
- **Background BLE on iOS (Atomic Object)**: https://spin.atomicobject.com/bluetooth-ios-app/

---

## 19. First-Launch Onboarding

### Sequential Permission Wizard

On first launch, the app presents a sequential onboarding flow that requests permissions one at a time, following Apple Human Interface Guidelines. Each permission is preceded by a **pre-permission explanation screen** that describes why the permission is needed before the system dialog appears.

### Permission Sequence

**Step 1 — Bluetooth (required)**

> *"GT3 Companion connects to your Segway GT3 Pro over Bluetooth to read speed, battery, and ride data in real time."*

- This is the only **required** permission. Without Bluetooth, the app cannot function.
- If denied, show a persistent banner explaining how to enable Bluetooth in Settings.
- Triggers `CBCentralManager` initialization → system Bluetooth permission dialog.

**Step 2 — Location When In Use → Always**

> *"GT3 Companion records your GPS route during rides so you can see where you've been and explore ride data on a map."*

- First request: When In Use (lower friction).
- After the user completes their first ride, prompt to upgrade to **Always** with explanation:

> *"To track rides when your phone is in your pocket or the app is in the background, GT3 Companion needs 'Always' location access. Your location is only recorded during active rides — never at other times."*

- If denied, GPS fields in telemetry samples are `nil`. Rides still work without GPS.

**Step 3 — HealthKit (optional)**

> *"If you have an Apple Watch, GT3 Companion can record your heart rate and calories during rides — like a cycling workout."*

- Only shown if a paired Apple Watch is detected (`WCSession.default.isPaired`).
- Requests read access to heart rate and write access to workouts.
- If declined, rides proceed without health data.

**Step 4 — Motion & Fitness (optional)**

> *"GT3 Companion uses your phone's motion sensors to detect road surface quality — bumpy roads, smooth pavement, and everything in between."*

- Requests `CMMotionActivityManager` authorization.
- If declined, `roughnessScore` is `nil` in telemetry samples.

**Step 5 — Notifications (optional)**

> *"GT3 Companion can notify you about ride summaries, charging complete, and connection events."*

- Standard `UNUserNotificationCenter` request.
- If declined, the app still functions — Live Activity provides the primary notification surface.

### Design Principles

- **One permission per screen** — never stack multiple system dialogs.
- **Pre-permission screens use the app's Catppuccin theme** with clear illustrations.
- **"Skip" / "Not Now" option** on all optional permissions (steps 3–5).
- **No dark patterns** — clearly label which permissions are required vs. optional.
- **Permissions can be changed later** in the app's Settings view, which deep-links to iOS Settings when needed.
- **Progressive disclosure** — Location Always is requested after the first ride, not during onboarding, so the user understands the context.

---

## 20. Apple Watch Integration

### Architecture

The phone is the BLE hub — it maintains the connection to the GT3 Pro and runs all protocol/crypto logic. The Apple Watch serves as a health sensor and wrist-mounted display.

```
┌──────────────┐     WatchConnectivity      ┌──────────────┐
│   iPhone     │ ◄─────────────────────────► │ Apple Watch  │
│              │                              │              │
│ ScooterConn- │  phone → watch:             │ RideWorkout- │
│ ectionMgr    │   • speed, battery, trip    │ Manager      │
│ (BLE → GT3)  │   • ride state (start/stop) │ (HKWorkout-  │
│              │   • navigation cues          │  Session)    │
│ WatchConn-   │                              │              │
│ ectivity-    │  watch → phone:             │ WatchRide-   │
│ Manager      │   • heart rate              │ View         │
│              │   • calories                │              │
│              │   • workout state           │ Complication- │
│              │                              │ Provider     │
└──────────────┘                              └──────────────┘
```

### WatchConnectivity Relay

The `WatchConnectivityManager` on the phone side uses `WCSession` to bridge data:

**Phone → Watch (live context updates):**
- `updateApplicationContext(_:)` for latest telemetry snapshot (speed, battery, trip distance, ride state)
- Sent every ~2s during a ride, matching the BLE polling cadence
- Watch uses this to update its ride-in-progress UI

**Watch → Phone (health data stream):**
- `sendMessage(_:replyHandler:)` for real-time heart rate samples
- Heart rate is merged into the phone's `TelemetrySample` as `heartRate` field
- `transferUserInfo(_:)` for workout summary when ride ends

### HKWorkoutSession

The Watch app runs an `HKWorkoutSession` with `HKLiveWorkoutBuilder` during rides:

```swift
let configuration = HKWorkoutConfiguration()
configuration.activityType = .cycling  // closest to e-scooter
configuration.locationType = .outdoor

let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
let builder = session.associatedWorkoutBuilder()
builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
```

**Tracked metrics:**
- **Heart rate** — continuous via `HKQuantityType.heartRate`, streamed to phone in real time
- **Active calories** — `HKQuantityType.activeEnergyBurned`
- **Heart rate zones** — computed from user's max HR (220 - age or manually set):
  - Zone 1 (50–60%): Very light
  - Zone 2 (60–70%): Light
  - Zone 3 (70–80%): Moderate
  - Zone 4 (80–90%): Hard
  - Zone 5 (90–100%): Maximum

### Watch Ride-in-Progress UI

**WatchRideView** shows a compact, glanceable ride display:

```
┌─────────────────┐
│    72 km/h      │  ← large speed
│                 │
│  🔋 85%  ♥ 128 │  ← battery + heart rate
│  12.4 km        │  ← trip distance
│                 │
│  Zone 3 ████░░  │  ← HR zone indicator
└─────────────────┘
```

- Green/yellow/red tint based on battery level
- Heart rate zone color coding
- Haptic tap on navigation turns (if navigation active)
- Always-on display support for quick wrist glances

### Complications

`ComplicationProvider` offers Watch face complications:

| Family | Content |
|---|---|
| Circular | Battery % ring |
| Rectangular | Speed + battery + trip |
| Inline | "72 km/h • 85%" |
| Corner | Battery gauge |

Complications show last-known data when not riding, and live data during rides via `CLKComplicationDataSource` with timeline entries.

### Workout Persistence

When a ride ends:

1. Watch finalizes `HKWorkoutSession` → `HKLiveWorkoutBuilder.endCollection()`
2. Builder saves workout to Apple Health with:
   - Activity type: `.cycling`
   - Duration matching ride duration
   - Heart rate samples
   - Calorie data
   - Route (from phone GPS via `HKWorkoutRouteBuilder`)
3. Workout summary sent to phone via `transferUserInfo`
4. Phone includes health data in the ride upload to fluxhaus-server

The workout appears in Apple Health / Fitness app alongside other workouts, with the full GPS route visible on the map.

---

## Appendix A: Quick-Start Development Plan

### Phase 1: Crypto & Auth (week 1-2)

1. Port `AESHelper.swift` — single-block AES-128-ECB via CommonCrypto
2. Port `KeyDerivation.swift` — SHA-1 based key derivation
3. Port `NinebotCrypto.swift` — encrypt/decrypt (non-SN and SN modes)
4. Port `JavaLCG.swift` — Java Random PRNG for password generation
5. Write unit tests against known test vectors from the Python reference client
6. Implement `NinebotAuth.swift` — 3-phase handshake state machine

### Phase 2: BLE Transport (week 2-3)

1. Implement `ScooterConnectionManager.swift` — scan, connect, discover services
2. Implement `NinebotTransport.swift` — frame building, fragmentation, reassembly
3. Integrate crypto layer
4. Test: connect to real GT3 Pro, complete auth handshake, read one register
5. Implement iOS bonded device workarounds (CCCD toggle, stale drain, echo detection)

### Phase 3: Register Reading & Data (week 3-4)

1. Define `GT3Registers.swift` with all register addresses and metadata
2. Implement `RegisterReader.swift` — sequential register read orchestration
3. Implement `TelemetryParser.swift` — raw bytes to typed values
4. Calibrate units by reading known values (speed=0, odometer vs dashboard)
5. Implement `RideTracker.swift` — ride start/stop detection

### Phase 4: Live Activity (week 4-5)

1. Create Widget Extension target
2. Define `GT3RideAttributes` shared between app and widget
3. Build Dynamic Island compact and expanded layouts
4. Build Lock Screen layout
5. Wire up ActivityKit start/update/end to BLE connection events
6. Test automatic Live Activity start from background wake

### Phase 5: Upload & Polish (week 5-6)

1. Implement `FluxHausAPIClient.swift` — server API client with OIDC auth
2. Implement `UploadQueue.swift` — offline queue with retry
3. Implement background URLSession upload
4. Build SwiftUI views (dashboard, ride history, settings)
5. Set up Grafana dashboard for GT3 data
6. Local persistence with SwiftData
7. End-to-end test: power on scooter → auto-connect → Live Activity → ride → upload → Grafana

### Phase 6: GPS, Navigation & Watch (week 6-8)

1. Implement `GPSTracker.swift` — CoreLocation at 1-2 Hz
2. Implement `SurfaceRoughnessTracker.swift` — CoreMotion accelerometer RMS
3. Implement `NavigationManager.swift` — MapKit turn-by-turn
4. Build Watch app target with `RideWorkoutManager.swift`
5. Implement `WatchConnectivityManager.swift` — phone ↔ Watch relay
6. Build ride explorer view with timeline scrubber
7. Build aggregate analytics views
8. Implement first-launch onboarding wizard
9. End-to-end test: ride with GPS + Watch HR → upload → explore in app

---

## Appendix B: Wire Protocol Quick Reference

### Read Register Command

```
Plaintext: [5A A5 LEN 3E TARGET_ID 01 INDEX 02]
                              │     │   │     └─ read 2 bytes
                              │     │   └─ register address
                              │     └─ cmd_read (0x01)
                              └─ board target
```

### Read Register Response

```
Plaintext: [5A A5 LEN 3E SOURCE_ID 04 INDEX DATA...]
                               │      │   │    └─ register value bytes
                               │      │   └─ register address
                               │      └─ cmd_readACK (0x04)
                               └─ responding board
```

### Encrypted Frame Structure

```
Outbound:  [HDR 3B] [encrypted payload] [MAC 4B] [counter 2B]
Inbound:   [HDR 3B] [encrypted payload] [MAC 4B] [counter 2B]

HDR = [0x5A] [0xB5] [LEN]  ← note: 0xB5 not 0xA5 in encrypted frames
```
