import SwiftUI

struct DashboardView: View {
    @State private var data = DashboardData()
    @State private var isRefreshing = false
    @Environment(SyncService.self) private var syncService

    private var insights: HealthInsights { HealthInsights(data: data) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    overviewCard
                    if data.sleepSummary != nil || !data.isLoading {
                        sleepCard
                    }
                    activityCard
                    heartCard
                    recoveryCard
                    stepsCard
                    if !data.workouts.isEmpty {
                        workoutsCard
                    }
                    if data.bloodOxygen > 0 || data.respiratoryRate > 0 {
                        vitalsCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .navigationTitle(insights.greeting)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if isRefreshing || syncService.isSyncing {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing || syncService.isSyncing)
                }
            }
            .refreshable { await refresh() }
        }
        .task { await loadData() }
    }

    // MARK: - Overview Card

    private var overviewCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(insights.overallStatus.color.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: overallIcon)
                    .font(.system(size: 22))
                    .foregroundStyle(insights.overallStatus.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(insights.overallHeadline)
                    .font(.system(size: 17, weight: .semibold))
                if let lastSync = syncService.lastSyncDate {
                    Text("Updated \(lastSync.relativeString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if syncService.isSyncing {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.65)
                        Text("Syncing…").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(Date(), style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var overallIcon: String {
        switch insights.overallStatus {
        case .great: return "checkmark.seal.fill"
        case .good: return "heart.fill"
        case .fair: return "minus.circle.fill"
        case .low: return "exclamationmark.circle.fill"
        case .noData: return "ellipsis.circle.fill"
        }
    }

    // MARK: - Sleep Card

    private var sleepCard: some View {
        InsightCard(
            label: "Sleep",
            icon: "moon.fill",
            iconColor: .indigo,
            insight: insights.sleep
        ) {
            if let sleep = data.sleepSummary {
                VStack(spacing: 10) {
                    SleepStagesView(summary: sleep)
                }
            }
        }
    }

    // MARK: - Activity Card

    private var activityCard: some View {
        InsightCard(
            label: "Activity",
            icon: "flame.fill",
            iconColor: .red,
            insight: insights.activity
        ) {
            ActivityRingsView(
                moveProgress: data.moveProgress,
                exerciseProgress: data.exerciseProgress,
                standProgress: data.standProgress,
                moveKcal: data.activeEnergyKcal,
                exerciseMinutes: data.exerciseMinutes,
                standHours: data.standHours,
                moveGoal: data.moveGoal,
                exerciseGoal: data.exerciseGoal,
                standGoal: data.standGoal
            )
        }
    }

    // MARK: - Heart Card

    private var heartCard: some View {
        InsightCard(
            label: "Heart Rate",
            icon: "heart.fill",
            iconColor: .red,
            insight: insights.heart
        ) {
            HeartRateChartView(
                samples: data.heartRateSamples,
                current: data.currentHeartRate,
                min: data.heartRateMin,
                max: data.heartRateMax,
                avg: data.heartRateAvg,
                resting: data.restingHeartRate
            )
        }
    }

    // MARK: - Recovery Card

    private var recoveryCard: some View {
        InsightCard(
            label: "Recovery",
            icon: "bolt.heart.fill",
            iconColor: .purple,
            insight: insights.recovery
        ) {
            if data.heartRateVariability > 0 || data.restingHeartRate > 0 {
                HStack(spacing: 0) {
                    if data.heartRateVariability > 0 {
                        RecoveryMetric(
                            label: "HRV",
                            value: "\(Int(data.heartRateVariability))",
                            unit: "ms",
                            note: hrvNote
                        )
                    }
                    if data.heartRateVariability > 0 && data.restingHeartRate > 0 {
                        Divider().frame(height: 44).padding(.horizontal, 12)
                    }
                    if data.restingHeartRate > 0 {
                        RecoveryMetric(
                            label: "Resting HR",
                            value: "\(Int(data.restingHeartRate))",
                            unit: "BPM",
                            note: rhrNote
                        )
                    }
                    Spacer()
                }
            }
        }
    }

    private var hrvNote: String {
        let hrv = data.heartRateVariability
        if hrv >= 50 { return "High — great sign" }
        if hrv >= 30 { return "Moderate" }
        return "Low — rest up"
    }

    private var rhrNote: String {
        let rhr = data.restingHeartRate
        if rhr < 60 { return "Excellent" }
        if rhr < 75 { return "Normal" }
        return "Slightly elevated"
    }

    // MARK: - Steps Card

    private var stepsCard: some View {
        InsightCard(
            label: "Steps",
            icon: "figure.walk",
            iconColor: .orange,
            insight: insights.steps
        ) {
            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(data.steps.formatted())
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("/ \(data.stepGoal.formatted()) steps")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                ProgressView(value: data.stepProgress)
                    .tint(.orange)
                    .scaleEffect(y: 1.4)
                if data.distanceMeters > 0 {
                    HStack {
                        Label(String(format: "%.1f km", data.distanceMeters / 1000), systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if data.flightsClimbed > 0 {
                            Label("\(data.flightsClimbed) flights", systemImage: "stairs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Workouts Card

    private var workoutsCard: some View {
        MetricCard(title: "Workouts", icon: "figure.run", iconColor: .green) {
            VStack(spacing: 10) {
                if let headline = insights.workoutHeadline {
                    Text(headline)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(data.workouts) { workout in
                    WorkoutRow(workout: workout)
                    if workout.id != data.workouts.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Vitals Card

    private var vitalsCard: some View {
        MetricCard(title: "Vitals", icon: "waveform.path.ecg", iconColor: .pink) {
            HStack(spacing: 12) {
                if data.bloodOxygen > 0 {
                    VitalTile(
                        icon: "lungs.fill",
                        label: "Blood Oxygen",
                        value: String(format: "%.0f%%", data.bloodOxygen),
                        note: data.bloodOxygen >= 95 ? "Normal" : "Below normal",
                        color: data.bloodOxygen >= 95 ? .blue : .orange
                    )
                }
                if data.respiratoryRate > 0 {
                    VitalTile(
                        icon: "wind",
                        label: "Breathing Rate",
                        value: String(format: "%.0f", data.respiratoryRate),
                        note: "breaths / min",
                        color: .teal
                    )
                }
            }
        }
    }

    // MARK: - Loading

    private func loadData() async {
        data.isLoading = true
        data = await HealthKitService.shared.fetchDashboardData()
    }

    private func refresh() async {
        isRefreshing = true
        await loadData()
        isRefreshing = false
    }
}

// MARK: - Insight Card

private struct InsightCard<Detail: View>: View {
    let label: String
    let icon: String
    let iconColor: Color
    let insight: HealthInsight
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                Spacer()
                InsightBadge(status: insight.status)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.headline)
                    .font(.system(size: 18, weight: .semibold))
                if insight.status != .noData {
                    Text(insight.detail)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if insight.status != .noData {
                Divider()
                detail()
            } else {
                Text(insight.detail)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Insight Badge

private struct InsightBadge: View {
    let status: InsightStatus

    private var label: String {
        switch status {
        case .great: return "Great"
        case .good: return "Good"
        case .fair: return "Fair"
        case .low: return "Low"
        case .noData: return "—"
        }
    }

    var body: some View {
        if status != .noData {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(status.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(status.color.opacity(0.12), in: Capsule())
        }
    }
}

// MARK: - Recovery Metric

private struct RecoveryMetric: View {
    let label: String
    let value: String
    let unit: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(note)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Workout Row

private struct WorkoutRow: View {
    let workout: WorkoutSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.icon)
                .font(.system(size: 18))
                .foregroundStyle(.green)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(workout.displayName)
                    .font(.system(size: 15, weight: .semibold))
                Text(workout.startDate, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(workout.durationMinutes)) min")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                if workout.activeEnergyKcal > 0 {
                    Text("\(Int(workout.activeEnergyKcal)) Cal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Vitals Tile

private struct VitalTile: View {
    let icon: String
    let label: String
    let value: String
    let note: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Date helper

private extension Date {
    var relativeString: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: self, relativeTo: Date())
    }
}

#Preview {
    DashboardView()
        .environment(SyncService.shared)
}
