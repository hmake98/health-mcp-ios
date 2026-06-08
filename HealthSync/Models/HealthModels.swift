import Foundation
import SwiftUI

// MARK: - API Request Types (matching server schema)

struct VitalsRequest: Encodable {
    let records: [VitalRecord]
}

struct VitalRecord: Encodable {
    let type: String
    let value: Double
    let unit: String
    let startDate: String
    let endDate: String
    let source: String?
}

struct SleepRequest: Encodable {
    let records: [SleepRecord]
}

struct SleepRecord: Encodable {
    let stage: String
    let startDate: String
    let endDate: String
    let durationSeconds: Int
    let source: String?
}

struct WorkoutsRequest: Encodable {
    let records: [WorkoutRecord]
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

struct ActivityRequest: Encodable {
    let records: [ActivityRecord]
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

// MARK: - Dashboard Display Models

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

    var durationMinutes: Double {
        endDate.timeIntervalSince(startDate) / 60
    }

    var displayName: String {
        switch stage {
        case "asleepDeep": return "Deep"
        case "asleepREM": return "REM"
        case "asleepCore": return "Core"
        case "awake": return "Awake"
        case "inBed": return "In Bed"
        case "asleepUnspecified": return "Asleep"
        default: return stage
        }
    }

    var color: Color {
        switch stage {
        case "asleepDeep": return Color(red: 0.2, green: 0.4, blue: 0.9)
        case "asleepREM": return Color(red: 0.6, green: 0.2, blue: 0.9)
        case "asleepCore": return Color(red: 0.2, green: 0.6, blue: 0.9)
        case "awake": return Color(red: 1.0, green: 0.6, blue: 0.2)
        case "inBed": return Color.gray.opacity(0.4)
        default: return Color(red: 0.3, green: 0.7, blue: 0.9)
        }
    }
}

struct SleepSummary {
    let stages: [SleepStageSegment]
    let bedtime: Date?
    let wakeTime: Date?

    var totalInBedMinutes: Double {
        stages.filter { $0.stage == "inBed" }.reduce(0) { $0 + $1.durationMinutes }
    }

    var totalAsleepMinutes: Double {
        stages.filter { ["asleepDeep", "asleepREM", "asleepCore", "asleepUnspecified"].contains($0.stage) }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    var deepMinutes: Double {
        stages.filter { $0.stage == "asleepDeep" }.reduce(0) { $0 + $1.durationMinutes }
    }

    var remMinutes: Double {
        stages.filter { $0.stage == "asleepREM" }.reduce(0) { $0 + $1.durationMinutes }
    }

    var coreMinutes: Double {
        stages.filter { $0.stage == "asleepCore" }.reduce(0) { $0 + $1.durationMinutes }
    }

    var totalAsleepHours: Double { totalAsleepMinutes / 60 }

    var quality: String {
        let deepPercent = totalAsleepMinutes > 0 ? (deepMinutes / totalAsleepMinutes) * 100 : 0
        let remPercent = totalAsleepMinutes > 0 ? (remMinutes / totalAsleepMinutes) * 100 : 0
        if totalAsleepHours >= 7 && deepPercent >= 13 && remPercent >= 18 { return "Great" }
        if totalAsleepHours >= 6 { return "Good" }
        if totalAsleepHours >= 5 { return "Fair" }
        return "Poor"
    }

    var qualityColor: Color {
        switch quality {
        case "Great": return .green
        case "Good": return .blue
        case "Fair": return .yellow
        default: return .red
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
        type
            .replacingOccurrences(of: "(?<=[a-z])(?=[A-Z])", with: " ", options: .regularExpression)
            .capitalized
    }

    var icon: String {
        let key = type.lowercased()
        if key.contains("run") { return "figure.run" }
        if key.contains("cycl") || key.contains("bike") { return "figure.outdoor.cycle" }
        if key.contains("walk") { return "figure.walk" }
        if key.contains("swim") { return "figure.pool.swim" }
        if key.contains("yoga") { return "figure.yoga" }
        if key.contains("hik") { return "figure.hiking" }
        if key.contains("strength") || key.contains("weight") { return "figure.strengthtraining.traditional" }
        if key.contains("hiit") || key.contains("interval") { return "figure.highintensity.intervaltraining" }
        if key.contains("row") { return "figure.rowing" }
        if key.contains("elliptical") { return "figure.elliptical" }
        if key.contains("stair") { return "figure.stairs" }
        if key.contains("tennis") { return "figure.tennis" }
        if key.contains("basketball") { return "figure.basketball" }
        if key.contains("soccer") { return "figure.soccer" }
        if key.contains("dance") { return "figure.dance" }
        if key.contains("pilates") { return "figure.pilates" }
        return "figure.mixed.cardio"
    }

    var distanceKm: Double { distanceMeters / 1000 }
    var distanceMiles: Double { distanceMeters / 1609.34 }
}

struct DashboardData {
    var steps: Int = 0
    var distanceMeters: Double = 0
    var activeEnergyKcal: Double = 0
    var exerciseMinutes: Int = 0
    var standHours: Int = 0
    var flightsClimbed: Int = 0
    var moveGoal: Double = 500
    var exerciseGoal: Int = 30
    var standGoal: Int = 12
    var stepGoal: Int = 10000
    var currentHeartRate: Double = 0
    var restingHeartRate: Double = 0
    var heartRateVariability: Double = 0
    var bloodOxygen: Double = 0
    var respiratoryRate: Double = 0
    var walkingHeartRateAvg: Double = 0
    var heartRateSamples: [HeartRateSample] = []
    var sleepSummary: SleepSummary? = nil
    var workouts: [WorkoutSummary] = []
    var isLoading: Bool = false

    var moveProgress: Double { min(activeEnergyKcal / max(moveGoal, 1), 1.0) }
    var exerciseProgress: Double { min(Double(exerciseMinutes) / Double(exerciseGoal), 1.0) }
    var standProgress: Double { min(Double(standHours) / Double(standGoal), 1.0) }
    var stepProgress: Double { min(Double(steps) / Double(stepGoal), 1.0) }

    var heartRateMin: Double { heartRateSamples.map(\.value).min() ?? 0 }
    var heartRateMax: Double { heartRateSamples.map(\.value).max() ?? 0 }
    var heartRateAvg: Double {
        guard !heartRateSamples.isEmpty else { return 0 }
        return heartRateSamples.map(\.value).reduce(0, +) / Double(heartRateSamples.count)
    }
}

// MARK: - Vital Type Constants

enum VitalType {
    static let heartRate = "heart_rate"
    static let restingHeartRate = "resting_heart_rate"
    static let hrv = "hrv"
    static let bloodOxygen = "blood_oxygen"
    static let bloodPressureSystolic = "blood_pressure_systolic"
    static let bloodPressureDiastolic = "blood_pressure_diastolic"
    static let respiratoryRate = "respiratory_rate"
    static let walkingHeartRateAverage = "walking_heart_rate_average"
}

enum SleepStageType {
    static let inBed = "inBed"
    static let asleepUnspecified = "asleepUnspecified"
    static let awake = "awake"
    static let asleepDeep = "asleepDeep"
    static let asleepCore = "asleepCore"
    static let asleepREM = "asleepREM"
}
