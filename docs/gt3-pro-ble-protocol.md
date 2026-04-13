# Segway GT3 Pro — Bluetooth Low Energy Protocol Reference

> **Scooter model**: Segway SuperScooter GT3 Pro (x3 series)

> Reverse-engineered from Bluetooth packet captures, the Segway Mobility app, and the
> [segway-ninebot-ble](https://nootnooot.codeberg.page/segway-ninebot-ble/) community docs.

---

## Table of Contents

1. [BLE Connection](#1-ble-connection)
2. [Frame Format](#2-frame-format)
3. [Encryption (Enc2)](#3-encryption-enc2)
4. [Authentication Handshake](#4-authentication-handshake)
5. [Board Addresses](#5-board-addresses)
6. [Commands](#6-commands)
7. [Register Map](#7-register-map)
8. [Data Parsing](#8-data-parsing)
9. [Power Control](#9-power-control)
10. [Practical Notes & Gotchas](#10-practical-notes--gotchas)

---

## 1. BLE Connection

### Service & Characteristic UUIDs

| Role | UUID |
|------|------|
| **Ninebot Service** | `6E400001-0000-0000-006E-696E65626F74` |
| Legacy UART Service | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` |

| Characteristic | UUID Suffix | Direction | Purpose |
|----------------|-------------|-----------|---------|
| Write | `0002` | App → Device | Primary data channel |
| RCTP Write | `0003` | App → Device | Candidate auth channel |
| **Notify** | **`0004`** | Device → App | **Primary data channel** |
| Auth Write | `0005` | App → Device | Authentication writes |
| Auth Notify | `0006` | Device → App | Authentication responses |
| Legacy Write | `B5A3-0002` | App → Device | Legacy UART write |
| Legacy Notify | `B5A3-0003` | Device → App | Legacy UART notify |

> **⚠️ The notify characteristic is `0004`, NOT `0003`.** This is the single most common
> source of connection bugs.

### Connection Flow

```
1.  Create CBCentralManager (restore key: "GT3CompanionCentral")
2.  Scan by advertised name/prefix OR service UUID
    └─ Also check retrieveConnectedPeripherals + saved peripheral UUID
3.  Connect to peripheral
4.  Negotiate MTU = maximumWriteValueLength(for: .withResponse) + 3
5.  Discover both services (Ninebot + Legacy UART)
6.  Subscribe to characteristics
7.  Toggle CCCD on 006E-0004:
    ├─ Disable notifications
    ├─ Wait 300 ms
    ├─ Re-enable notifications
    └─ Wait 200 ms drain period
8.  Begin authentication handshake (see §4)
9.  On success, persist peripheral UUID for reconnection
```

### Auth Gating

Authentication does not begin until **all three** characteristics are discovered:
- Ninebot write char (`0002`)
- Ninebot notify char (`0004`)
- Legacy UART notify char (`B5A3-0003`)

### State Restoration (iOS Background)

On `willRestoreState`, the app retrieves the previously-connected peripheral and
re-initiates service discovery → characteristic subscription → authentication.

---

## 2. Frame Format

### Plain Frame (Protocol 2)

```
Offset  Bytes  Field
──────  ─────  ─────────────────────
 0      2      Header: 5A A5
 2      1      LEN (payload byte count)
 3      1      Source: 0x3E (phone)
 4      1      Target board address
 5      1      Command byte
 6      1      Index (register address)
 7      LEN-4  Data payload
 N      2      Checksum (little-endian, appended by sendFramePlain)
```

`LEN` = total bytes from Source through end of Data (i.e., `data.count`, the "data-only" length).

### Frame Size Rules

| Mode | Total frame size |
|------|-----------------|
| Plain (old) | `LEN + 3` |
| Plain (GT3 Pro) | `LEN + 7` |
| Encrypted (SN mode) | `LEN + 13` (includes MAC + counter) |

### Checksum

```
checksum = ~(sum of all bytes from Source through Data) & 0xFFFF
```

Appended as two bytes, little-endian.

---

## 3. Encryption (Enc2)

The GT3 Pro uses "Encryption2" — a custom CCM-like scheme built on AES-128.
Encrypted frames keep the **`5A A5`** header (not `5A B5`).

### Key Derivation

```
function deriveKey(input1, input2) → [UInt8]:
    padded1 = input1 padded/truncated to 16 bytes
    padded2 = input2 padded/truncated to 16 bytes
    combined = padded1 + padded2          // 32 bytes
    hash = SHA-1(combined)                // 20 bytes
    return hash[0..<16]                   // first 16 bytes
```

### AES Helper

Single-block **AES-128-ECB** via CommonCrypto. Used as a building block for CTR
keystream generation and CBC-MAC computation.

### The `dataBasic` Constant

A hardcoded 16-byte IV used in non-SN mode encryption:

```
97 CF B8 02 84 41 43 DE 56 00 2B 3B 34 78 0A 5D
```

### Non-SN Mode (counter == 0)

Used **only** for the initial PRE_COMM exchange before the crypto counter is established.

```
1.  keystream = AES_ECB(key, dataBasic)
2.  ciphertext = plaintext XOR keystream
3.  checksum = ~sum(plaintext) & 0xFFFF
4.  tail = [0x00, 0x00, checksum_lo, checksum_hi, 0x00, 0x00]
5.  output = ciphertext + tail
```

The same keystream is used for both encryption and decryption (XOR is its own inverse).

### SN Mode (counter > 0)

Full AES-128-CTR + CBC-MAC after authentication is established.

#### Nonce Construction (13 bytes)

```
Offset  Bytes  Value
──────  ─────  ─────────────────────────────
 0      2      0x00 0x00
 2      1      counter high byte (big-endian)
 3      1      counter low byte  (big-endian)
 4      8      authParam[0..7]
12      1      0x00
```

#### CTR Encryption

```
For each 16-byte block i (starting at i=1):
    A_i = [0x01] + nonce(13) + [0x00, block_index]
    keystream_i = AES_ECB(key, A_i)
    ciphertext_block = plaintext_block XOR keystream_i
```

#### CBC-MAC (Authentication Tag)

```
1.  B_0 = [0x59] + nonce(13) + [0x00, payload_length]
2.  X_1 = AES_ECB(key, B_0)

3.  AAD block = "5A A5 LEN" zero-padded to 16 bytes
4.  X_2 = AES_ECB(key, X_1 XOR AAD)

5.  For each plaintext block:
        X_{n+1} = AES_ECB(key, X_n XOR plaintext_block)

6.  tag = X_final[0..<4]   (truncated to 4 bytes)

7.  A_0 = [0x01] + nonce(13) + [0x00, 0x00]
8.  encrypted_tag = tag XOR AES_ECB(key, A_0)[0..<4]
```

#### Encrypted Frame Layout

```
[5A A5 LEN] [encrypted_payload] [encrypted_tag (4B)] [counter_hi counter_lo]
```

The counter increments by 1 after each encrypted frame sent.

### Verified Example

```
Device name:  03GGG2539C0023
Derived key:  41 33 25 79 46 7D 81 48 52 F1 22 B6 2B C8 84 11
PRE_COMM encrypted payload: A7 E4 A6 99 00 00 62 FF 00 00
```

---

## 4. Authentication Handshake

Three-phase handshake to establish an encrypted session.

```
┌──────────┐                        ┌──────────┐
│   App    │                        │  GT3 Pro │
└────┬─────┘                        └────┬─────┘
     │                                   │
     │ ── PRE_COMM (cmd 0x5B) ────────→  │  Phase 1: Exchange params
     │ ←── authParam[16] + serial[14] ── │
     │                                   │
     │ ── SET_PWD (cmd 0x5C) ─────────→  │  Phase 2: Set password
     │     (may require button press)    │
     │ ←── index=1 (accepted) ────────── │
     │                                   │
     │ ── AUTH (cmd 0x5D) ────────────→  │  Phase 3: Authenticate
     │     serial number (14B ASCII)     │
     │ ←── index=1 (authenticated) ───── │
     │                                   │
     │  ✓ Encrypted session established  │
```

### Phase 1: PRE_COMM

| Field | Value |
|-------|-------|
| Target | MCU (`0x04`) |
| Command | `0x5B` |
| Index | `0x00` |
| Key | `SHA-1(btName + dataBasic)[0:16]` |
| Crypto mode | Non-SN (counter = 0) |

**Response** (≥ 30 bytes):
- Bytes 0–15: `authParam` (16 bytes, used in all subsequent key derivation)
- Bytes 16–29: `serial` (14 bytes, ASCII serial number)
- Response `index`: `0` = no stored password, `≠ 0` = device has a stored password

**Echo detection**: If the PRE_COMM response exactly equals the request, the device
is echoing. Disconnect and retry.

### Phase 2: SET_PWD

Only executed if the device has no stored password (or stored password auth fails).

| Field | Value |
|-------|-------|
| Target | MCU (`0x04`) |
| Command | `0x5C` |
| Key | `SHA-1(btName + authParam)[0:16]` |
| Payload | Generated password (16 bytes) |

#### Password Generation (Java LCG PRNG)

The password is generated using a port of `java.util.Random` — the exact Java LCG
must be replicated:

```
Seed initialization:
    raw_seed = authParam[0] << 24 | authParam[1] << 16 | authParam[2] << 8 | authParam[3]
    seed = (raw_seed ^ 0x5DEECE66D) & 0xFFFFFFFFFFFF   (48-bit mask)

Next value:
    seed = (seed × 0x5DEECE66D + 0xB) & 0xFFFFFFFFFFFF
    return seed >> (48 - bits)                           // Java right-shift semantics
```

**Password derivation:**

```
1.  Create JavaLCG with seed from authParam[0..3]
2.  Generate 16 random bytes via nextInt()
3.  raw_password = SHA-256(random_bytes)
4.  password = raw_password[0..<16]        // first 16 bytes
```

**Response:**
- `index = 1`: Password accepted
- `index = 0`: Waiting for physical button press on scooter
  - Retry up to 30 times with delay

The password is stored in the iOS Keychain for future connections.

### Phase 3: AUTH

| Field | Value |
|-------|-------|
| Target | MCU (`0x04`) |
| Command | `0x5D` |
| Key | `SHA-1(password + authParam)[0:16]` |
| Payload | Serial number (14 bytes ASCII) |
| Crypto counter | Set to `2` before sending |

**Response:**
- `index = 1`: Authenticated ✓ — encrypted session is now established
- `index ≠ 1`: Auth failed — clear stored password, fall back to SET_PWD

### Reconnection (Stored Password)

If the app has a stored password AND the device reports it has one (`PRE_COMM index ≠ 0`):

```
1.  Skip SET_PWD entirely
2.  key = SHA-1(stored_password + authParam)[0:16]
3.  Set crypto counter = 2
4.  Send AUTH with serial number
```

---

## 5. Board Addresses

The GT3 Pro (x3 series) uses **non-standard** board addresses compared to generic
Ninebot scooters.

| Board | GT3 Pro Address | Generic Ninebot | Notes |
|-------|:---------:|:--------:|-------|
| BLE Controller | `0x21` | `0x21` | Same |
| VCU (Vehicle Control Unit) | **`0x16`** | `0x02` | ⚠️ Different! |
| MCU (Motor Control Unit) | **`0x04`** | `0x05` | ⚠️ Different! Auth target |
| BMS1 | `0x06` | `0x06` | Same |
| BMS2 | `0x07` | `0x07` | Same |
| TFT Display | `0x09` | `0x09` | Same |

> **The MCU address `0x04` is also the BLE controller in generic docs.** On the GT3 Pro,
> authentication targets `0x04` (MCU), while the BLE board for firmware version queries is `0x21`.

The source address for all frames sent from the phone is `0x3E`.

---

## 6. Commands

### Command Bytes

| Command | Byte | Description |
|---------|:----:|-------------|
| READ | `0x01` | Read register(s) |
| WRITE | `0x03` | Write register(s) (no response) |
| READ_ACK | `0x04` | Response to READ |
| WRITE_ACK | `0x05` | Response to WRITE |
| PRE_COMM | `0x5B` | Phase 1 authentication |
| SET_PWD | `0x5C` | Phase 2 password setup |
| AUTH | `0x5D` | Phase 3 authentication |
| ACC_CMD | `0x79` | Power control (on/off) |

### Building a Read Request

```
Header:  5A A5
LEN:     calculated
Source:  3E
Target:  board address (e.g., 0x16 for VCU)
Command: 01 (READ)
Index:   register address
Data:    [size] (number of bytes to read)
```

### Building a Write Request

```
Header:  5A A5
LEN:     calculated
Source:  3E
Target:  board address
Command: 03 (WRITE)
Index:   register address
Data:    value bytes (little-endian)
```

---

## 7. Register Map

### Live Telemetry Registers

| Register | Board | Address | Size | Unit | Conversion |
|----------|:-----:|:-------:|:----:|------|------------|
| `rSpeed` | VCU `0x16` | `0x57` | 2 | km/h | `raw ÷ 10` |
| `rBattery` | VCU `0x16` | `0x55` | 2 | % | direct |
| `rSingleMileage` | VCU `0x16` | `0x68` | 2 | km | `raw ÷ 100` |
| `rSingleRideTime` | VCU `0x16` | `0x6A` | 2 | sec | direct |
| `rRunningTime` | VCU `0x16` | `0x69` | 2 | sec | direct |
| `rLeftMileage` | VCU `0x16` | `0x5F` | 2 | km | `raw ÷ 100` |
| `rBodyTemp` | VCU `0x16` | `0x6B` | 2 | °C | `raw ÷ 10` |
| `rGearMode` | VCU `0x16` | `0x5A` | 2 | — | direct |
| `rErrorCode` | VCU `0x16` | `0x58` | 2 | — | direct |
| `rWarnCode` | VCU `0x16` | `0x59` | 2 | — | direct |
| `rBool` | VCU `0x16` | `0x1C` | 2 | — | bitfield (see below) |
| `rGearED` | VCU `0x16` | `0x47` | 2 | — | direct |
| `rGearSR` | VCU `0x16` | `0x48` | 2 | — | direct |

### BMS Registers (Battery Pack 2)

| Register | Board | Address | Size | Unit | Conversion |
|----------|:-----:|:-------:|:----:|------|------------|
| `rBMSVolt2` | BMS2 `0x07` | `0x8C` | 2 | V | `raw ÷ 100` |
| `rBMSCur2` | BMS2 `0x07` | `0x8D` | 2 | A | `signed raw ÷ 100` |
| `rBmsSOC2` | BMS2 `0x07` | `0x8F` | 2 | % | direct |
| `rBmsTmp2` | BMS2 `0x07` | `0x96` | 4 | °C | avg of 2 temp sensors |
| `rChargeStatus` | BMS2 `0x07` | `0x92` | 4 | — | direct |
| `rTimeFull` | BMS2 `0x07` | `0x94` | 2 | — | direct |

> **GT3 Pro note**: The GT3 Pro has a single battery pack addressed as BMS2 (`0x07`).
> The app duplicates BMS2 values into BMS1 fields for compatibility.

### Cumulative / Diagnostic Registers

| Register | Board | Address | Size | Description |
|----------|:-----:|:-------:|:----:|-------------|
| `rMileage` | VCU `0x16` | `0x62` | 4 | Total odometer (`÷ 100` km) |
| `rPreciseMileage` | VCU `0x16` | `0x5E` | 4 | Precise odometer (`÷ 1000` km) |
| `rRuntime` | VCU `0x16` | `0x64` | 4 | Total runtime (sec) |
| `rRideTime` | VCU `0x16` | `0x66` | 4 | Total ride time (sec) |
| `rSN` | VCU `0x16` | `0x10` | 14 | Serial number (ASCII) |
| `rPN` | VCU `0x16` | `0x20` | — | Part number |

### Firmware Version Registers

| Register | Board | Address | Size |
|----------|:-----:|:-------:|:----:|
| `rCtrlV` | VCU `0x16` | `0x17` | 2 |
| `rMCUV` | VCU `0x16` | `0x18` | 2 |
| `rBmsV` | VCU `0x16` | `0x19` | 2 |
| `rBms2V` | VCU `0x16` | `0x1A` | 2 |
| `rBleV` | BLE `0x21` | `0x01` | 2 |

### Settings Registers

| Register | Board | Address | Size | Description |
|----------|:-----:|:-------:|:----:|-------------|
| `rLedMode` | VCU `0x16` | `0x5B` | 2 | LED mode |
| `rProjectionLightMode` | VCU `0x16` | `0x5C` | 2 | Projection light |
| `rTailLightMode` | VCU `0x16` | `0x5D` | 2 | Tail light mode |
| `rAlarmLevel` | VCU `0x16` | `0x74` | 2 | Alarm sensitivity |
| `rBumpyRoad` | VCU `0x16` | `0x75` | 2 | Bumpy road mode |
| `rVoiceVolume` | VCU `0x16` | `0x76` | 2 | Voice volume |
| `rMaxPower` | VCU `0x16` | `0x82` | 2 | Max power setting |
| `rFindMyStatus` | BLE `0x21` | `0x1D` | 2 | Find My status |
| `rFindMyEnable` | BLE `0x21` | `0x20` | 2 | Find My enable |

### BMS Lifetime / Diagnostic Registers

| Register | Board | Address | Size | Description |
|----------|:-----:|:-------:|:----:|-------------|
| `rBms2CycleCountLT` | BMS2 | `0x59` | 2 | Charge cycle count |
| `rBms2EnergyThroughputLT` | BMS2 | `0xE3` | 4 | Energy throughput |
| `rBms2CapacityThroughputLT` | BMS2 | `0xE1` | 4 | Capacity throughput |
| `rBms2DeepDischargeCountLT` | BMS2 | `0x89` | 2 | Deep discharge count |
| `rBms2RemainCapacityLT` | BMS2 | `0x8A` | 2 | Remaining capacity |
| `rBms2ManufactureDateLT` | BMS2 | `0x0A` | 4 | Manufacture date |
| `rBatterySN2` | BMS2 | `0x02` | 14 | Battery serial number |
| `rBmsCapacity` | BMS2 | `0x13` | 2 | Battery capacity |
| `rBmsExtremeUseTimeLT` | BMS2 | `0xF5` | 4 | Extreme use time |
| `rBmsExtremeChargeTimeLT` | BMS2 | `0xF7` | 4 | Extreme charge time |
| `rBmsCellVolFrequence` | BMS2 | `0xA0` | — | Cell voltage frequency |
| `rBmsTempFrequence` | BMS2 | `0x96` | — | Temperature frequency |

### rBool Bitfield (VCU 0x1C)

| Bit | Mask | Meaning |
|:---:|:----:|---------|
| 0 | `0x01` | Powered on |
| 5 | `0x20` | Standby mode |

---

## 8. Data Parsing

All multi-byte register values are **little-endian**.

### Parsing Rules

```swift
// UInt16 (unsigned)
let value = UInt16(data[0]) | (UInt16(data[1]) << 8)

// Int16 (signed, for current)
let raw = UInt16(data[0]) | (UInt16(data[1]) << 8)
let signedValue = Int16(bitPattern: raw)

// UInt32
let value32 = UInt32(data[0]) |
    (UInt32(data[1]) << 8) |
    (UInt32(data[2]) << 16) |
    (UInt32(data[3]) << 24)
```

### Conversion Table

| Type | Formula | Example |
|------|---------|---------|
| Speed | `raw ÷ 10` | `425` → `42.5 km/h` |
| Voltage | `raw ÷ 100` | `6120` → `61.20 V` |
| Current | `signed(raw) ÷ 100` | `65436` → `-1.00 A` |
| Temperature | `raw ÷ 10` | `352` → `35.2 °C` |
| Distance | `raw ÷ 100` | `1234` → `12.34 km` |
| Precise Distance | `raw ÷ 1000` | `12345` → `12.345 km` |
| Percentage | direct | `85` → `85%` |
| Time | direct (seconds) | `3600` → `3600 sec` |
| BMS Temp (4-byte) | average of 2 sensors | `(temp1 + temp2) ÷ 2` |

### Data Flow

```
GT3 Pro BLE Notification
    ↓
ScooterPeripheralDelegate (decrypt + reassemble frames)
    ↓
AppCoordinator.didReceiveTelemetry()
    ↓
RegisterReader.processResponse() → parse register → update snapshot
    ↓
TelemetryParser (apply conversion formulas)
    ↓
Upload to fluxhaus-server (batched samples)
```

---

## 9. Power Control

Power commands use command byte `0x79` (ACC_CMD) targeting the VCU (`0x16`).

### Power On

```
Target:  VCU (0x16)
Command: 0x79
Index:   0x00
Data:    [0x01, 0x00]
```

### Power Off

```
Target:  VCU (0x16)
Command: 0x79
Index:   0x00
Data:    [0x02, 0x00]
```

Both commands are **fire-and-forget** — no ACK is expected.

Power state is detected via the `rBool` register (VCU `0x1C`):
- `bit 0 (0x01)` = powered on
- `bit 5 (0x20)` = standby mode

Observed `rBool` transitions during a power cycle:
```
Powered:  2098 (0x0832) — bit 0 set
Standby:  2065 (0x0811) — bit 5 set
Off→On:   2098 → 2065 → 2067 → 2098
```

> **Note**: Battery percentage never drops to 0 on power-off — the scooter's BMS
> continues reporting.

---

## 10. Practical Notes & Gotchas

### Connection Reliability

- **CCCD toggle is mandatory** after reconnect: disable notifications → wait 300ms →
  re-enable → wait 200ms drain before starting auth.
- **Only one app can hold the BLE connection.** Force-quit the Segway Mobility app
  before connecting with GT3 Companion.
- **Echo detection**: If the PRE_COMM response is identical to the request, the device
  is in a bad state. Disconnect and retry.

### Frame Encoding

- GT3 Pro always uses the `5A A5` header, even for encrypted frames. The `5A B5`
  header seen in generic Ninebot docs is for other scooter models.
- Frame counter bytes in the encrypted tail are **big-endian** (unlike the little-endian
  register data).

### Polling Strategy

The app polls ~58 registers at 1–2 Hz during a ride:
1. Speed frame triggers sample emission
2. Each sample pulls the latest BMS, temperature, gear, and GPS values
3. Samples are persisted to SwiftData every few seconds
4. Batched uploads to the server happen periodically

### Background Execution

- Live Activity (ActivityKit) helps keep the app alive in background
- Persist samples to SwiftData frequently to survive backgrounding
- Detect orphaned rides on launch and finalize them

### Button Press Requirement

During initial pairing (`SET_PWD`), the scooter may require a physical button press
to accept the new password. The app retries up to 30 times while waiting for the user
to press the button.

---

## References

- [segway-ninebot-ble](https://nootnooot.codeberg.page/segway-ninebot-ble/) — Community BLE protocol documentation
- [Codeberg source](https://codeberg.org/NootNooot/segway-ninebot-ble) — Transport, encryption, auth, 8693 commands for 66 models
- GT3 Companion source — `GT3Companion/BLE/`, `GT3Companion/Crypto/`, `GT3Companion/Data/`
