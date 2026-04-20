# Privacy Policy

**GT3 Companion**
*Last updated: April 19, 2026*

GT3 Companion is an open-source app for the Segway SuperScooter GT3 Pro. This policy explains what data the app collects, how it is used, and how you can control it.

## Data We Collect

### Scooter Telemetry

When connected to your GT3 Pro via Bluetooth, the app reads:

- Speed, battery level, estimated range, and gear mode
- Battery voltage, current, temperature, and state of charge
- Body temperature and BMS cell voltages
- Trip distance, trip time, and odometer
- Firmware versions, serial number, and error/warning codes

This data is used to display the live dashboard, record rides, and monitor scooter health.

### Location Data

The app records GPS coordinates (latitude, longitude, altitude, speed, course, and accuracy) **only during active rides**. Location data is used to:

- Display your route on a map
- Calculate ride distance and speed
- Export routes as GPX files

Location is collected in the background while a ride is in progress so tracking continues if you switch apps. The app does not track your location when you are not riding.

### Motion Data

The app uses your device's accelerometer to measure surface roughness during rides. This data is used to estimate road surface quality and is recorded alongside ride telemetry.

### Heart Rate and Health Data

If you use the Apple Watch companion, the app records heart rate during rides via HealthKit. Ride workouts (cycling type) and active energy burned are saved to Apple Health. Health data is:

- Stored locally on your device and in Apple Health
- Uploaded to your server **only** if you have cloud sync enabled
- Never shared with third parties

### Weather Data

The app may fetch current weather conditions (temperature, humidity, wind, UV index) via Apple WeatherKit during rides. Weather data is associated with your ride and is not used for any other purpose.

## Data Storage

### On-Device

All ride data, telemetry samples, GPS tracks, and preferences are stored locally on your device using SwiftData. You can delete all local data from **Settings → Data → Clear Local Data**.

### Cloud Sync (Optional)

If you sign in with a FluxHaus account, ride data and telemetry are uploaded to your self-hosted [FluxHaus Server](https://github.com/djensenius/FluxHaus-Server) instance. By default this is `api.fluxhaus.io`, but you can configure the app to point to your own server.

- Data is transmitted over HTTPS
- Authentication uses OIDC (OpenID Connect) with PKCE
- Your data is associated with your account and stored in your server's PostgreSQL and InfluxDB databases
- **You control the server** — data retention and access are entirely up to you

The app works fully offline without a server. Cloud sync is opt-in.

## Data We Do Not Collect

- We do not collect analytics or usage telemetry
- We do not use advertising SDKs or trackers
- We do not sell, rent, or share your data with third parties
- We do not collect your name, email, or personal information (your FluxHaus account is managed by your own server)

## Third-Party Services

| Service | Purpose | Data Shared |
|---------|---------|-------------|
| Apple HealthKit | Heart rate and workout tracking | Read/write heart rate and workouts (stays in Apple Health) |
| Apple WeatherKit | Weather conditions during rides | Location for weather lookup (Apple's privacy policy applies) |
| Apple MapKit | Map display and navigation | Map tile requests (Apple's privacy policy applies) |
| Your FluxHaus Server | Cloud sync (optional, self-hosted) | Ride data, telemetry, GPS tracks |

No data is sent to Segway, Ninebot, or any other third party.

## Bluetooth

The app connects to your GT3 Pro over Bluetooth Low Energy. The BLE connection is used exclusively for reading scooter telemetry and sending commands (e.g., power on/off). No data is shared with other Bluetooth devices.

## Push Notifications

If you enable Live Activities, the app may register a push token with your FluxHaus Server for push-to-start functionality. The token is stored only on your server.

## Children's Privacy

GT3 Companion is not directed at children under 13 and does not knowingly collect data from children.

## Your Rights

- **Delete local data**: Settings → Data → Clear Local Data
- **Delete cloud data**: Manage directly on your self-hosted FluxHaus Server
- **Revoke permissions**: Disable Bluetooth, Location, Motion, or Health access in iOS Settings at any time
- **Export your data**: Use the GPX export feature for ride routes

## Changes to This Policy

Updates to this policy will be posted in this repository. The "Last updated" date at the top indicates the most recent revision.

## Contact

For questions about this privacy policy, please [open an issue](https://github.com/djensenius/gt3pro/issues) on GitHub.

## Open Source

GT3 Companion is open source under the Apache 2.0 license. You can review exactly what data the app collects by reading the [source code](https://github.com/djensenius/gt3pro).
