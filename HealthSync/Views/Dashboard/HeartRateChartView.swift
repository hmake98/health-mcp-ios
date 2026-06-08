import SwiftUI
import Charts

struct HeartRateChartView: View {
    let samples: [HeartRateSample]
    let current: Double
    let min: Double
    let max: Double
    let avg: Double
    let resting: Double

    private var chartDomain: ClosedRange<Double> {
        let low = (min > 0 ? min - 10 : 40)
        let high = max > 0 ? max + 10 : 120
        return low...high
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if current > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(current))")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                    Text("BPM")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                    Spacer()
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse)
                }
            }

            if !samples.isEmpty {
                Chart {
                    ForEach(samples) { sample in
                        LineMark(
                            x: .value("Time", sample.date),
                            y: .value("BPM", sample.value)
                        )
                        .foregroundStyle(.red.gradient)
                        .interpolationMethod(.catmullRom)

                        AreaMark(
                            x: .value("Time", sample.date),
                            y: .value("BPM", sample.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.red.opacity(0.2), .red.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: chartDomain)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                        AxisValueLabel(format: .dateTime.hour())
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .stride(by: 20)) { value in
                        AxisValueLabel()
                            .font(.caption2)
                    }
                    AxisMarks(position: .trailing) {
                        AxisGridLine()
                    }
                }
                .frame(height: 80)

                HStack(spacing: 16) {
                    MiniStat(label: "Min", value: min > 0 ? "\(Int(min))" : "—")
                    MiniStat(label: "Avg", value: avg > 0 ? "\(Int(avg))" : "—")
                    MiniStat(label: "Max", value: max > 0 ? "\(Int(max))" : "—")
                    if resting > 0 {
                        Divider().frame(height: 28)
                        MiniStat(label: "Resting", value: "\(Int(resting))")
                    }
                }
            } else if current > 0 {
                EmptyMetricView(message: "No recent samples")
            } else {
                EmptyMetricView(message: "No heart rate data today")
            }
        }
    }
}

private struct MiniStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
    }
}
