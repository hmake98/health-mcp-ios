import SwiftUI
import BackgroundTasks

@main
struct HealthSyncApp: App {
    @State private var authService = AuthService.shared
    @State private var syncService = SyncService.shared

    init() {
        registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .environment(syncService)
        }
    }

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: SyncService.backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            SyncService.shared.handleBackgroundSync(task: refreshTask)
        }
    }
}
