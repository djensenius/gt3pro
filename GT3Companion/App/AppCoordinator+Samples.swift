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
        if let gpsSample,
           gpsSample.latitude != 0, gpsSample.longitude != 0,
           gpsSample.horizontalAccuracy > 0,
           gpsSample.horizontalAccuracy < gpsAccuracyThresholdMetres {
            if let prev = lastGPSCoord {
                gpsAccumulatedDistance += haversineDistanceKm(
                    lat1: prev.lat, lon1: prev.lon,
                    lat2: gpsSample.latitude, lon2: gpsSample.longitude
                )
            }
            lastGPSCoord = (gpsSample.latitude, gpsSample.longitude)
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
        let rideState = await rideTracker.state
        let isCurrentlyMoving = rideState == .riding
        let hasActiveRide = rideState != .idle

        if wasIdle && isCurrentlyMoving {
            isRiding = true
            sendRideStartNotification()
            launchWatchApp()
            watchSession.updateContext(
                battery: currentBattery,
                isConnected: true,
                rideActive: true,
                speed: currentSpeed,
                tripDistance: liveTripDistance,
                range: estimatedRange,
                mode: sample.gearMode
            )
        }

        let wasRiding = !wasIdle
        let rideInactive = !hasActiveRide
        if wasRiding && rideInactive {
            watchSession.updateContext(
                battery: currentBattery,
                isConnected: true,
                rideActive: false,
                speed: 0,
                tripDistance: liveTripDistance,
                range: estimatedRange,
                mode: sample.gearMode
            )
        }

        await fetchWeatherIfNeeded(gpsSample: gpsSample)
        isRiding = hasActiveRide

        await uploadQueue.enqueueSamples([sample])

        watchSession.sendTelemetry(
            speed: currentSpeed,
            battery: currentBattery,
            tripDistance: liveTripDistance,
            range: estimatedRange,
            mode: sample.gearMode,
            rideActive: hasActiveRide
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
        let shouldSkip = await rideTracker.shouldSkipWeatherFetch()
        guard !hasWeather, !isFetching, !shouldSkip else { return }

        // Use GPS sample if available, otherwise fall back to cached location
        let location: CLLocation
        if let gpsSample {
            location = CLLocation(latitude: gpsSample.latitude, longitude: gpsSample.longitude)
        } else if let cached = gpsTracker.lastKnownLocation {
            location = cached
            Task { @MainActor in
                DebugLogStore.shared.log(
                    "Weather: no GPS fix yet, using cached location",
                    category: "Weather",
                    level: .debug
                )
            }
        } else {
            Task { @MainActor in
                DebugLogStore.shared.log(
                    "Weather: skipped — no GPS sample or cached location",
                    category: "Weather",
                    level: .debug
                )
            }
            return
        }

        let rideId = await self.rideTracker.getCurrentRideId()
        await rideTracker.setFetchingWeather(true)
        await rideTracker.recordWeatherAttempt()
        Task { @MainActor in
            DebugLogStore.shared.log(
                "Weather: fetching for (\(String(format: "%.4f", location.coordinate.latitude)), "
                + "\(String(format: "%.4f", location.coordinate.longitude)))",
                category: "Weather"
            )
        }
        Task {
            let weather = await WeatherService.shared.fetchWeather(at: location)
            await self.rideTracker.setFetchingWeather(false)
            guard await self.rideTracker.getCurrentRideId() == rideId else { return }
            if let weather {
                await self.rideTracker.setWeather(weather)
            } else {
                await self.rideTracker.recordWeatherFailure()
            }
        }
    }
}
#endif
