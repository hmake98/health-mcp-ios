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
    private var observersRegistered = false

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

        // Always cover at least the last 2 days so HealthKit retroactive updates are captured.
        let recentWindow = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()

        var totalSynced = 0
        var errors: [String] = []

        // Vitals
        let vitalsStart = min(settings.lastVitalsSyncDate ?? settings.defaultSyncStartDate(), recentWindow)
        let vitals = await healthKit.fetchVitalRecords(since: vitalsStart)
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
        let sleepStart = min(settings.lastSleepSyncDate ?? settings.defaultSyncStartDate(), recentWindow)
        let sleep = await healthKit.fetchSleepRecords(since: sleepStart)
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
        let workoutsStart = min(settings.lastWorkoutsSyncDate ?? settings.defaultSyncStartDate(), recentWindow)
        let workouts = await healthKit.fetchWorkoutRecords(since: workoutsStart)
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

        // Activity — always last 14 days, upserted by day on server
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

    // Schedule a background task to run as soon as possible (called by HealthKit observers).
    func scheduleImmediateBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = nil // run ASAP
        try? BGTaskScheduler.shared.submit(request)
    }

    // Register HKObserverQuery so iOS wakes the app when health data changes.
    // Safe to call on every launch — guarded by observersRegistered flag.
    func setupBackgroundObservers() {
        guard !observersRegistered, HealthKitService.isAvailable else { return }
        observersRegistered = true
        HealthKitService.shared.enableBackgroundDelivery {
            // Called on a HealthKit background thread — hop to main actor.
            Task { @MainActor in
                SyncService.shared.scheduleImmediateBackgroundSync()
            }
        }
    }

    nonisolated func handleBackgroundSync(task: BGAppRefreshTask) {
        let syncTask = Task { @MainActor in
            await SyncService.shared.syncNow()
            SyncService.shared.scheduleBackgroundSync()
            task.setTaskCompleted(success: true)
        }
        // Cancel the in-flight task when iOS reclaims background time.
        task.expirationHandler = {
            syncTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - Reset & Full Sync

    func resetAndSyncFromScratch() async {
        guard !isSyncing else { return }
        isSyncing = true
        do {
            try await api.clearAllHealthData()
        } catch {
            // Server clear failed — still clear local state and re-sync from scratch
        }
        settings.clearSyncDates()
        logStore.clear()
        recentLogs = []
        isSyncing = false
        await syncNow()
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
