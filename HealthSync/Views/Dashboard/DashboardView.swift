import SwiftUI

struct DashboardView: View {
    @State private var data = DashboardData()
    @State private var isRefreshing = false
    @Environment(SyncService.self) private var syncService
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    syncStatusRow
                    activityCard
                    if data.hasHeartData {
                        heartCard
                    }
                    if data.hasVitals {
                        vitalsCard
                    }
                    if let sleep = data.sleepSummary {
                        sleepCard(sleep)
                    }
                    if !data.workouts.isEmpty {
                        workoutsCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationTitle(greetingTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if isRefreshing || data.isLoading {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing || data.isLoading)
                }
            }
            .refreshable { await refresh() }
        }
        .task { await loadData() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && !isRefreshing {
                Task { await loadData() }
            }
        }
    }

    // MARK: - Greeting

    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good Morning" }
        if hour < 17 { return "Good Afternoon" }
        return "Good Evening"
    }

    // MARK: - Sync Status Row

    private var syncStatusRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(syncDotColor)
                .frame(width: 8, height: 8)
            if syncService.isSyncing {
                Text("Syncing…").font(.caption).foregroundStyle(.secondary)
            } else if let last = syncService.lastSyncDate {
                Text("Updated \(last, style: .relative) ago").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Not yet synced").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Date(), style: .date).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
    }

    private var syncDotColor: Color {
        if syncService.isSyncing { return .blue }
        guard let last = syncService.lastSyncDate else { return .secondary }
        let age = Date().timeIntervalSince(last)
        if age < 3600 { return .green }
        if age < 14400 { return .yellow }
        return .orange
    }

    // MARK: - Activity Card

    private var activityCard: some View {
        DashCard(title: "Activity", icon: "flame.fill", iconColor: .red) {
            VStack(spacing: 12) {
                HStack(spacing: 0) {
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
                    Spacer()
                }
                Divider()
                HStack(spacing: 16) {
                    StatPill(label: "Steps", value: data.steps.formatted(), icon: "figure.walk")
                    if data.distanceMeters > 0 {
                        StatPill(label: "Distance", value: String(format: "%.1f km", data.distanceMeters / 1000), icon: "mappin")
                    }
                    if data.flightsClimbed > 0 {
                        StatPill(label: "Flights", value: "\(data.flightsClimbed)", icon: "stairs")
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Heart Card

    private var heartCard: some View {
        DashCard(title: "Heart", icon: "heart.fill", iconColor: .red) {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    if let hr = data.freshHeartRate {
                        HeartMetricTile(
                            label: "Heart Rate",
                            value: "\(Int(hr.value))",
                            unit: "BPM",
                            age: hr.ageString,
                            color: heartRateColor(hr.value)
                        )
                    }
                    if let rhr = data.freshRestingHR {
                        HeartMetricTile(
                            label: "Resting HR",
                            value: "\(Int(rhr.value))",
                            unit: "BPM",
                            age: rhr.ageString,
                            color: .secondary
                        )
                    }
                    if let hrv = data.freshHRV {
                        HeartMetricTile(
                            label: "HRV",
                            value: "\(Int(hrv.value))",
                            unit: "ms",
                            age: hrv.ageString,
                            color: hrv.value >= 50 ? .green : hrv.value >= 30 ? .orange : .red
                        )
                    }
                    Spacer()
                }
                if !data.heartRateSamples.isEmpty {
                    Divider()
                    HeartRateChartView(
                        samples: data.heartRateSamples,
                        current: data.currentHeartRate,
                        min: data.heartRateMin,
                        max: data.heartRateMax,
                        avg: data.heartRateAvg,
                        resting: data.freshRestingHR?.value ?? 0
                    )
                }
            }
        }
    }

    private func heartRateColor(_ bpm: Double) -> Color {
        if bpm < 50 || bpm > 120 { return .red }
        if bpm > 100 { return .orange }
        return .pink
    }

    // MARK: - Vitals Card

    private var vitalsCard: some View {
        DashCard(title: "Vitals", icon: "waveform.path.ecg", iconColor: .teal) {
            HStack(spacing: 16) {
                if let o2 = data.freshBloodOxygen {
                    VitalMetricTile(
                        icon: "lungs.fill",
                        label: "Blood O₂",
                        value: String(format: "%.0f%%", o2.value),
                        age: o2.ageString,
                        note: o2.value >= 95 ? "Normal" : "Below normal",
                        color: o2.value >= 95 ? .blue : .orange
                    )
                }
                if let rr = data.freshRespiratoryRate {
                    VitalMetricTile(
                        icon: "wind",
                        label: "Breathing",
                        value: String(format: "%.0f", rr.value),
                        age: rr.ageString,
                        note: "breaths/min",
                        color: .teal
                    )
                }
                Spacer()
            }
        }
    }

    // MARK: - Sleep Card

    private func sleepCard(_ sleep: SleepSummary) -> some View {
        DashCard(title: "Sleep", icon: "moon.fill", iconColor: .indigo) {
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.1f", sleep.totalAsleepHours))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                            Text("hrs").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text(sleep.quality)
                            .font(.caption)
                            .foregroundStyle(sleep.qualityColor)
                    }
                    Spacer()
                    if let bed = sleep.bedtime, let wake = sleep.wakeTime {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(bed, format: .dateTime.hour().minute())
                                .font(.caption2).foregroundStyle(.secondary)
                            Image(systemName: "arrow.down")
                                .font(.caption2).foregroundStyle(.tertiary)
                            Text(wake, format: .dateTime.hour().minute())
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
                SleepStagesView(summary: sleep)
            }
        }
    }

    // MARK: - Workouts Card

    private var workoutsCard: some View {
        DashCard(title: "Workouts", icon: "figure.run", iconColor: .green) {
            VStack(spacing: 10) {
                ForEach(data.workouts) { workout in
                    WorkoutRow(workout: workout)
                    if workout.id != data.workouts.last?.id { Divider() }
                }
            }
        }
    }

    // MARK: - Load / Refresh

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

// MARK: - DashCard container

private struct DashCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                Spacer()
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Heart metric tile (with measurement age)

private struct HeartMetricTile: View {
    let label: String
    let value: String
    let unit: String
    let age: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text(age)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Vital metric tile (with measurement age)

private struct VitalMetricTile: View {
    let icon: String
    let label: String
    let value: String
    let age: String
    let note: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                HStack(spacing: 4) {
                    Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(age).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - StatPill

private struct StatPill: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(label)
                .font(.system(size: 10))
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
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(workout.durationMinutes)) min")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                if workout.activeEnergyKcal > 0 {
                    Text("\(Int(workout.activeEnergyKcal)) Cal")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
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
