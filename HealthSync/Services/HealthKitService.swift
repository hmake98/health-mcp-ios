import Foundation
import HealthKit
import os

private let hkLogger = Logger(subsystem: "com.hmake98.HealthSync", category: "HealthKitService")

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
            .respiratoryRate, .walkingHeartRateAverage, .vo2Max,
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

    // MARK: - Background Delivery

    // Registers HKObserverQuery for key types and enables background delivery.
    // iOS wakes the app when any observed type has new data; onNewData fires on a background thread.
    // The completion handler MUST be called promptly (within ~15 s) or iOS kills the wake.
    func enableBackgroundDelivery(onNewData: @escaping () -> Void) {
        let observedTypes: [HKSampleType] = [
            HKQuantityType(.heartRate),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKCategoryType(.sleepAnalysis),
            HKWorkoutType.workoutType(),
        ]
        for type in observedTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
                defer { completionHandler() } // release HealthKit's background time immediately
                if let error {
                    hkLogger.error("HKObserverQuery error for \(type.identifier): \(error)")
                    return
                }
                hkLogger.info("HealthKit background delivery fired for \(type.identifier)")
                onNewData()
            }
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { success, error in
                if let error {
                    hkLogger.error("enableBackgroundDelivery failed for \(type.identifier): \(error)")
                } else {
                    hkLogger.info("Background delivery enabled for \(type.identifier): \(success)")
                }
            }
        }
    }

    // MARK: - Dashboard Fetch

    func fetchDashboardData() async -> DashboardData {
        var data = DashboardData()
        data.isLoading = true

        let today = Calendar.current.startOfDay(for: Date())
        let now = Date()
        let bpm = HKUnit.count().unitDivided(by: .minute())
        // mL/(kg·min) — the standard VO2 Max unit
        let vo2Unit = HKUnit.literUnit(with: .milli)
            .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))

        async let steps = fetchTodaySum(.stepCount, unit: .count(), start: today, end: now)
        async let distance = fetchTodaySum(.distanceWalkingRunning, unit: .meter(), start: today, end: now)
        async let activeEnergy = fetchTodaySum(.activeEnergyBurned, unit: .kilocalorie(), start: today, end: now)
        async let exerciseMinutes = fetchTodaySum(.appleExerciseTime, unit: .minute(), start: today, end: now)
        async let standHours = fetchTodaySum(.appleStandTime, unit: .hour(), start: today, end: now)
        async let flights = fetchTodaySum(.flightsClimbed, unit: .count(), start: today, end: now)
        async let currentHR = fetchLatestSampleWithDate(.heartRate, unit: bpm)
        async let restingHR = fetchLatestSampleWithDate(.restingHeartRate, unit: bpm)
        async let hrv = fetchLatestSampleWithDate(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let spo2 = fetchLatestSampleWithDate(.oxygenSaturation, unit: .percent())
        async let respRate = fetchLatestSampleWithDate(.respiratoryRate, unit: bpm)
        async let walkingHR = fetchLatestSampleWithDate(.walkingHeartRateAverage, unit: bpm)
        async let vo2 = fetchLatestSampleWithDate(.vo2Max, unit: vo2Unit)
        async let hrSamples = fetchHeartRateSamples(hours: 8)
        async let sleep = fetchLastNightSleep()
        async let sleepConsistency = fetchSleepConsistency()
        async let workouts = fetchTodayWorkouts()

        data.steps = Int(await steps)
        data.distanceMeters = await distance
        data.activeEnergyKcal = await activeEnergy
        data.exerciseMinutes = Int(await exerciseMinutes)
        data.standHours = Int(await standHours)
        data.flightsClimbed = Int(await flights)

        if let hr  = await currentHR  { data.heartRate           = TimedValue(value: hr.value,          measuredAt: hr.measuredAt) }
        if let rh  = await restingHR  { data.restingHeartRate    = TimedValue(value: rh.value,          measuredAt: rh.measuredAt) }
        if let hv  = await hrv        { data.hrv                 = TimedValue(value: hv.value,          measuredAt: hv.measuredAt) }
        // oxygenSaturation returns 0–1 fraction; convert to 0–100 %
        if let o2  = await spo2       { data.bloodOxygen         = TimedValue(value: o2.value * 100,    measuredAt: o2.measuredAt) }
        if let rr  = await respRate   { data.respiratoryRate     = TimedValue(value: rr.value,          measuredAt: rr.measuredAt) }
        if let whr = await walkingHR  { data.walkingHeartRateAvg = TimedValue(value: whr.value,         measuredAt: whr.measuredAt) }
        if let v2  = await vo2        { data.vo2Max              = TimedValue(value: v2.value,           measuredAt: v2.measuredAt) }

        data.heartRateSamples   = await hrSamples
        data.sleepSummary       = await sleep
        data.sleepConsistency   = await sleepConsistency
        data.workouts           = await workouts
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

    // Returns both value and the measurement timestamp so callers can build a TimedValue.
    func fetchLatestSampleWithDate(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> (value: Double, measuredAt: Date)? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: HKQuantityType(id),
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (sample.quantity.doubleValue(for: unit), sample.startDate))
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
            // 26 h window captures late-night sleepers (e.g. 2 AM start) and early risers.
            let yesterday = Calendar.current.date(byAdding: .hour, value: -26, to: now) ?? now
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

    // Fetches the last 8 nights of sleep, extracts bedtimes, and computes the
    // standard deviation so the caller can display a schedule consistency label.
    private func fetchSleepConsistency() async -> SleepConsistency? {
        await withCheckedContinuation { continuation in
            let now = Date()
            let eightDaysAgo = Calendar.current.date(byAdding: .day, value: -8, to: now) ?? now
            let predicate = HKQuery.predicateForSamples(withStart: eightDaysAgo, end: now)
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
                // Group segments into distinct nights: a gap of >3 h between segments = new night.
                var nights: [[HKCategorySample]] = []
                var current: [HKCategorySample] = []
                for sample in samples {
                    if let last = current.last,
                       sample.startDate.timeIntervalSince(last.endDate) > 3 * 3600 {
                        if !current.isEmpty { nights.append(current) }
                        current = [sample]
                    } else {
                        current.append(sample)
                    }
                }
                if !current.isEmpty { nights.append(current) }

                let cal = Calendar.current
                // Extract bedtime = first actual sleep sample (not just inBed) each night.
                let bedtimeMinutes: [Double] = nights.compactMap { night in
                    let sleepValues = Set([1, 3, 4, 5]) // asleepUnspecified, deep, core, REM
                    guard let first = night.first(where: { sleepValues.contains($0.value) }) else { return nil }
                    let comps = cal.dateComponents([.hour, .minute], from: first.startDate)
                    var mins = Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
                    // Normalize post-midnight bedtimes (0–360 min) to negatives so variance
                    // doesn't treat "11:50 PM" and "12:10 AM" as maximally different.
                    if mins < 360 { mins -= 1440 }
                    return mins
                }

                guard bedtimeMinutes.count >= 3 else {
                    continuation.resume(returning: nil)
                    return
                }

                let mean = bedtimeMinutes.reduce(0, +) / Double(bedtimeMinutes.count)
                let variance = bedtimeMinutes.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(bedtimeMinutes.count)
                continuation.resume(returning: SleepConsistency(
                    nightsAnalyzed: bedtimeMinutes.count,
                    bedtimeVarianceMinutes: variance.squareRoot()
                ))
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

        let bpm = HKUnit.count().unitDivided(by: .minute())
        let types: [(HKQuantityTypeIdentifier, String, HKUnit, Double)] = [
            (.heartRate,               VitalType.heartRate,               bpm,                    1),
            (.restingHeartRate,        VitalType.restingHeartRate,        bpm,                    1),
            (.heartRateVariabilitySDNN,VitalType.hrv,                     .secondUnit(with: .milli), 1),
            // oxygenSaturation returns 0–1 fraction; multiply by 100 to store as percentage (97.0 not 0.97)
            (.oxygenSaturation,        VitalType.bloodOxygen,             .percent(),             100),
            (.bloodPressureSystolic,   VitalType.bloodPressureSystolic,   .millimeterOfMercury(), 1),
            (.bloodPressureDiastolic,  VitalType.bloodPressureDiastolic,  .millimeterOfMercury(), 1),
            (.respiratoryRate,         VitalType.respiratoryRate,         bpm,                    1),
            (.walkingHeartRateAverage, VitalType.walkingHeartRateAverage, bpm,                         1),
            // VO2 max is estimated weekly by Apple Watch; unit is mL/min/kg
            (.vo2Max,                  VitalType.vo2Max,                  HKUnit(from: "ml/kg/min"),   1),
        ]

        for (typeID, typeName, unit, multiplier) in types {
            let samples = await fetchQuantitySamples(typeID, since: startDate)
            let vitalRecords = samples.map { sample in
                VitalRecord(
                    sourceId: sample.uuid.uuidString,
                    type: typeName,
                    value: sample.quantity.doubleValue(for: unit) * multiplier,
                    unit: typeName == VitalType.bloodOxygen ? "%" : unit.unitString,
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
                        sourceId: sample.uuid.uuidString,
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
                        sourceId: w.uuid.uuidString,
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
