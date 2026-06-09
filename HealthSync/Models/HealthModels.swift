import Foundation
import SwiftUI

// MARK: - API Request Types

struct VitalsRequest: Encodable { let records: [VitalRecord] }
struct SleepRequest: Encodable { let records: [SleepRecord] }
struct WorkoutsRequest: Encodable { let records: [WorkoutRecord] }
struct ActivityRequest: Encodable { let records: [ActivityRecord] }

struct VitalRecord: Encodable {
    let type: String
    let value: Double
    let unit: String
    let startDate: String
    let endDate: String
    let source: String?
}

struct SleepRecord: Encodable {
    let stage: String
    let startDate: String
    let endDate: String
    let durationSeconds: Int
    let source: String?
}

struct WorkoutRecord: Encodable {
    let workoutType: String
    let startDate: String
    let endDate: String
    let durationSeconds: Int
    let totalEnergyBurnedKcal: Double?
    let totalDistanceMeters: Double?
    let averageHeartRate: Double?
    let source: String?
}

struct ActivityRecord: Encodable {
    let date: String
    let stepCount: Int?
    let distanceMeters: Double?
    let activeEnergyKcal: Double?
    let exerciseMinutes: Int?
    let flightsClimbed: Int?
    let source: String?
}

// MARK: - Timed Value

/// A health metric value paired with when it was actually measured.
/// Use isStale(within:) to decide whether to display it.
struct TimedValue {
    let value: Double
    let measuredAt: Date

    /// Default: 4 hours — for heart rate, SpO2, respiratory rate.
    static let shortStaleness: TimeInterval = 4 * 3600
    /// Extended: 24 hours — for resting HR and HRV (measured during sleep/rest).
    static let longStaleness: TimeInterval = 24 * 3600

    func isStale(within threshold: TimeInterval = shortStaleness) -> Bool {
        Date().timeIntervalSince(measuredAt) > threshold
    }

    var ageString: String {
        let secs = Date().timeIntervalSince(measuredAt)
        if secs < 60    { return "just now" }
        if secs < 3600  { return "\(Int(secs / 60))m ago" }
        if secs < 86400 { return "\(Int(secs / 3600))h ago" }
        return "yesterday"
    }
}

// MARK: - Dashboard Data

struct DashboardData {
    // Goals
    var moveGoal: Double = 500
    var exerciseGoal: Int = 30
    var standGoal: Int = 12
    var stepGoal: Int = 10000

    // Activity — always today's totals, no staleness concept
    var steps: Int = 0
    var distanceMeters: Double = 0
    var activeEnergyKcal: Double = 0
    var exerciseMinutes: Int = 0
    var standHours: Int = 0
    var flightsClimbed: Int = 0

    // Heart metrics with measurement timestamps
    var heartRate: TimedValue? = nil         // stale after 4 h
    var restingHeartRate: TimedValue? = nil  // stale after 24 h
    var hrv: TimedValue? = nil               // stale after 24 h

    // Vitals with measurement timestamps
    var bloodOxygen: TimedValue? = nil       // stale after 4 h; stored as 0–100 %
    var respiratoryRate: TimedValue? = nil   // stale after 4 h

    // Heart rate chart — last 8 hours of individual readings
    var heartRateSamples: [HeartRateSample] = []

    // Sleep — last night
    var sleepSummary: SleepSummary? = nil

    // Workouts today
    var workouts: [WorkoutSummary] = []

    var isLoading: Bool = false

    // MARK: - Progress helpers (used by activity rings)

    var moveProgress: Double     { min(activeEnergyKcal / max(moveGoal, 1), 1.0) }
    var exerciseProgress: Double { min(Double(exerciseMinutes) / Double(exerciseGoal), 1.0) }
    var standProgress: Double    { min(Double(standHours) / Double(standGoal), 1.0) }
    var stepProgress: Double     { min(Double(steps) / Double(stepGoal), 1.0) }

    // MARK: - Fresh metric accessors

    /// Returns heartRate only if measured within the last 4 hours.
    var freshHeartRate: TimedValue?       { heartRate.flatMap     { $0.isStale() ? nil : $0 } }
    /// Returns bloodOxygen only if measured within the last 4 hours.
    var freshBloodOxygen: TimedValue?     { bloodOxygen.flatMap   { $0.isStale() ? nil : $0 } }
    /// Returns respiratoryRate only if measured within the last 4 hours.
    var freshRespiratoryRate: TimedValue? { respiratoryRate.flatMap { $0.isStale() ? nil : $0 } }
    /// Returns restingHeartRate only if measured within the last 24 hours.
    var freshRestingHR: TimedValue?       { restingHeartRate.flatMap { $0.isStale(within: TimedValue.longStaleness) ? nil : $0 } }
    /// Returns HRV only if measured within the last 24 hours.
    var freshHRV: TimedValue?             { hrv.flatMap { $0.isStale(within: TimedValue.longStaleness) ? nil : $0 } }

    // MARK: - Visibility helpers

    var hasAnyActivity: Bool { steps > 0 || activeEnergyKcal > 0 || exerciseMinutes > 0 }
    var hasHeartData: Bool   { freshHeartRate != nil || !heartRateSamples.isEmpty || freshRestingHR != nil || freshHRV != nil }
    var hasVitals: Bool      { freshBloodOxygen != nil || freshRespiratoryRate != nil }

    // MARK: - Backward-compat properties (used by HealthInsights.swift)

