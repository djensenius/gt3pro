import HealthKit
import Foundation

class RideWorkoutManager: NSObject, ObservableObject {
    let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var authorizationInProgress = false
    private var authorizationCompletions: [(Bool) -> Void] = []
    private var pendingStartConfiguration: HKWorkoutConfiguration?
    private var isEndingWorkout = false

    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var isWorkoutActive = false
    @Published var isAuthorizationGranted = false
    @Published var workoutError: String?

    private var isWorkoutAuthorized: Bool {
        healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async {
                self.workoutError = "HealthKit is not available on this device."
                self.isAuthorizationGranted = false
                completion?(false)
            }
            return
        }

        let workoutType = HKObjectType.workoutType()
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

        let typesToShare: Set<HKSampleType> = [workoutType]
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
            print("Ignoring workout start: session already active or ending")
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async {
                self.workoutError = "HealthKit is not available on this device."
            }
            return
        }

        let config = configuration ?? {
            let cfg = HKWorkoutConfiguration()
            cfg.activityType = .cycling
            cfg.locationType = .outdoor
            return cfg
        }()

        guard isWorkoutAuthorized else {
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
        guard session != nil, !isEndingWorkout else {
            print("Ignoring workout end: no active session or already ending")
            return
        }
        isEndingWorkout = true
        session?.end()
    }
}

extension RideWorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        if toState == .ended {
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
                        self?.builder = nil
                        self?.session = nil
                        self?.isEndingWorkout = false
                        self?.isWorkoutActive = false
                    }
                }
            }
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
                        self.heartRate = statistics.mostRecentQuantity()?
                            .doubleValue(for: .count().unitDivided(by: .minute())) ?? 0
                    case HKQuantityType(.activeEnergyBurned):
                        self.activeCalories = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    default:
                        break
                    }
                }
            }
        }
    }
}
