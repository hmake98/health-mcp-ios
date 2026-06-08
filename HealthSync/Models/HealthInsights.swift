import Foundation
import SwiftUI

enum InsightStatus {
    case great, good, fair, low, noData

    var color: Color {
        switch self {
        case .great: return .green
        case .good: return .blue
        case .fair: return .orange
        case .low: return .red
        case .noData: return .secondary
        }
    }

    var dot: String {
        switch self {
        case .great: return "circle.fill"
        case .good: return "circle.fill"
        case .fair: return "circle.fill"
        case .low: return "circle.fill"
        case .noData: return "circle.dotted"
        }
    }
}

struct HealthInsight {
    let headline: String
    let detail: String
    let status: InsightStatus
}

struct HealthInsights {
    let data: DashboardData

    // MARK: - Overall

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Good night"
        }
    }

    var overallHeadline: String {
        let statuses: [InsightStatus] = [
            sleep.status, activity.status, heart.status, recovery.status
        ].filter { $0 != .noData }

        guard !statuses.isEmpty else { return "Collecting your data…" }

        let positive = statuses.filter { $0 == .great || $0 == .good }.count
        let ratio = Double(positive) / Double(statuses.count)

        if ratio == 1.0 { return "You're doing great today" }
        if ratio >= 0.6 { return "Overall looking good" }
        if ratio >= 0.3 { return "Mixed signals today" }
        return "Your body may need some rest"
    }

    var overallStatus: InsightStatus {
        let statuses: [InsightStatus] = [
            sleep.status, activity.status, heart.status, recovery.status
        ].filter { $0 != .noData }

        guard !statuses.isEmpty else { return .noData }

        let positive = statuses.filter { $0 == .great || $0 == .good }.count
        let ratio = Double(positive) / Double(statuses.count)

        if ratio == 1.0 { return .great }
        if ratio >= 0.6 { return .good }
        if ratio >= 0.3 { return .fair }
        return .low
    }

    // MARK: - Sleep

    var sleep: HealthInsight {
        guard let s = data.sleepSummary, s.totalAsleepHours > 0 else {
            return HealthInsight(
                headline: "No sleep recorded",
                detail: "Wear your watch to bed to track sleep stages.",
                status: .noData
            )
        }
        let h = s.totalAsleepHours
        let formatted = formatHours(h)
        let quality = s.quality

        switch quality {
        case "Great":
            return HealthInsight(
                headline: "Well rested",
                detail: "\(formatted) of sleep with strong deep and REM stages — your body recovered well overnight.",
                status: .great
            )
        case "Good":
            return HealthInsight(
                headline: "Good night's rest",
                detail: "\(formatted) of sleep — solid rest, though a little more deep sleep would help.",
                status: .good
            )
        case "Fair":
            return HealthInsight(
                headline: "Light sleep",
                detail: "\(formatted) — below the 7-8 hour range. You may feel a bit tired today.",
                status: .fair
            )
        default:
            return HealthInsight(
                headline: "Not enough sleep",
                detail: "Only \(formatted) recorded. Try to rest more — sleep is essential for recovery.",
                status: .low
            )
        }
    }

    // MARK: - Activity

    var activity: HealthInsight {
        let moveProgress = data.moveProgress
        let allGoalsHit = moveProgress >= 1.0 && data.exerciseProgress >= 1.0 && data.standProgress >= 1.0
        let kcal = Int(data.activeEnergyKcal)
        let goal = Int(data.moveGoal)
        let remaining = max(0, goal - kcal)

        if allGoalsHit {
            return HealthInsight(
                headline: "All goals complete!",
                detail: "Move, exercise, and stand rings are all closed. Excellent day.",
                status: .great
            )
        } else if moveProgress >= 0.8 {
            return HealthInsight(
                headline: "Almost there",
                detail: "Just \(remaining) more calories to close your move ring. You've got this.",
                status: .good
            )
        } else if moveProgress >= 0.4 {
            return HealthInsight(
                headline: "Making progress",
                detail: "\(kcal) of \(goal) calories burned — keep moving through the day.",
                status: .fair
            )
        } else {
            return HealthInsight(
                headline: "Time to move",
                detail: "You've burned \(kcal) calories. A short walk would make a big difference.",
                status: .low
            )
        }
    }

    // MARK: - Heart Rate

    var heart: HealthInsight {
        let hr = data.currentHeartRate > 0 ? data.currentHeartRate : data.heartRateAvg
        guard hr > 0 else {
            return HealthInsight(
                headline: "No reading yet",
                detail: "Heart rate data will appear once your watch syncs.",
                status: .noData
            )
        }

        let bpm = Int(hr)
        if hr < 50 {
            return HealthInsight(
                headline: "Very low heart rate",
                detail: "\(bpm) BPM — common in athletes, but worth mentioning to a doctor if unusual for you.",
                status: .fair
            )
        } else if hr < 62 {
            return HealthInsight(
                headline: "Excellent resting rate",
                detail: "\(bpm) BPM — a sign of good cardiovascular fitness.",
                status: .great
            )
        } else if hr <= 100 {
            return HealthInsight(
                headline: "Normal and steady",
                detail: "\(bpm) BPM — right in the healthy range. Nothing to worry about.",
                status: .good
            )
        } else if hr <= 120 {
            return HealthInsight(
                headline: "Slightly elevated",
                detail: "\(bpm) BPM — stress, caffeine, or recent activity could explain this.",
                status: .fair
            )
        } else {
            return HealthInsight(
                headline: "Heart rate is high",
                detail: "\(bpm) BPM — take a moment to rest and breathe. Persistent readings need attention.",
                status: .low
            )
        }
    }

    // MARK: - Recovery

    var recovery: HealthInsight {
        let hrv = data.heartRateVariability
        let rhr = data.restingHeartRate

        guard hrv > 0 || rhr > 0 else {
            return HealthInsight(
                headline: "No recovery data",
                detail: "Wear your watch overnight to get daily recovery insights.",
                status: .noData
            )
        }

        // High HRV + low resting HR = great recovery
        let hrvGood = hrv >= 40
        let rhrGood = rhr > 0 && rhr < 65

        if hrvGood && rhrGood {
            return HealthInsight(
                headline: "Fully recovered",
                detail: "Your nervous system is balanced and resting heart rate is low — a great day to push hard.",
                status: .great
            )
        } else if hrvGood || rhrGood {
            return HealthInsight(
                headline: "Recovered well",
                detail: "Your body is in decent shape. Moderate to hard effort is fine today.",
                status: .good
            )
        } else if hrv >= 20 || (rhr > 0 && rhr < 80) {
            return HealthInsight(
                headline: "Partially recovered",
                detail: "Light activity is the smart choice today — your body is still catching up.",
                status: .fair
            )
        } else {
            return HealthInsight(
                headline: "Rest day recommended",
                detail: "Low HRV and elevated resting heart rate suggest your body needs recovery. Take it easy.",
                status: .low
            )
        }
    }

    // MARK: - Steps

    var steps: HealthInsight {
        let count = data.steps
        let goal = data.stepGoal
        let remaining = max(0, goal - count)
        let km = String(format: "%.1f", data.distanceMeters / 1000)

        if count == 0 {
            return HealthInsight(
                headline: "No steps yet",
                detail: "Every step counts — even a short walk makes a difference.",
                status: .noData
            )
        } else if count >= goal {
            return HealthInsight(
                headline: "Step goal crushed!",
                detail: "\(count.formatted()) steps — that's \(km) km walked today.",
                status: .great
            )
        } else if remaining <= 1500 {
            return HealthInsight(
                headline: "Almost at your goal",
                detail: "Just \(remaining.formatted()) more steps — a 10-minute walk will do it.",
                status: .good
            )
        } else if count >= 5000 {
            return HealthInsight(
                headline: "Solid progress",
                detail: "\(count.formatted()) steps (\(km) km) — \(remaining.formatted()) to reach your goal.",
                status: .fair
            )
        } else {
            return HealthInsight(
                headline: "Light day so far",
                detail: "\(count.formatted()) steps — a walk after meals would help close the gap.",
                status: .low
            )
        }
    }

    // MARK: - Workouts

    var workoutHeadline: String? {
        guard !data.workouts.isEmpty else { return nil }
        if data.workouts.count == 1 {
            let w = data.workouts[0]
            return "\(w.displayName) · \(Int(w.durationMinutes)) min · \(Int(w.activeEnergyKcal)) Cal"
        }
        let totalCal = Int(data.workouts.reduce(0) { $0 + $1.activeEnergyKcal })
        return "\(data.workouts.count) workouts · \(totalCal) Cal burned"
    }

    // MARK: - Helpers

    private func formatHours(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }
}
