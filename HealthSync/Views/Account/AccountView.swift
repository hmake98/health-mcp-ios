import SwiftUI

struct AccountView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var syncService
    @State private var syncIntervalMinutes = AppSettings.shared.syncIntervalMinutes
    @State private var showClearLogsAlert = false
    @State private var showSignOutAlert = false
    @State private var serverOnline: Bool? = nil
    @State private var isCheckingServer = false

    var body: some View {
        NavigationStack {
            List {
                userSection
                syncSection
                statusSection
                historySection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - User Section

    private var userSection: some View {
        Section {
            HStack(spacing: 14) {
                avatarView
                VStack(alignment: .leading, spacing: 3) {
                    Text(auth.displayName)
                        .font(.system(size: 17, weight: .semibold))
                    if !auth.displayEmail.isEmpty {
                        Text(auth.displayEmail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.12))
                .frame(width: 52, height: 52)
            Text(auth.avatarInitials.isEmpty ? "?" : auth.avatarInitials)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.red)
        }
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        Section("Sync") {
            Picker(selection: $syncIntervalMinutes) {
                ForEach(AppSettings.intervalOptions) { option in
                    Text(option.label).tag(option.minutes)
                }
            } label: {
                Label("Interval", systemImage: "clock.arrow.2.circlepath")
            }
            .onChange(of: syncIntervalMinutes) { _, v in
                AppSettings.shared.syncIntervalMinutes = v
                if v > 0 { syncService.scheduleBackgroundSync() }
            }

            Button {
                Task { await syncService.syncNow() }
            } label: {
                HStack {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if syncService.isSyncing {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .disabled(syncService.isSyncing)

            if let lastSync = syncService.lastSyncDate {
                HStack {
                    Label("Last Synced", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(lastSync, style: .relative)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section {
            HStack {
                Label("Server", systemImage: "server.rack")
                Spacer()
                if isCheckingServer {
                    ProgressView().scaleEffect(0.8)
                } else if let online = serverOnline {
                    Image(systemName: online ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(online ? .green : .red)
                    Text(online ? "Connected" : "Unreachable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { Task { await checkServer() } }
            .onAppear { Task { await checkServer() } }
        }
    }

    // MARK: - History Section

    @ViewBuilder
    private var historySection: some View {
        Section("History") {
            let logs = syncService.recentLogs
            if logs.isEmpty {
                Text("No sync history yet")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(logs.prefix(5)) { log in
                    RecentLogRow(log: log)
                }
                NavigationLink {
                    LogsView()
                } label: {
                    Label("View All Logs", systemImage: "list.bullet.rectangle")
                }
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Label("Version", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            Button(role: .destructive) {
                showClearLogsAlert = true
            } label: {
                Label("Clear History", systemImage: "trash")
            }
            .alert("Clear History?", isPresented: $showClearLogsAlert) {
                Button("Clear", role: .destructive) { syncService.clearLogs() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All sync history will be deleted.")
            }

            Button(role: .destructive) {
                showSignOutAlert = true
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .alert("Sign Out?", isPresented: $showSignOutAlert) {
                Button("Sign Out", role: .destructive) { auth.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will need to sign in again to sync your data.")
            }
        }
    }

    // MARK: - Helpers

    private func checkServer() async {
        isCheckingServer = true
        serverOnline = await APIClient.shared.checkHealth()
        isCheckingServer = false
    }
}

// MARK: - Recent Log Row

private struct RecentLogRow: View {
    let log: SyncLog

    private var statusColor: Color {
        switch log.status {
        case .success: return .green
        case .failed: return .red
        case .partial: return .orange
        case .running: return .blue
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: log.statusIcon)
                .foregroundStyle(statusColor)
                .font(.system(size: 14))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(log.type.rawValue)
                    .font(.system(size: 14, weight: .medium))
                Text(log.formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(log.recordsSynced)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("records")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    AccountView()
        .environment(AuthService.shared)
        .environment(SyncService.shared)
}
