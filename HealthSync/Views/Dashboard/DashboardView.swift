import SwiftUI

// MARK: - HealthStatus

private enum HealthStatus {
    case optimal, good, fair, poor

    var label: String {
        switch self {
        case .optimal: return "Optimal"
        case .good:    return "Good"
        case .fair:    return "Fair"
        case .poor:    return "Poor"
        }
    }

    var color: Color {
        switch self {
        case .optimal: return .green
        case .good:    return Color(red: 0.2, green: 0.55, blue: 1.0)
        case .fair:    return .orange
        case .poor:    return .red
        }
    }
}

// MARK: - DashboardView

struct DashboardView: View {
    @State private var data = DashboardData()
    @State private var isRefreshing = false
    @Environment(SyncService.self) private var syncService
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    syncStatusRow
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 16)

                    // MARK: Cardiovascular
                    SectionHeader("Cardiovascular")
                    rhrCard
                        .padding(.horizontal, 16)
                    HStack(alignment: .top, spacing: 12) {
                        hrvCard
                        walkingHRCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    vo2MaxCard
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    // MARK: Sleep
                    SectionHeader("Sleep")
                    sleepHealthCard
                        .padding(.horizontal, 16)

                    // MARK: Movement
                    SectionHeader("Movement")
                    HStack(alignment: .top, spacing: 12) {
                        stepsCard
                        activeEnergyCard
                    }
                    .padding(.horizontal, 16)

                    // MARK: Workouts
                    if !data.workouts.isEmpty {
                        SectionHeader("Workouts")
                        workoutsCard
                            .padding(.horizontal, 16)
                    }

                    Spacer().frame(height: 40)
                }
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

    // MARK: - Sync Status Row

    private var syncStatusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(syncDotColor)
                .frame(width: 7, height: 7)
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
    }

    private var syncDotColor: Color {
        if syncService.isSyncing { return .blue }
        guard let last = syncService.lastSyncDate else { return .secondary }
        let age = Date().timeIntervalSince(last)
        if age < 3600  { return .green }
        if age < 14400 { return .yellow }
        return .orange
    }

    // MARK: - Resting Heart Rate Card

    private var rhrCard: some View {
        let rhr = data.freshRestingHR
        return HealthMetricCard(
            icon: "heart.fill",
            iconColor: .red,
            title: "Resting Heart Rate",
            value: rhr.map { "\(Int($0.value))" } ?? "--",
            unit: rhr != nil ? "BPM" : "",
            description: "Cardiovascular fitness · recovery · stress",
            status: rhr.map { rhrStatus($0.value) },
            age: rhr?.ageString
        )
    }

    private func rhrStatus(_ bpm: Double) -> HealthStatus {
        if bpm < 40 || bpm > 100 { return .poor }
        if bpm <= 60              { return .optimal }
        if bpm <= 80              { return .good }
        return .fair
    }

    // MARK: - HRV Card

    private var hrvCard: some View {
        let hrv = data.freshHRV
        return CompactMetricCard(
            icon: "waveform.path.ecg",
            iconColor: .purple,
            title: "HRV",
            value: hrv.map { "\(Int($0.value))" } ?? "--",
            unit: hrv != nil ? "ms" : "",
            description: "Recovery · nervous system balance · stress",
            status: hrv.map { hrvStatus($0.value) },
            age: hrv?.ageString
        )
    }

    private func hrvStatus(_ ms: Double) -> HealthStatus {
        if ms >= 55 { return .optimal }
        if ms >= 40 { return .good }
        if ms >= 25 { return .fair }
        return .poor
    }

    // MARK: - Walking HR Average Card

    private var walkingHRCard: some View {
        let whr = data.freshWalkingHRAvg
        return CompactMetricCard(
            icon: "figure.walk",
            iconColor: .teal,
            title: "Walking HR Avg",
            value: whr.map { "\(Int($0.value))" } ?? "--",
            unit: whr != nil ? "BPM" : "",
            description: "Cardiovascular efficiency",
            status: whr.map { walkingHRStatus($0.value) },
            age: whr?.ageString
        )
    }

    private func walkingHRStatus(_ bpm: Double) -> HealthStatus {
        if bpm < 70  { return .optimal }
        if bpm < 85  { return .good }
        if bpm < 100 { return .fair }
        return .poor
    }

    // MARK: - VO2 Max Card

    private var vo2MaxCard: some View {
        let vo2 = data.freshVo2Max
        return HealthMetricCard(
            icon: "lungs.fill",
            iconColor: .cyan,
            title: "Cardio Fitness  ·  VO₂ Max",
            value: vo2.map { String(format: "%.1f", $0.value) } ?? "--",
            unit: vo2 != nil ? "mL/kg/min" : "",
            description: "Strong predictor of long-term health & longevity",
            status: vo2.map { vo2Status($0.value) },
            age: vo2?.ageString
        )
    }

    private func vo2Status(_ ml: Double) -> HealthStatus {
        if ml >= 50 { return .optimal }
        if ml >= 38 { return .good }
        if ml >= 28 { return .fair }
        return .poor
    }

    // MARK: - Sleep Card

    @ViewBuilder
    private var sleepHealthCard: some View {
        DashCard(title: "Sleep", icon: "moon.fill", iconColor: .indigo) {
            if let sleep = data.sleepSummary {
                VStack(alignment: .leading, spacing: 14) {
                    // Duration row
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .center, spacing: 8) {
                                Text(sleepDurationLabel(sleep))
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                if let status = sleepStatus(sleep.totalAsleepHours) {
                                    StatusBadge(status: status)
                                }
                            }
                            Text("Recovery foundation")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let bed = sleep.bedtime, let wake = sleep.wakeTime {
                            VStack(alignment: .trailing, spacing: 4) {
                                Label(bed.formatted(date: .omitted, time: .shortened), systemImage: "moon.zzz")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Image(systemName: "arrow.down")
                                    .font(.caption2).foregroundStyle(.tertiary)
                                Label(wake.formatted(date: .omitted, time: .shortened), systemImage: "sun.horizon")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Consistency row
                    if let consistency = data.sleepConsistency {
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text("CONSISTENCY")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .tracking(0.5)
                                Spacer()
                                Text("\(consistency.nightsAnalyzed) nights")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(consistency.label)
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundStyle(consistency.color)
                            Text("Often more important than total sleep duration")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Stage bar
                    Divider()
                    SleepStagesView(summary: sleep)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("--")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.quaternary)
                    Text("No sleep data recorded for last night")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sleepDurationLabel(_ sleep: SleepSummary) -> String {
        let h = Int(sleep.totalAsleepHours)
        let m = Int((sleep.totalAsleepHours - Double(h)) * 60)
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    private func sleepStatus(_ hours: Double) -> HealthStatus? {
        guard hours > 0 else { return nil }
        if hours >= 7 && hours <= 9 { return .optimal }
        if hours >= 6               { return .good }
        if hours >= 5               { return .fair }
        return .poor
    }

    // MARK: - Daily Steps Card

    private var stepsCard: some View {
        CompactMetricCard(
            icon: "shoeprints.fill",
            iconColor: .green,
            title: "Daily Steps",
            value: data.steps > 0 ? data.steps.formatted() : "--",
            unit: "",
            description: "Activity baseline",
            status: data.steps > 0 ? stepsStatus(data.steps) : nil,
            age: nil
        )
    }

    private func stepsStatus(_ steps: Int) -> HealthStatus {
        if steps >= 10000 { return .optimal }
        if steps >= 7500  { return .good }
        if steps >= 5000  { return .fair }
        return .poor
    }

    // MARK: - Active Energy Card

    private var activeEnergyCard: some View {
        CompactMetricCard(
            icon: "flame.fill",
            iconColor: .orange,
            title: "Active Energy",
            value: data.activeEnergyKcal > 0 ? "\(Int(data.activeEnergyKcal))" : "--",
            unit: data.activeEnergyKcal > 0 ? "Cal" : "",
            description: "Daily movement load",
            status: data.activeEnergyKcal > 0 ? energyStatus(data.activeEnergyKcal) : nil,
            age: nil
        )
    }

    private func energyStatus(_ kcal: Double) -> HealthStatus {
        if kcal >= 600 { return .optimal }
        if kcal >= 400 { return .good }
        if kcal >= 200 { return .fair }
        return .poor
    }

    // MARK: - Workouts Card

    private var workoutsCard: some View {
        DashCard(title: "Today", icon: "figure.run", iconColor: .green) {
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

    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good Morning" }
        if hour < 17 { return "Good Afternoon" }
        return "Good Evening"
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        HStack(spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(Color.secondary.opacity(0.25))
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .padding(.bottom, 12)
    }
}

// MARK: - StatusBadge

private struct StatusBadge: View {
    let status: HealthStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 5, height: 5)
            Text(status.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(status.color.opacity(0.12), in: Capsule())
    }
}

// MARK: - HealthMetricCard (full width)

private struct HealthMetricCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let unit: String
    let description: String
    let status: HealthStatus?
    var age: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(status != nil ? iconColor : iconColor.opacity(0.35))
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                Spacer()
                if let age {
                    Text(age)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(value)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(status != nil ? .primary : .quaternary)
                if !unit.isEmpty {
                    Text(" \(unit)")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)
                }
                Spacer()
                if let status {
                    StatusBadge(status: status)
                }
            }

            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - CompactMetricCard (half width, used in 2-column HStack)

private struct CompactMetricCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let unit: String
    let description: String
    let status: HealthStatus?
    var age: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(status != nil ? iconColor : iconColor.opacity(0.35))
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
            }

            Spacer().frame(height: 10)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(status != nil ? .primary : .quaternary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer().frame(height: 6)

            if let status {
                StatusBadge(status: status)
            }

            Spacer(minLength: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let age {
                    Text(age)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

#Preview {
    DashboardView()
        .environment(SyncService.shared)
}
