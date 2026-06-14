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
                    switch newPhase {
                    case .active:
                        // Re-register observers in case the process was relaunched in background.
                        syncService.setupBackgroundObservers()
                    case .background:
                        // Schedule right as the app enters background so the task is queued
                        // even if the user never returns to the foreground.
                        syncService.scheduleBackgroundSync()
                    default:
                        break
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
        // Observers and scheduling are driven by scenePhase changes (.active / .background).
        // Kick off the first schedule + observer registration here for the initial launch.
        syncService.setupBackgroundObservers()
        syncService.scheduleBackgroundSync()
    }
}
