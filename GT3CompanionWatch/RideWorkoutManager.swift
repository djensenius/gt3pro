import HealthKit
import Foundation
import Observation

struct WatchHeartRateSample: Equatable {
    let bpm: Int
    let timestamp: Date
}

@MainActor
protocol RideWorkoutManagerDelegate: AnyObject {
    func rideWorkoutManager(
        _ manager: RideWorkoutManager,
        didCollectHeartRateSample sample: WatchHeartRateSample,
        activeCalories: Double
    )
    func rideWorkoutManager(_ manager: RideWorkoutManager, didUpdateActiveCalories activeCalories: Double)
}

@Observable
class RideWorkoutManager: NSObject {
    @ObservationIgnored
    let healthStore = HKHealthStore()
    @ObservationIgnored
    weak var delegate: RideWorkoutManagerDelegate?
    @ObservationIgnored
    private var session: HKWorkoutSession?
    @ObservationIgnored
    private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored
    private var authorizationInProgress = false
    @ObservationIgnored
    private var authorizationCompletions: [(Bool) -> Void] = []
    @ObservationIgnored
    private var pendingStartConfiguration: HKWorkoutConfiguration?
    @ObservationIgnored
    private var isEndingWorkout = false
    private static let workoutType = HKObjectType.workoutType()

    var heartRate: Double = 0
    var latestHeartRateSample: WatchHeartRateSample?
    var activeCalories: Double = 0
    var isWorkoutActive = false
    var isAuthorizationGranted = false
    var workoutError: String?

    private var isWorkoutAuthorized: Bool {
        healthStore.authorizationStatus(for: Self.workoutType) == .sharingAuthorized
    }

    private func healthKitIsAvailable() -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async {
                self.workoutError = "HealthKit is not available on this device."
                self.isAuthorizationGranted = false
            }
            return false
        }
        return true
    }

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        guard healthKitIsAvailable() else {
            completion?(false)
            return
        }

        if isWorkoutAuthorized {
            DispatchQueue.main.async {
                self.workoutError = nil
                self.isAuthorizationGranted = true
                completion?(true)
            }
            return
        }

        if let completion {
            authorizationCompletions.append(completion)
        }
        guard !authorizationInProgress else { return }
        authorizationInProgress = true

        let typesToShare: Set<HKSampleType> = [
            Self.workoutType,
            HKQuantityType(.activeEnergyBurned)
        ]
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
        ]
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            DispatchQueue.main.async {
                self.authorizationInProgress = false
                let authorized = success && self.isWorkoutAuthorized
                self.isAuthorizationGranted = authorized
                if let error {
                    self.workoutError = "HealthKit authorization failed: \(error.localizedDescription)"
                    print("HealthKit auth error: \(error)")
                } else if !authorized {
                    self.workoutError = "HealthKit workout permission was not granted."
                } else {
                    self.workoutError = nil
                }
                let completions = self.authorizationCompletions
                self.authorizationCompletions.removeAll()
                completions.forEach { $0(authorized) }
            }
        }
    }

    func startWorkout(with configuration: HKWorkoutConfiguration? = nil) {
        guard session == nil, !isEndingWorkout else {
            pendingStartConfiguration = nil
            return
        }
        guard healthKitIsAvailable() else {
            return
        }

        let config = configuration ?? {
            let cfg = HKWorkoutConfiguration()
            cfg.activityType = .cycling
            cfg.locationType = .outdoor
            return cfg
        }()

        guard isWorkoutAuthorized else {
            if authorizationInProgress {
                pendingStartConfiguration = pendingStartConfiguration ?? config
                return
            }
            pendingStartConfiguration = config
            requestAuthorization { [weak self] authorized in
                guard let self, authorized else { return }
                let pending = self.pendingStartConfiguration
                self.pendingStartConfiguration = nil
                self.startWorkout(with: pending)
            }
            return
        }

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            builder = session?.associatedWorkoutBuilder()
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)

            session?.delegate = self
            builder?.delegate = self

            let startDate = Date()
            WatchConnectivityManager.logStartup("Starting HKWorkoutSession")
            session?.startActivity(with: startDate)
            builder?.beginCollection(withStart: startDate) { [weak self] _, error in
                guard let error else { return }
                DispatchQueue.main.async {
                    self?.workoutError = "Workout collection failed: \(error.localizedDescription)"
                }
            }

            DispatchQueue.main.async {
                self.workoutError = nil
                self.isWorkoutActive = true
            }
        } catch {
            DispatchQueue.main.async {
                self.workoutError = "Failed to start workout: \(error.localizedDescription)"
                self.isWorkoutActive = false
                self.session = nil
                self.builder = nil
            }
            print("Failed to start workout: \(error)")
        }
    }

    func endWorkout() {
        guard let session, !isEndingWorkout else {
            return
        }
        isEndingWorkout = true
        WatchConnectivityManager.logStartup("Stopping HKWorkoutSession")
        switch session.state {
        case .running, .paused:
            session.stopActivity(with: Date())
        case .stopped:
            finishWorkout(at: Date())
        case .ended:
            cleanupEndedWorkout()
        default:
            session.end()
            cleanupEndedWorkout()
        }
    }

    func recoverWorkout() {
        healthStore.recoverActiveWorkoutSession { [weak self] recoveredSession, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.workoutError = "Workout recovery failed: \(error.localizedDescription)"
                    WatchConnectivityManager.logStartup("Workout recovery failed: \(error.localizedDescription)")
                    return
                }
                guard let recoveredSession else {
                    self.workoutError = "Workout recovery did not return an active session."
                    WatchConnectivityManager.logStartup("Workout recovery returned no active session")
                    return
                }
                self.session = recoveredSession
                self.builder = recoveredSession.associatedWorkoutBuilder()
                self.builder?.dataSource = HKLiveWorkoutDataSource(
                    healthStore: self.healthStore,
                    workoutConfiguration: recoveredSession.workoutConfiguration
                )
                self.session?.delegate = self
                self.builder?.delegate = self
                self.isWorkoutActive = true
                self.workoutError = nil
                WatchConnectivityManager.logStartup("Recovered active HKWorkoutSession")
            }
        }
    }

    private func finishWorkout(at date: Date) {
        builder?.endCollection(withEnd: date) { [weak self] _, error in
            if let error {
                DispatchQueue.main.async {
                    self?.workoutError = "Failed to end workout collection: \(error.localizedDescription)"
                }
            }
            self?.builder?.finishWorkout { [weak self] _, error in
                DispatchQueue.main.async {
                    if let error {
                        self?.workoutError = "Failed to save workout: \(error.localizedDescription)"
                    }
                    self?.session?.end()
                    self?.cleanupEndedWorkout()
                    WatchConnectivityManager.logStartup("Finished HKWorkoutSession")
                }
            }
        }
    }

    private func cleanupEndedWorkout() {
        builder = nil
        session = nil
        isEndingWorkout = false
        isWorkoutActive = false
    }
}

