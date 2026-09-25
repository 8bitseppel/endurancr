import Foundation
import HealthKit
import CoreLocation
import TrainingCore

/// Wraps HealthKit authorization and reading of running workouts. All data stays
/// on-device; nothing here touches the network. Used by both the iOS and watch
/// targets (the watch additionally *writes* workouts via `WorkoutManager`).
@Observable
@MainActor
final class HealthKitService {
    let store = HKHealthStore()
    var isAuthorized = false
    var lastError: String?

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Types we read to reason about training and fitness.
    private var readTypes: Set<HKObjectType> {
        [
            .workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.runningSpeed),
            HKQuantityType(.runningPower),
            HKQuantityType(.stepCount),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.vo2Max),
            HKSeriesType.workoutRoute(),
        ]
    }

    /// Types we write when the watch records a run.
    private var shareTypes: Set<HKSampleType> {
        [
            .workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned),
            HKSeriesType.workoutRoute(),
        ]
    }

    func requestAuthorization() async {
        if DemoMode.isOn { isAuthorized = true; return }
        guard Self.isAvailable else {
            lastError = "Health data isn't available on this device."
            return
        }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            isAuthorized = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Fetches running workouts since `date`, mapped to the engine's `CompletedRun`.
    func fetchRuns(since date: Date) async -> [CompletedRun] {
        if DemoMode.isOn { return DemoMode.runs.filter { $0.date >= date } }
        let workouts = await fetchRunningWorkouts(since: date)
        var runs: [CompletedRun] = []
        for workout in workouts {
            let distance = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                .sumQuantity()?.doubleValue(for: .meter()) ?? 0
            let hr = await averageHeartRate(during: workout)
            runs.append(CompletedRun(
                date: workout.startDate,
                distanceMeters: distance,
                durationSeconds: workout.duration,
                averageHeartRate: hr
            ))
        }
        return runs
    }

    /// Recent running workouts (most recent first) for the run-history screen —
    /// the underlying `HKWorkout`s, so a detail view can also load their GPS route.
    func recentRunningWorkouts(since date: Date) async -> [HKWorkout] {
        await fetchRunningWorkouts(since: date).sorted { $0.startDate > $1.startDate }
    }

    /// Average heart rate (bpm) across a workout, or `nil` if none was recorded
    /// (e.g. an iPhone-only run with no heart-rate sensor).
    func averageHeartRate(for workout: HKWorkout) async -> Double? {
        await averageHeartRate(during: workout)
    }

    /// Active energy burned (kcal) during a workout, or `nil` if not recorded.
    func activeEnergyKilocalories(for workout: HKWorkout) -> Double? {
        workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())
    }

    /// Total distance (meters) of a running workout.
    func distanceMeters(for workout: HKWorkout) -> Double {
        workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?.doubleValue(for: .meter()) ?? 0
    }

    /// Fetches daily resting-heart-rate samples since `date`, for fatigue detection.
    func fetchRestingHeartRates(since date: Date) async -> [RestingHeartRateSample] {
        if DemoMode.isOn { return [] }
        let type = HKQuantityType(.restingHeartRate)
        let predicate = HKQuery.predicateForSamples(withStart: date, end: nil)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let unit = HKUnit.count().unitDivided(by: .minute())
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, samples, _ in
                let mapped = (samples as? [HKQuantitySample])?.map {
                    RestingHeartRateSample(date: $0.startDate, bpm: $0.quantity.doubleValue(for: unit))
                } ?? []
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    /// Loads the GPS route attached to a workout as an ordered list of coordinates,
    /// for drawing in-app with MapKit. Returns `[]` if the run has no route.
    func routeCoordinates(for workout: HKWorkout) async -> [CLLocationCoordinate2D] {
        guard let route = await routeSample(for: workout) else { return [] }
        return await withCheckedContinuation { continuation in
            var coords: [CLLocationCoordinate2D] = []
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if error != nil { continuation.resume(returning: coords); return }
                if let locations { coords.append(contentsOf: locations.map(\.coordinate)) }
                if done { continuation.resume(returning: coords) }
            }
            store.execute(query)
        }
    }

    private func routeSample(for workout: HKWorkout) async -> HKWorkoutRoute? {
        let predicate = HKQuery.predicateForObjects(from: workout)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(), predicate: predicate,
                limit: 1, sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkoutRoute])?.first)
            }
            store.execute(query)
        }
    }

    private func fetchRunningWorkouts(since date: Date) async -> [HKWorkout] {
        if DemoMode.isOn { return [] }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForSamples(withStart: date, end: nil),
        ])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(), predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }

    private func averageHeartRate(during workout: HKWorkout) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(.heartRate), quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, stats, _ in
                let unit = HKUnit.count().unitDivided(by: .minute())
                continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }
}
