import SwiftUI

struct ContentView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var syncService

    var body: some View {
        if auth.isAuthenticated {
            mainTabs
                .task { await requestHealthKitPermissions() }
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

    private func requestHealthKitPermissions() async {
        guard HealthKitService.isAvailable else { return }
        try? await HealthKitService.shared.requestAuthorization()
    }
}
