//
//  AppCoordinator+Samples.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if os(iOS)
import CoreLocation

// MARK: - Sample Emission & GPS Distance

extension AppCoordinator {
    func emitSample() async {
        let gpsSample = gpsTracker.latestSample
        let roughness = roughnessTracker.latestSample

        // Accumulate GPS distance via haversine
        if let gpsSample, let lat = Optional(gpsSample.latitude), let lon = Optional(gpsSample.longitude),
           lat != 0, lon != 0, gpsSample.horizontalAccuracy > 0, gpsSample.horizontalAccuracy < 50 {
            if let prev = lastGPSCoord {
                gpsAccumulatedDistance += haversineDistance(
                    lat1: prev.lat, lon1: prev.lon, lat2: lat, lon2: lon
                )
            }
            lastGPSCoord = (lat, lon)
        }

        // Prefer GPS distance; fall back to scooter register
        let liveTripDistance = gpsAccumulatedDistance > 0 ? gpsAccumulatedDistance : scooterTripDistance
        tripDistance = liveTripDistance

        let sample = TelemetrySample(
            timestamp: Date(),
            speed: currentSpeed,
            battery: currentBattery,
            bmsVoltage: await registerReader.getTelemetryDouble("rBMSVolt2") ?? 0,
            bmsCurrent: await registerReader.getTelemetryDouble("rBMSCur2") ?? 0,
            bmsSOC: await registerReader.getTelemetryInt("rBmsSOC2") ?? 0,
            bmsTemp: await registerReader.getTelemetryDouble("rBmsTmp2") ?? 0,
            tripDistance: liveTripDistance,
            tripTime: await registerReader.getTelemetryInt("rSingleRideTime") ?? 0,
            bodyTemp: await registerReader.getTelemetryDouble("rBodyTemp") ?? 0,
            gearMode: await registerReader.getTelemetryInt("rGearMode") ?? 0,
            estimatedRange: estimatedRange,
            errorCode: await registerReader.getTelemetryInt("rErrorCode") ?? 0,
            warnCode: await registerReader.getTelemetryInt("rWarnCode") ?? 0,
            regenLevel: await registerReader.getTelemetryInt("rGearED") ?? 0,
            speedResponse: await registerReader.getTelemetryInt("rGearSR") ?? 0,
            latitude: gpsSample?.latitude,
            longitude: gpsSample?.longitude,
            altitude: gpsSample?.altitude,
            gpsSpeed: gpsSample?.speed,
            gpsCourse: gpsSample?.course,
            horizontalAccuracy: gpsSample?.horizontalAccuracy,
            roughnessScore: roughness?.roughnessScore,
            maxAcceleration: roughness?.maxAcceleration,
            heartRate: watchSession.latestHeartRate > 0 ? watchSession.latestHeartRate : nil
        )

        let wasIdle = await rideTracker.state == .idle
        await rideTracker.addSample(sample)
        let nowRiding = await rideTracker.state == .riding

        if wasIdle && nowRiding {
            isRiding = true
            sendRideStartNotification()
            launchWatchApp()
        }

        await fetchWeatherIfNeeded(gpsSample: gpsSample)
        isRiding = await rideTracker.state != .idle

        await uploadQueue.enqueueSamples([sample])

        watchSession.sendTelemetry(
            speed: currentSpeed,
            battery: currentBattery,
            tripDistance: liveTripDistance,
            range: estimatedRange,
            mode: sample.gearMode
        )

        await liveActivityManager.updateActivity(state: .init(
            speed: currentSpeed,
            battery: currentBattery,
            tripDistance: liveTripDistance,
            estimatedRange: estimatedRange,
            gearMode: sample.gearMode,
            bmsTemp: sample.bmsTemp,
            isCharging: false,
            isAwake: isScooterAwake,
            isConnected: true
        ))
    }

    func sendRideStartNotification() {
        sendNotification(
            title: "Ride Started 🛴",
            body: "GT3 Pro ride logging is active. Battery: \(currentBattery)%"
        )
    }

    private func fetchWeatherIfNeeded(gpsSample: GPSSample?) async {
        let rideState = await rideTracker.state
        guard rideState == .riding || rideState == .stopped else { return }
        let hasWeather = await rideTracker.hasWeather()
        let isFetching = await rideTracker.isFetchingWeather()
        guard !hasWeather, !isFetching else { return }
        guard let gpsSample else {
            Task { @MainActor in
                DebugLogStore.shared.log(
                    "Weather: skipped — no GPS sample yet",
                    category: "Weather",
                    level: .debug
                )
            }
            return
        }

        let location = CLLocation(latitude: gpsSample.latitude, longitude: gpsSample.longitude)
        let rideId = await self.rideTracker.getCurrentRideId()
        await rideTracker.setFetchingWeather(true)
        Task {
            let weather = await WeatherService.shared.fetchWeather(at: location)
            await self.rideTracker.setFetchingWeather(false)
            guard await self.rideTracker.getCurrentRideId() == rideId else { return }
            await self.rideTracker.setWeather(weather)
        }
    }
}

/// Haversine distance between two coordinates in km.
private func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let earthRadius = 6371.0
    let dLat = (lat2 - lat1) * .pi / 180
    let dLon = (lon2 - lon1) * .pi / 180
    let aVal = sin(dLat / 2) * sin(dLat / 2)
        + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
        * sin(dLon / 2) * sin(dLon / 2)
    return earthRadius * 2 * atan2(sqrt(aVal), sqrt(1 - aVal))
}
#endif
