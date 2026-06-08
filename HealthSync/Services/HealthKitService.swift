import Foundation
import HealthKit

final class HealthKitService {
    static let shared = HealthKitService()
    let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Permission Types

    var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        let quantityIDs: [HKQuantityTypeIdentifier] = [
            .heartRate, .restingHeartRate, .heartRateVariabilitySDNN,
            .oxygenSaturation, .bloodPressureSystolic, .bloodPressureDiastolic,
            .stepCount, .distanceWalkingRunning, .activeEnergyBurned,
            .appleExerciseTime, .appleStandTime, .flightsClimbed,
            .respiratoryRate, .walkingHeartRateAverage, .vo2Max
        ]
        for id in quantityIDs {
            types.insert(HKQuantityType(id))
        }
        types.insert(HKCategoryType(.sleepAnalysis))
        types.insert(HKWorkoutType.workoutType())
        types.insert(HKActivitySummaryType.activitySummaryType())
        return types
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: - Dashboard Fetch

    func fetchDashboardData() async -> DashboardData {
        var data = DashboardData()
        data.isLoading = true

        let today = Calendar.current.startOfDay(for: Date())
        let now = Date()

        async let steps = fetchTodaySum(.stepCount, unit: .count(), start: today, end: now)
        async let distance = fetchTodaySum(.distanceWalkingRunning, unit: .meter(), start: today, end: now)
        async let activeEnergy = fetchTodaySum(.activeEnergyBurned, unit: .kilocalorie(), start: today, end: now)
        async let exerciseMinutes = fetchTodaySum(.appleExerciseTime, unit: .minute(), start: today, end: now)
        async let standHours = fetchTodaySum(.appleStandTime, unit: .hour(), start: today, end: now)
        async let flights = fetchTodaySum(.flightsClimbed, unit: .count(), start: today, end: now)
        async let currentHR = fetchLatestSample(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let restingHR = fetchLatestSample(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let hrv = fetchLatestSample(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let spo2 = fetchLatestSample(.oxygenSaturation, unit: .percent())
        async let respRate = fetchLatestSample(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let walkingHR = fetchLatestSample(.walkingHeartRateAverage, unit: HKUnit.count().unitDivided(by: .minute()))
        async let hrSamples = fetchHeartRateSamples(hours: 8)
        async let sleep = fetchLastNightSleep()
        async let workouts = fetchTodayWorkouts()

        data.steps = Int(await steps)
        data.distanceMeters = await distance
        data.activeEnergyKcal = await activeEnergy
        data.exerciseMinutes = Int(await exerciseMinutes)
        data.standHours = Int(await standHours)
        data.flightsClimbed = Int(await flights)
        data.currentHeartRate = await currentHR
        data.restingHeartRate = await restingHR
        data.heartRateVariability = await hrv
        data.bloodOxygen = await spo2 * 100
        data.respiratoryRate = await respRate
        data.walkingHeartRateAvg = await walkingHR
        data.heartRateSamples = await hrSamples
        data.sleepSummary = await sleep
        data.workouts = await workouts
        data.isLoading = false
        return data
    }

    // MARK: - Aggregated Stats

    private func fetchTodaySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(id),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    private func fetchLatestSample(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: HKQuantityType(id),
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    // MARK: - Heart Rate Samples

    private func fetchHeartRateSamples(hours: Int) async -> [HeartRateSample] {
        await withCheckedContinuation { continuation in
            let start = Calendar.current.date(byAdding: .hour, value: -hours, to: Date()) ?? Date()
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let unit = HKUnit.count().unitDivided(by: .minute())
            let query = HKSampleQuery(
                sampleType: HKQuantityType(.heartRate),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let result = (samples as? [HKQuantitySample] ?? []).map {
                    HeartRateSample(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    // MARK: - Sleep

    private func fetchLastNightSleep() async -> SleepSummary? {
        await withCheckedContinuation { continuation in
            let now = Date()
            let yesterday = Calendar.current.date(byAdding: .hour, value: -20, to: now) ?? now
            let predicate = HKQuery.predicateForSamples(withStart: yesterday, end: now)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let stages = samples.compactMap { sample -> SleepStageSegment? in
                    let stage = Self.sleepStageString(from: sample.value)
                    return SleepStageSegment(stage: stage, startDate: sample.startDate, endDate: sample.endDate)
                }
                let sleepSamples = samples.filter { [0, 1, 3, 4, 5].contains($0.value) }
                let bedtime = sleepSamples.first?.startDate
                let wakeTime = sleepSamples.last?.endDate
                continuation.resume(returning: SleepSummary(stages: stages, bedtime: bedtime, wakeTime: wakeTime))
            }
            store.execute(query)
        }
    }

    private static func sleepStageString(from value: Int) -> String {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed: return SleepStageType.inBed
        case .asleepUnspecified: return SleepStageType.asleepUnspecified
        case .awake: return SleepStageType.awake
        case .asleepDeep: return SleepStageType.asleepDeep
        case .asleepCore: return SleepStageType.asleepCore
        case .asleepREM: return SleepStageType.asleepREM
        default: return SleepStageType.asleepUnspecified
        }
    }

    // MARK: - Workouts

    private func fetchTodayWorkouts() async -> [WorkoutSummary] {
        await withCheckedContinuation { continuation in
            let today = Calendar.current.startOfDay(for: Date())
            let predicate = HKQuery.predicateForSamples(withStart: today, end: Date())
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let workouts = (samples as? [HKWorkout] ?? []).map { w in
                    WorkoutSummary(
                        type: w.workoutActivityType.name,
                        startDate: w.startDate,
                        endDate: w.endDate,
                        durationSeconds: w.duration,
                        activeEnergyKcal: w.statistics(for: HKQuantityType(.activeEnergyBurned))?
                            .sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0,
                        distanceMeters: w.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                            .sumQuantity()?.doubleValue(for: .meter()) ?? 0,
                        averageHeartRate: w.statistics(for: HKQuantityType(.heartRate))?
                            .averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    )
                }
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
    }

    // MARK: - Sync Data Fetching

    func fetchVitalRecords(since startDate: Date) async -> [VitalRecord] {
        var records: [VitalRecord] = []
        let iso = ISO8601DateFormatter()

        let types: [(HKQuantityTypeIdentifier, String, HKUnit)] = [
            (.heartRate, VitalType.heartRate, HKUnit.count().unitDivided(by: .minute())),
            (.restingHeartRate, VitalType.restingHeartRate, HKUnit.count().unitDivided(by: .minute())),
            (.heartRateVariabilitySDNN, VitalType.hrv, .secondUnit(with: .milli)),
            (.oxygenSaturation, VitalType.bloodOxygen, .percent()),
            (.bloodPressureSystolic, VitalType.bloodPressureSystolic, .millimeterOfMercury()),
            (.bloodPressureDiastolic, VitalType.bloodPressureDiastolic, .millimeterOfMercury()),
            (.respiratoryRate, VitalType.respiratoryRate, HKUnit.count().unitDivided(by: .minute())),
            (.walkingHeartRateAverage, VitalType.walkingHeartRateAverage, HKUnit.count().unitDivided(by: .minute())),
        ]

        for (typeID, typeName, unit) in types {
            let samples = await fetchQuantitySamples(typeID, since: startDate)
            let vitalRecords = samples.map { sample in
                VitalRecord(
                    type: typeName,
                    value: sample.quantity.doubleValue(for: unit),
                    unit: unit.unitString,
                    startDate: iso.string(from: sample.startDate),
                    endDate: iso.string(from: sample.endDate),
                    source: sample.sourceRevision.source.name
                )
            }
            records.append(contentsOf: vitalRecords)
        }
        return records
    }

    func fetchSleepRecords(since startDate: Date) async -> [SleepRecord] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let iso = ISO8601DateFormatter()
                let records = (samples as? [HKCategorySample] ?? []).map { sample in
                    let duration = Int(sample.endDate.timeIntervalSince(sample.startDate))
                    return SleepRecord(
                        stage: Self.sleepStageString(from: sample.value),
                        startDate: iso.string(from: sample.startDate),
                        endDate: iso.string(from: sample.endDate),
                        durationSeconds: duration,
                        source: sample.sourceRevision.source.name
                    )
                }
                continuation.resume(returning: records)
            }
            store.execute(query)
        }
    }

    func fetchWorkoutRecords(since startDate: Date) async -> [WorkoutRecord] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let iso = ISO8601DateFormatter()
                let records = (samples as? [HKWorkout] ?? []).map { w -> WorkoutRecord in
                    let energy = w.statistics(for: HKQuantityType(.activeEnergyBurned))?
                        .sumQuantity()?.doubleValue(for: .kilocalorie())
                    let distance = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                        .sumQuantity()?.doubleValue(for: .meter())
                    let avgHR = w.statistics(for: HKQuantityType(.heartRate))?
                        .averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    return WorkoutRecord(
                        workoutType: w.workoutActivityType.name,
                        startDate: iso.string(from: w.startDate),
                        endDate: iso.string(from: w.endDate),
                        durationSeconds: Int(w.duration),
                        totalEnergyBurnedKcal: energy,
                        totalDistanceMeters: distance,
                        averageHeartRate: avgHR,
                        source: w.sourceRevision.source.name
                    )
                }
                continuation.resume(returning: records)
            }
            store.execute(query)
        }
    }

    func fetchActivityRecords(forLast days: Int) async -> [ActivityRecord] {
        let cal = Calendar.current
        let iso = ISO8601DateFormatter()
        var records: [ActivityRecord] = []

        for dayOffset in 0..<days {
            guard let day = cal.date(byAdding: .day, value: -dayOffset, to: cal.startOfDay(for: Date())),
                  let dayEnd = cal.date(byAdding: .day, value: 1, to: day) else { continue }

            async let steps = fetchDaySum(.stepCount, unit: .count(), start: day, end: dayEnd)
            async let dist = fetchDaySum(.distanceWalkingRunning, unit: .meter(), start: day, end: dayEnd)
            async let energy = fetchDaySum(.activeEnergyBurned, unit: .kilocalorie(), start: day, end: dayEnd)
            async let exercise = fetchDaySum(.appleExerciseTime, unit: .minute(), start: day, end: dayEnd)
            async let flights = fetchDaySum(.flightsClimbed, unit: .count(), start: day, end: dayEnd)

            let record = ActivityRecord(
                date: iso.string(from: day),
                stepCount: Int(await steps),
                distanceMeters: await dist,
                activeEnergyKcal: await energy,
                exerciseMinutes: Int(await exercise),
                flightsClimbed: Int(await flights),
                source: "Apple Health"
            )
            records.append(record)
        }
        return records
    }

    // MARK: - Private Helpers

    private func fetchDaySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(id),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    private func fetchQuantitySamples(_ id: HKQuantityTypeIdentifier, since startDate: Date) async -> [HKQuantitySample] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date())
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: HKQuantityType(id),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            store.execute(query)
        }
    }
}

// MARK: - HKWorkoutActivityType name

private extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .hiking: return "Hiking"
        case .functionalStrengthTraining: return "Functional Strength Training"
        case .traditionalStrengthTraining: return "Traditional Strength Training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "Stair Climbing"
        case .tennis: return "Tennis"
        case .basketball: return "Basketball"
        case .soccer: return "Soccer"
        case .dance: return "Dance"
        case .pilates: return "Pilates"
        case .golf: return "Golf"
        case .crossTraining: return "Cross Training"
        case .cooldown: return "Cooldown"
        case .mindAndBody: return "Mind and Body"
        default: return "Workout"
        }
    }
}