extension RideWorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        WatchConnectivityManager.logStartup(
            "HKWorkoutSession state \(fromState.rawValue) → \(toState.rawValue)"
        )
        if toState == .stopped {
            finishWorkout(at: date)
        } else if toState == .ended {
            cleanupEndedWorkout()
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session error: \(error)")
        DispatchQueue.main.async {
            self.workoutError = "Workout session failed: \(error.localizedDescription)"
            self.isWorkoutActive = false
            self.isEndingWorkout = false
            self.session = nil
            self.builder = nil
        }
    }
}

extension RideWorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            if let statistics = workoutBuilder.statistics(for: quantityType) {
                DispatchQueue.main.async {
                    switch quantityType {
                    case HKQuantityType(.heartRate):
                        let bpm = statistics.mostRecentQuantity()?
                            .doubleValue(for: .count().unitDivided(by: .minute())) ?? 0
                        let timestamp = statistics.mostRecentQuantityDateInterval()?.end ?? Date()
                        self.heartRate = bpm
                        if bpm > 0 {
                            let sample = WatchHeartRateSample(
                                bpm: Int(bpm.rounded()),
                                timestamp: timestamp
                            )
                            self.latestHeartRateSample = sample
                            self.delegate?.rideWorkoutManager(
                                self,
                                didCollectHeartRateSample: sample,
                                activeCalories: self.activeCalories
                            )
                        }
                    case HKQuantityType(.activeEnergyBurned):
                        let activeCalories = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                        self.activeCalories = activeCalories
                        self.delegate?.rideWorkoutManager(self, didUpdateActiveCalories: activeCalories)
                    default:
                        break
                    }
                }
            }
        }
    }
}
