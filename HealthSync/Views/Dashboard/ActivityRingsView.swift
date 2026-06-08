import SwiftUI

struct ActivityRingsView: View {
    let moveProgress: Double
    let exerciseProgress: Double
    let standProgress: Double
    let moveKcal: Double
    let exerciseMinutes: Int
    let standHours: Int
    let moveGoal: Double
    let exerciseGoal: Int
    let standGoal: Int

    private let ringLineWidth: CGFloat = 14
    private let ringSpacing: CGFloat = 6

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                RingLayer(progress: standProgress, color: .cyan, size: 3, lineWidth: ringLineWidth, spacing: ringSpacing)
                RingLayer(progress: exerciseProgress, color: .green, size: 2, lineWidth: ringLineWidth, spacing: ringSpacing)
                RingLayer(progress: moveProgress, color: .red, size: 1, lineWidth: ringLineWidth, spacing: ringSpacing)
            }
            .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: 10) {
                RingLegendRow(
                    color: .red,
                    label: "Move",
                    value: "\(Int(moveKcal)) / \(Int(moveGoal)) Cal"
                )
                RingLegendRow(
                    color: .green,
                    label: "Exercise",
                    value: "\(exerciseMinutes) / \(exerciseGoal) min"
                )
                RingLegendRow(
                    color: .cyan,
                    label: "Stand",
                    value: "\(standHours) / \(standGoal) hr"
                )
            }
        }
    }
}

private struct RingLayer: View {
    let progress: Double
    let color: Color
    let size: Int
    let lineWidth: CGFloat
    let spacing: CGFloat

    private var diameter: CGFloat {
        let base: CGFloat = 120
        let offset = CGFloat(3 - size) * (lineWidth + spacing)
        return base - offset * 2
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
                .frame(width: diameter, height: diameter)

            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [color, color.opacity(0.7)]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: progress)

            // Completion dot when over 100%
            if progress >= 1.0 {
                Circle()
                    .fill(color)
                    .frame(width: lineWidth, height: lineWidth)
                    .offset(y: -diameter / 2)
            }
        }
    }
}

private struct RingLegendRow: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
        }
    }
}
