import SwiftUI

struct AccountView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var syncService
    @State private var syncIntervalMinutes = AppSettings.shared.syncIntervalMinutes
    @State private var showClearLogsAlert = false
    @State private var showSignOutAlert = false
    @State private var showResetAlert = false
    @State private var serverOnline: Bool? = nil
    @State private var isCheckingServer = false

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                syncSection
                serverSection
                historySection
                dangerSection
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Profile

    private var profileSection: some View {
        Section {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Text(auth.avatarInitials.isEmpty ? "?" : auth.avatarInitials)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.displayName)
                        .font(.headline)
                    if !auth.displayEmail.isEmpty {
                        Text(auth.displayEmail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Sync

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
                        ProgressView()
                    }
                }
            }
            .disabled(syncService.isSyncing)

            if let lastSync = syncService.lastSyncDate {
                LabeledContent("Last Synced") {
                    Text(lastSync, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Server

    private var serverSection: some View {
        Section {
            HStack {
                Label("Server", systemImage: "server.rack")
                Spacer()
                if isCheckingServer {
                    ProgressView()
                } else if let online = serverOnline {
                    Label(online ? "Connected" : "Unreachable",
                          systemImage: online ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(online ? .green : .red)
                        .font(.subheadline)
                } else {
                    Text("Tap to check")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { Task { await checkServer() } }
        } footer: {
            Text("Tap to check server connectivity.")
        }
        .task { await checkServer() }
    }

    // MARK: - History

    @ViewBuilder
    private var historySection: some View {
        Section("History") {
            if syncService.recentLogs.isEmpty {
                Text("No sync history yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(syncService.recentLogs.prefix(5)) { log in
                    LabeledContent {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(log.recordsSynced) records")
                                .font(.subheadline)
                            Text(log.formattedDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Label {
                            Text(log.type.rawValue)
                        } icon: {
                            Image(systemName: log.statusIcon)
                                .foregroundStyle(log.statusColor)
                        }
                    }
                }
                NavigationLink {
                    LogsView()
                } label: {
                    Label("View All Logs", systemImage: "list.bullet.rectangle")
                }
            }
        }
    }

    // MARK: - Danger Zone

    private var dangerSection: some View {
        Section {
            LabeledContent("Version",
                value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")

            Button(role: .destructive) {
                showResetAlert = true
            } label: {
                Label("Reset & Full Sync from Scratch", systemImage: "arrow.counterclockwise.icloud")
            }
            .disabled(syncService.isSyncing)
            .alert("Reset All Health Data?", isPresented: $showResetAlert) {
                Button("Reset & Sync", role: .destructive) {
                    Task { await syncService.resetAndSyncFromScratch() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deletes all health data from the server and re-syncs everything from Apple Health. Use this to fix accuracy issues.")
            }

            Button(role: .destructive) {
                showClearLogsAlert = true
            } label: {
                Label("Clear Sync History", systemImage: "trash")
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
        } footer: {
            Text("Resetting will re-sync up to 30 days of Apple Health data.")
        }
    }

    // MARK: - Helpers

    private func checkServer() async {
        isCheckingServer = true
        serverOnline = await APIClient.shared.checkHealth()
        isCheckingServer = false
    }
}

#Preview {
    AccountView()
        .environment(AuthService.shared)
        .environment(SyncService.shared)
}
