import Foundation
import BackgroundTasks
import os

private let logger = Logger(subsystem: "com.hmake98.HealthSync", category: "SyncService")

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
        logger.info("syncNow started")

        var log = SyncLog(type: .full)
        logStore.append(log)
        let startTime = Date()

        // 4-hour overlap catches Apple Watch retroactive writes without re-sending days of data.
        // Records carry a sourceId (HealthKit UUID) so the server can upsert safely if the
        // same sample arrives in two consecutive syncs within the overlap window.
        let overlapWindow = Date(timeIntervalSinceNow: -4 * 3600)

        var totalSynced = 0
        var errors: [String] = []

        // Vitals
        let vitalsStart = min(settings.lastVitalsSyncDate ?? settings.defaultSyncStartDate(), overlapWindow)
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
        let sleepStart = min(settings.lastSleepSyncDate ?? settings.defaultSyncStartDate(), overlapWindow)
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
        let workoutsStart = min(settings.lastWorkoutsSyncDate ?? settings.defaultSyncStartDate(), overlapWindow)
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

        // Activity — daily aggregates keyed by date; send today + yesterday so in-progress
        // days stay current without re-blasting the full historical window every sync.
        let activityDays = settings.lastActivitySyncDate == nil ? 30 : 2
        let activityRecords = await healthKit.fetchActivityRecords(forLast: activityDays)
        if !activityRecords.isEmpty {
            do {
                let count = try await api.syncActivity(records: activityRecords)
                settings.updateActivitySyncDate(Date())
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
        logger.info("syncNow finished — status: \(log.status.rawValue), records: \(totalSynced)")
    }

    // MARK: - Background Task Scheduling

    func scheduleBackgroundSync() {
        guard settings.syncIntervalMinutes > 0 else {
            logger.info("scheduleBackgroundSync skipped — manual-only mode")
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Double(settings.syncIntervalMinutes) * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled background sync in \(self.settings.syncIntervalMinutes) min")
        } catch {
            logger.error("Failed to schedule background sync: \(error)")
        }
    }

    // Schedule a background task to run as soon as possible (called by HealthKit observers).
    func scheduleImmediateBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = nil // run ASAP
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled immediate background sync (HealthKit trigger)")
        } catch {
            logger.error("Failed to schedule immediate background sync: \(error)")
        }
    }

    // Register HKObserverQuery so iOS wakes the app when health data changes.
    // Safe to call on every launch — guarded by observersRegistered flag.
    func setupBackgroundObservers() {
        guard !observersRegistered, HealthKitService.isAvailable else {
            logger.debug("setupBackgroundObservers skipped (already registered or HK unavailable)")
            return
        }
        observersRegistered = true
        logger.info("Registering HealthKit background observers")
        HealthKitService.shared.enableBackgroundDelivery {
            // Called on a HealthKit background thread — hop to main actor.
            Task { @MainActor in
                SyncService.shared.scheduleImmediateBackgroundSync()
            }
        }
    }

    nonisolated func handleBackgroundSync(task: BGAppRefreshTask) {
        logger.info("Background task started: \(Self.backgroundTaskIdentifier)")
        let syncTask = Task { @MainActor in
            SyncService.shared.setupBackgroundObservers()
            await SyncService.shared.syncNow()
            SyncService.shared.scheduleBackgroundSync()
            // Guard against calling setTaskCompleted after the expiration handler already fired.
            if !Task.isCancelled {
                logger.info("Background task completed successfully")
                task.setTaskCompleted(success: true)
            }
        }
        task.expirationHandler = {
            logger.warning("Background task expired before completion — rescheduling")
            syncTask.cancel()
            // Keep the chain alive even when this run expired.
            Task { @MainActor in
                SyncService.shared.scheduleBackgroundSync()
            }
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
