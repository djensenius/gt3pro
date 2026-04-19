//
//  WeatherDebugView.swift
//  GT3Companion
//
//  Debug view for testing weather functionality.
//

import CoreLocation
import SwiftUI
@preconcurrency import WeatherKit

// swiftlint:disable type_body_length
struct WeatherDebugView: View {
    @State private var snapshot: WeatherSnapshot?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastFetchDate: Date?
    @State private var rawWeather: CurrentWeather?
    @State private var availabilityStatus: String?

    // Default to Toronto; editable
    @State private var latitudeText = "43.6532"
    @State private var longitudeText = "-79.3832"

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.large) {
                    headerSection
                    coordinateInput
                    availabilityButton
                    if let status = availabilityStatus {
                        availabilityBanner(status)
                    }
                    fetchButton
                    if let error = errorMessage {
                        errorBanner(error)
                    }
                    if let snap = snapshot {
                        snapshotCard(snap)
                        symbolTestGrid(snap)
                        rawValuesSection(snap)
                    }
                    symbolMapSection
                }
                .padding()
            }
        }
        .navigationTitle("Weather Debug")
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.small) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 32))
                .foregroundStyle(Theme.Colors.warning)
            Text("Weather Debug Tool")
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Test WeatherKit integration & symbol mapping")
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
            #if targetEnvironment(simulator)
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Running on Simulator — WeatherKit typically fails here with JWT errors. Test on a real device.")
            }
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Colors.warning)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Theme.Colors.warning.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            #endif
        }
        .padding(.top)
    }

    // MARK: - Coordinate Input

    private var coordinateInput: some View {
        VStack(spacing: Theme.Spacing.small) {
            Text("Location")
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Theme.Spacing.medium) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Latitude")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    TextField("Lat", text: $latitudeText)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Longitude")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    TextField("Lon", text: $longitudeText)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                }
            }

            // Quick location presets
            HStack(spacing: Theme.Spacing.small) {
                presetButton("Toronto", lat: "43.6532", lon: "-79.3832")
                presetButton("NYC", lat: "40.7128", lon: "-74.0060")
                presetButton("London", lat: "51.5074", lon: "-0.1278")
                presetButton("Tokyo", lat: "35.6762", lon: "139.6503")
            }
        }
        .padding()
        .background(Theme.Colors.elevatedBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    private func presetButton(_ label: String, lat: String, lon: String) -> some View {
        Button {
            latitudeText = lat
            longitudeText = lon
        } label: {
            Text(label)
                .font(Theme.Fonts.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.Colors.accent.opacity(0.15))
                .foregroundStyle(Theme.Colors.accent)
                .clipShape(Capsule())
        }
    }

    // MARK: - Availability Check

    private var availabilityButton: some View {
        Button {
            Task { await checkAvailability() }
        } label: {
            HStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.shield.fill")
                }
                Text(isLoading ? "Checking…" : "Check Availability")
            }
            .font(Theme.Fonts.bodyMedium)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Theme.Colors.accent.opacity(0.7))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .disabled(isLoading)
    }

    private func availabilityBanner(_ status: String) -> some View {
        HStack(alignment: .top) {
            Image(systemName: status.hasPrefix("✅") ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(status.hasPrefix("✅") ? Theme.Colors.success : Theme.Colors.warning)
            Text(status)
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (status.hasPrefix("✅") ? Theme.Colors.success : Theme.Colors.warning).opacity(0.1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    // MARK: - Fetch Button

    private var fetchButton: some View {
        Button {
            Task { await fetchWeather() }
        } label: {
            HStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "cloud.sun.fill")
                }
                Text(isLoading ? "Fetching…" : "Fetch Weather")
            }
            .font(Theme.Fonts.bodyMedium)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Theme.Colors.accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .disabled(isLoading)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Colors.error)
            Text(message)
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.error)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.error.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    // MARK: - Snapshot Card (mirrors RideDetailView weather section)

    private func snapshotCard(_ snap: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                Text("Current Weather")
                    .font(Theme.Fonts.headerLarge())
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                if let date = lastFetchDate {
                    Text(date, style: .time)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            VStack(spacing: Theme.Spacing.medium) {
                HStack(spacing: Theme.Spacing.large) {
                    Image(systemName: snap.conditionSymbol)
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(width: 50)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(snap.condition.capitalized)
                            .font(Theme.Fonts.bodyMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(String(format: "%.1f°C", snap.temp))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(String(format: "Feels like %.1f°C", snap.feelsLike))
                            .font(Theme.Fonts.bodySmall)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                }

                HStack(spacing: Theme.Spacing.medium) {
                    weatherDetail(
                        icon: "humidity.fill", label: "Humidity",
                        value: String(format: "%.0f%%", snap.humidity)
                    )
                    weatherDetail(
                        icon: "wind", label: "Wind",
                        value: String(format: "%.1f km/h", snap.windSpeed)
                    )
                    weatherDetail(icon: "sun.max.fill", label: "UV", value: String(format: "%.0f", snap.uvIndex))
                    weatherDetail(
                        icon: "gauge.with.dots.needle.33percent",
                        label: "Pressure",
                        value: String(format: "%.0f hPa", snap.pressure)
                    )
                }

                WeatherAttributionView()
            }
            .padding()
            .background(Theme.Colors.elevatedBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
    }

    // MARK: - Symbol Test Grid

    private func symbolTestGrid(_ snap: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("Symbol Mapping Test")
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)

            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                symbolRow("WeatherKit symbol", snap.conditionSymbol)
                symbolRow("weatherSymbol(for:)", weatherSymbol(for: snap.condition))
                let matches = snap.conditionSymbol == weatherSymbol(for: snap.condition)
                symbolRow("Match?", matches ? "✅ Yes" : "⚠️ Different")
            }
            .padding()
            .background(Theme.Colors.elevatedBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
    }

    private func symbolRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 160, alignment: .leading)
            if value.contains("✅") || value.contains("⚠️") {
                Text(value)
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
            } else {
                Image(systemName: value)
                    .foregroundStyle(Theme.Colors.accent)
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            Spacer()
        }
    }

    // MARK: - Raw Values

    private func rawValuesSection(_ snap: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("Raw Values")
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)

            VStack(spacing: 6) {
                rawRow("temp", String(format: "%.2f", snap.temp))
                rawRow("feelsLike", String(format: "%.2f", snap.feelsLike))
                rawRow("humidity", String(format: "%.2f", snap.humidity))
                rawRow("windSpeed", String(format: "%.2f", snap.windSpeed))
                rawRow("windDirection", String(format: "%.2f°", snap.windDirection))
                rawRow("condition", snap.condition)
                rawRow("conditionSymbol", snap.conditionSymbol)
                rawRow("uvIndex", String(format: "%.1f", snap.uvIndex))
                rawRow("pressure", String(format: "%.2f", snap.pressure))
            }
            .padding()
            .background(Theme.Colors.elevatedBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
    }

    private func rawRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
        }
    }

    // MARK: - Symbol Map Section

    private var symbolMapSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("weatherSymbol(for:) Coverage")
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)

            let conditions = [
                "Clear", "Sunny", "Partly Cloudy", "Mostly Clear",
                "Cloudy", "Overcast", "Rain", "Drizzle", "Shower",
                "Thunderstorm", "Snow", "Sleet", "Flurries",
                "Fog", "Haze", "Mist", "Windy", "Breezy", "Unknown"
            ]

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                ForEach(conditions, id: \.self) { condition in
                    VStack(spacing: 4) {
                        Image(systemName: weatherSymbol(for: condition))
                            .font(.title2)
                            .foregroundStyle(Theme.Colors.accent)
                        Text(condition)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.Colors.elevatedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Helpers

    private func weatherDetail(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(Theme.Colors.accent)
            Text(value)
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func fetchWeather() async {
        guard let lat = Double(latitudeText),
              let lon = Double(longitudeText) else {
            errorMessage = "Invalid coordinates"
            return
        }

        isLoading = true
        errorMessage = nil

        let location = CLLocation(latitude: lat, longitude: lon)

        // Match FluxHaus pattern: new instance instead of .shared
        do {
            let service = WeatherKit.WeatherService()
            // Use full weather request (not subset) — matches working FluxHaus pattern
            let weather = try await service.weather(for: location)
            let current = weather.currentWeather
            snapshot = WeatherSnapshot(
                temp: current.temperature.converted(to: .celsius).value,
                feelsLike: current.apparentTemperature.converted(to: .celsius).value,
                humidity: current.humidity * 100,
                windSpeed: current.wind.speed.converted(to: .kilometersPerHour).value,
                windDirection: current.wind.direction.converted(to: .degrees).value,
                condition: current.condition.description,
                conditionSymbol: current.symbolName,
                uvIndex: Double(current.uvIndex.value),
                pressure: current.pressure.converted(to: .hectopascals).value
            )
        } catch {
            errorMessage = """
            \(String(describing: type(of: error))): \(error.localizedDescription)

            Full error: \(error)
            """
        }

        isLoading = false
        lastFetchDate = Date()
    }

    private func checkAvailability() async {
        isLoading = true
        errorMessage = nil

        let location = CLLocation(
            latitude: Double(latitudeText) ?? 43.6532,
            longitude: Double(longitudeText) ?? -79.3832
        )
        let service = WeatherKit.WeatherService()

        do {
            // Lightweight probe — full weather request to verify auth works
            _ = try await service.weather(for: location)
            availabilityStatus = "✅ WeatherKit authorized and responding"
        } catch {
            availabilityStatus = """
            ❌ \(String(describing: type(of: error)))
            \(error.localizedDescription)

            Full: \(error)

            Checklist:
            • App ID has WeatherKit capability in Apple Developer Portal
            • Provisioning profile is regenerated after enabling
            • Device is signed into iCloud
            • Running on a real device (simulator can fail)
            """
        }

        isLoading = false
    }
}
// swiftlint:enable type_body_length

#Preview {
    NavigationStack {
        WeatherDebugView()
    }
}
