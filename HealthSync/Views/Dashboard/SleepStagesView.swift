import SwiftUI
import Charts

struct SleepStagesView: View {
    let summary: SleepSummary

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", summary.totalAsleepHours))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.indigo)
                Text("hr")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                Spacer()
                Text(summary.quality)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(summary.qualityColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(summary.qualityColor.opacity(0.12), in: Capsule())
            }

            if let bedtime = summary.bedtime, let wakeTime = summary.wakeTime {
                HStack(spacing: 12) {
                    Label(timeFormatter.string(from: bedtime), systemImage: "moon.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Label(timeFormatter.string(from: wakeTime), systemImage: "sun.and.horizon.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SleepTimelineView(stages: summary.stages)

            HStack(spacing: 12) {
                SleepStagePill(label: "Deep", minutes: summary.deepMinutes, color: Color(red: 0.2, green: 0.4, blue: 0.9))
                SleepStagePill(label: "REM", minutes: summary.remMinutes, color: Color(red: 0.6, green: 0.2, blue: 0.9))
                SleepStagePill(label: "Core", minutes: summary.coreMinutes, color: Color(red: 0.2, green: 0.6, blue: 0.9))
            }
        }
    }
}

private struct SleepTimelineView: View {
    let stages: [SleepStageSegment]

    private var sleepStages: [SleepStageSegment] {
        stages.filter { $0.stage != "inBed" }
    }

    private var totalDuration: Double {
        sleepStages.reduce(0) { $0 + $1.durationMinutes }
    }

    var body: some View {
        if !sleepStages.isEmpty && totalDuration > 0 {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(sleepStages) { segment in
                        let width = max(1, geo.size.width * (segment.durationMinutes / totalDuration))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(segment.color)
                            .frame(width: width, height: 24)
                    }
                }
            }
            .frame(height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
    }
}

private struct SleepStagePill: View {
    let label: String
    let minutes: Double
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(formatMinutes(minutes))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        }
    }

    private func formatMinutes(_ m: Double) -> String {
        if m < 60 { return "\(Int(m))m" }
        return "\(Int(m / 60))h \(Int(m.truncatingRemainder(dividingBy: 60)))m"
    }
}
