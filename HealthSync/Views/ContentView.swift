import SwiftUI

struct ContentView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var syncService
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if auth.isAuthenticated {
            mainTabs
                .task { await setup() }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // Re-schedule on every foreground in case the task was consumed.
                        syncService.scheduleBackgroundSync()
                    }
                }
        } else {
            LoginView()
        }
    }

    private var mainTabs: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "heart.text.square.fill")
                }
            AccountView()
                .tabItem {
                    Label("Account", systemImage: "person.circle.fill")
                }
        }
    }

    // Runs once when the authenticated view first appears.
    private func setup() async {
        guard HealthKitService.isAvailable else { return }
        let settings = AppSettings.shared
        if !settings.hasRequestedHKAuthorization {
            try? await HealthKitService.shared.requestAuthorization()
            settings.hasRequestedHKAuthorization = true
        }
        syncService.scheduleBackgroundSync()
        syncService.setupBackgroundObservers()
    }
}
