import Foundation

struct SyncIntervalOption: Identifiable {
    let id: Int
    let label: String
    let minutes: Int
}

final class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let syncIntervalMinutes = "syncIntervalMinutes"
        static let lastSyncDate = "lastSyncDate"
        static let lastVitalsSyncDate = "lastVitalsSyncDate"
        static let lastSleepSyncDate = "lastSleepSyncDate"
        static let lastWorkoutsSyncDate = "lastWorkoutsSyncDate"
        static let hasRequestedHKAuthorization = "hasRequestedHKAuthorization"
    }

    var hasRequestedHKAuthorization: Bool {
        get { defaults.bool(forKey: Key.hasRequestedHKAuthorization) }
        set { defaults.set(newValue, forKey: Key.hasRequestedHKAuthorization) }
    }

    var syncIntervalMinutes: Int {
        get {
            let v = defaults.integer(forKey: Key.syncIntervalMinutes)
            return v == 0 ? 60 : v
        }
        set { defaults.set(newValue, forKey: Key.syncIntervalMinutes) }
    }

    var lastSyncDate: Date? {
        get { defaults.object(forKey: Key.lastSyncDate) as? Date }
        set { defaults.set(newValue, forKey: Key.lastSyncDate) }
    }

    var lastVitalsSyncDate: Date? {
        get { defaults.object(forKey: Key.lastVitalsSyncDate) as? Date }
        set { defaults.set(newValue, forKey: Key.lastVitalsSyncDate) }
    }

    var lastSleepSyncDate: Date? {
        get { defaults.object(forKey: Key.lastSleepSyncDate) as? Date }
        set { defaults.set(newValue, forKey: Key.lastSleepSyncDate) }
    }

    var lastWorkoutsSyncDate: Date? {
        get { defaults.object(forKey: Key.lastWorkoutsSyncDate) as? Date }
        set { defaults.set(newValue, forKey: Key.lastWorkoutsSyncDate) }
    }

    func updateVitalsSyncDate(_ date: Date) { lastVitalsSyncDate = date }
    func updateSleepSyncDate(_ date: Date) { lastSleepSyncDate = date }
    func updateWorkoutsSyncDate(_ date: Date) { lastWorkoutsSyncDate = date }

    func clearSyncDates() {
        [Key.lastSyncDate, Key.lastVitalsSyncDate, Key.lastSleepSyncDate, Key.lastWorkoutsSyncDate].forEach {
            defaults.removeObject(forKey: $0)
        }
    }

    func defaultSyncStartDate() -> Date {
        Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    }

    static let intervalOptions: [SyncIntervalOption] = [
        SyncIntervalOption(id: 15, label: "15 minutes", minutes: 15),
        SyncIntervalOption(id: 30, label: "30 minutes", minutes: 30),
        SyncIntervalOption(id: 60, label: "1 hour", minutes: 60),
        SyncIntervalOption(id: 120, label: "2 hours", minutes: 120),
        SyncIntervalOption(id: 240, label: "4 hours", minutes: 240),
        SyncIntervalOption(id: 480, label: "8 hours", minutes: 480),
        SyncIntervalOption(id: 0, label: "Manual only", minutes: 0),
    ]

    var currentIntervalLabel: String {
        AppSettings.intervalOptions.first(where: { $0.minutes == syncIntervalMinutes })?.label ?? "1 hour"
    }
}