    var currentHeartRate: Double   { heartRate?.value ?? 0 }
    var heartRateVariability: Double { hrv?.value ?? 0 }
    var heartRateMin: Double { heartRateSamples.map(\.value).min() ?? 0 }
    var heartRateMax: Double { heartRateSamples.map(\.value).max() ?? 0 }
    var heartRateAvg: Double {
        guard !heartRateSamples.isEmpty else { return 0 }
        return heartRateSamples.map(\.value).reduce(0, +) / Double(heartRateSamples.count)
    }
}

// MARK: - Chart & Display Models

struct HeartRateSample: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct SleepStageSegment: Identifiable {
    let id = UUID()
    let stage: String
    let startDate: Date
    let endDate: Date

    var durationMinutes: Double { endDate.timeIntervalSince(startDate) / 60 }

    var displayName: String {
        switch stage {
        case "asleepDeep": return "Deep"
        case "asleepREM":  return "REM"
        case "asleepCore": return "Core"
        case "awake":      return "Awake"
        case "inBed":      return "In Bed"
        default:           return "Asleep"
        }
    }

    var color: Color {
        switch stage {
        case "asleepDeep": return Color(red: 0.2, green: 0.4, blue: 0.9)
        case "asleepREM":  return Color(red: 0.6, green: 0.2, blue: 0.9)
        case "asleepCore": return Color(red: 0.2, green: 0.6, blue: 0.9)
        case "awake":      return Color(red: 1.0, green: 0.6, blue: 0.2)
        case "inBed":      return Color.gray.opacity(0.4)
        default:           return Color(red: 0.3, green: 0.7, blue: 0.9)
        }
    }
}

struct SleepSummary {
    let stages: [SleepStageSegment]
    let bedtime: Date?
    let wakeTime: Date?

    var totalInBedMinutes: Double    { stages.filter { $0.stage == "inBed" }.reduce(0) { $0 + $1.durationMinutes } }
    var totalAsleepMinutes: Double   { stages.filter { ["asleepDeep","asleepREM","asleepCore","asleepUnspecified"].contains($0.stage) }.reduce(0) { $0 + $1.durationMinutes } }
    var deepMinutes: Double          { stages.filter { $0.stage == "asleepDeep" }.reduce(0) { $0 + $1.durationMinutes } }
    var remMinutes: Double           { stages.filter { $0.stage == "asleepREM" }.reduce(0) { $0 + $1.durationMinutes } }
    var coreMinutes: Double          { stages.filter { $0.stage == "asleepCore" }.reduce(0) { $0 + $1.durationMinutes } }
    var totalAsleepHours: Double     { totalAsleepMinutes / 60 }

    var quality: String {
        let deepPct = totalAsleepMinutes > 0 ? (deepMinutes / totalAsleepMinutes) * 100 : 0
        let remPct  = totalAsleepMinutes > 0 ? (remMinutes  / totalAsleepMinutes) * 100 : 0
        if totalAsleepHours >= 7 && deepPct >= 13 && remPct >= 18 { return "Great" }
        if totalAsleepHours >= 6 { return "Good" }
        if totalAsleepHours >= 5 { return "Fair" }
        return "Poor"
    }

    var qualityColor: Color {
        switch quality {
        case "Great": return .green
        case "Good":  return .blue
        case "Fair":  return .yellow
        default:      return .red
        }
    }
}

struct WorkoutSummary: Identifiable {
    let id = UUID()
    let type: String
    let startDate: Date
    let endDate: Date
    let durationSeconds: Double
    let activeEnergyKcal: Double
    let distanceMeters: Double
    let averageHeartRate: Double?

    var durationMinutes: Double { durationSeconds / 60 }

    var displayName: String {
        type.replacingOccurrences(of: "(?<=[a-z])(?=[A-Z])", with: " ", options: .regularExpression).capitalized
    }

    var icon: String {
        let k = type.lowercased()
        if k.contains("run")      { return "figure.run" }
        if k.contains("cycl") || k.contains("bike") { return "figure.outdoor.cycle" }
        if k.contains("walk")     { return "figure.walk" }
        if k.contains("swim")     { return "figure.pool.swim" }
        if k.contains("yoga")     { return "figure.yoga" }
        if k.contains("hik")      { return "figure.hiking" }
        if k.contains("strength") || k.contains("weight") { return "figure.strengthtraining.traditional" }
        if k.contains("hiit") || k.contains("interval")   { return "figure.highintensity.intervaltraining" }
        if k.contains("row")      { return "figure.rowing" }
        if k.contains("elliptic") { return "figure.elliptical" }
        if k.contains("stair")    { return "figure.stairs" }
        if k.contains("tennis")   { return "figure.tennis" }
        if k.contains("basket")   { return "figure.basketball" }
        if k.contains("soccer")   { return "figure.soccer" }
        if k.contains("dance")    { return "figure.dance" }
        if k.contains("pilates")  { return "figure.pilates" }
        return "figure.mixed.cardio"
    }

    var distanceKm: Double    { distanceMeters / 1000 }
    var distanceMiles: Double { distanceMeters / 1609.34 }
}

// MARK: - Vital Type Constants

enum VitalType {
    static let heartRate               = "heart_rate"
    static let restingHeartRate        = "resting_heart_rate"
    static let hrv                     = "hrv"
    static let bloodOxygen             = "blood_oxygen"
    static let bloodPressureSystolic   = "blood_pressure_systolic"
    static let bloodPressureDiastolic  = "blood_pressure_diastolic"
    static let respiratoryRate         = "respiratory_rate"
    static let walkingHeartRateAverage = "walking_heart_rate_average"
}

enum SleepStageType {
    static let inBed             = "inBed"
    static let asleepUnspecified = "asleepUnspecified"
    static let awake             = "awake"
    static let asleepDeep        = "asleepDeep"
    static let asleepCore        = "asleepCore"
    static let asleepREM         = "asleepREM"
}
