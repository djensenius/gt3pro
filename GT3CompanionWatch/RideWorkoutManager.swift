import HealthKit
import Foundation

class RideWorkoutManager: NSObject, ObservableObject {
    let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var isWorkoutActive = false

    func requestAuthorization() {
        let typesToShare: Set = [HKQuantityType.workoutType()]
        let typesToRead: Set = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
        ]

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            if let error {
                print("HealthKit auth error: \(error)")
            }
        }
    }

    func startWorkout(with configuration: HKWorkoutConfiguration? = nil) {
        guard session == nil else { return }

        let config = configuration ?? {
            let cfg = HKWorkoutConfiguration()
            cfg.activityType = .cycling
            cfg.locationType = .outdoor
            return cfg
        }()

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            builder = session?.associatedWorkoutBuilder()
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)

            session?.delegate = self
            builder?.delegate = self

            let startDate = Date()
            session?.startActivity(with: startDate)
            builder?.beginCollection(withStart: startDate) { _, _ in }

            DispatchQueue.main.async { self.isWorkoutActive = true }
        } catch {
            print("Failed to start workout: \(error)")
        }
    }

    func endWorkout() {
        guard session != nil else { return }
        session?.end()
        session = nil
        DispatchQueue.main.async { self.isWorkoutActive = false }
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
            builder?.endCollection(withEnd: date) { _, _ in
                self.builder?.finishWorkout { _, _ in }
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session error: \(error)")
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
