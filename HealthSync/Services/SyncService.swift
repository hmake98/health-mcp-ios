import Foundation
import BackgroundTasks

@MainActor
@Observable
final class SyncService {
    static let shared = SyncService()
    static let backgroundTaskIdentifier = "com.hmake98.HealthSync.sync"

    var isSyncing = false
    var lastSyncDate: Date? { AppSettings.shared.lastSyncDate }
    var recentLogs: [SyncLog] = []
    var serverReachable: Bool? = nil

    private let settings = AppSettings.shared
    private let healthKit = HealthKitService.shared
    private let api = APIClient.shared
    private let logStore = SyncLogStore.shared

    init() {
        recentLogs = Array(logStore.load().suffix(20).reversed())
    }

    // MARK: - Manual Sync

    func syncNow() async {
        guard !isSyncing else { return }
        isSyncing = true

        var log = SyncLog(type: .full)
        logStore.append(log)
        let startTime = Date()

        var totalSynced = 0
        var errors: [String] = []

        // Vitals
        let vitalsStartDate = settings.lastVitalsSyncDate ?? settings.defaultSyncStartDate()
        let vitals = await healthKit.fetchVitalRecords(since: vitalsStartDate)
        if !vitals.isEmpty {
            do {
                let count = try await api.syncVitals(records: vitals)
                settings.updateVitalsSyncDate(Date())
                totalSynced += count
                log.details.append(SyncDetail(type: .vitals, recordsSynced: count))
            } catch {
                errors.append("Vitals: \(error.localizedDescription)")
                log.details.append(SyncDetail(type: .vitals, recordsSynced: 0, error: error.localizedDescription))
            }
        } else {
            log.details.append(SyncDetail(type: .vitals, recordsSynced: 0))
        }

        // Sleep
        let sleepStartDate = settings.lastSleepSyncDate ?? settings.defaultSyncStartDate()
        let sleep = await healthKit.fetchSleepRecords(since: sleepStartDate)
        if !sleep.isEmpty {
            do {
                let count = try await api.syncSleep(records: sleep)
                settings.updateSleepSyncDate(Date())
                totalSynced += count
                log.details.append(SyncDetail(type: .sleep, recordsSynced: count))
            } catch {
                errors.append("Sleep: \(error.localizedDescription)")
                log.details.append(SyncDetail(type: .sleep, recordsSynced: 0, error: error.localizedDescription))
            }
        } else {
            log.details.append(SyncDetail(type: .sleep, recordsSynced: 0))
        }

        // Workouts
        let workoutsStartDate = settings.lastWorkoutsSyncDate ?? settings.defaultSyncStartDate()
        let workouts = await healthKit.fetchWorkoutRecords(since: workoutsStartDate)
        if !workouts.isEmpty {
            do {
                let count = try await api.syncWorkouts(records: workouts)
                settings.updateWorkoutsSyncDate(Date())
                totalSynced += count
                log.details.append(SyncDetail(type: .workouts, recordsSynced: count))
            } catch {
                errors.append("Workouts: \(error.localizedDescription)")
                log.details.append(SyncDetail(type: .workouts, recordsSynced: 0, error: error.localizedDescription))
            }
        } else {
            log.details.append(SyncDetail(type: .workouts, recordsSynced: 0))
        }

        // Activity (always last 14 days — upserted by day on server)
        let activityRecords = await healthKit.fetchActivityRecords(forLast: 14)
        if !activityRecords.isEmpty {
            do {
                let count = try await api.syncActivity(records: activityRecords)
                totalSynced += count
                log.details.append(SyncDetail(type: .activity, recordsSynced: count))
            } catch {
                errors.append("Activity: \(error.localizedDescription)")
                log.details.append(SyncDetail(type: .activity, recordsSynced: 0, error: error.localizedDescription))
            }
        } else {
            log.details.append(SyncDetail(type: .activity, recordsSynced: 0))
        }

        // Finalize log
        log.durationSeconds = Date().timeIntervalSince(startTime)
        log.recordsSynced = totalSynced
        if errors.isEmpty {
            log.status = .success
        } else if totalSynced > 0 {
            log.status = .partial
            log.errorMessage = errors.joined(separator: "; ")
        } else {
            log.status = .failed
            log.errorMessage = errors.joined(separator: "; ")
        }

        settings.lastSyncDate = Date()
        logStore.update(log)
        recentLogs = Array(logStore.load().suffix(20).reversed())
        isSyncing = false
    }

    // MARK: - Background Task Scheduling

    func scheduleBackgroundSync() {
        guard settings.syncIntervalMinutes > 0 else { return }

        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Double(settings.syncIntervalMinutes) * 60)

        try? BGTaskScheduler.shared.submit(request)
    }

    nonisolated func handleBackgroundSync(task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        Task { @MainActor in
            await SyncService.shared.syncNow()
            SyncService.shared.scheduleBackgroundSync()
            task.setTaskCompleted(success: true)
        }
    }

    // MARK: - Server Health Check

    func checkServerHealth() async {
        serverReachable = await api.checkHealth()
    }

    // MARK: - Log Management

    func loadAllLogs() -> [SyncLog] {
        logStore.load().reversed()
    }

    func clearLogs() {
        logStore.clear()
        recentLogs = []
    }
}
