import Foundation

enum SyncStatus: String, Codable, CaseIterable {
    case success = "success"
    case failed = "failed"
    case partial = "partial"
    case running = "running"
}

enum SyncType: String, Codable {
    case full = "Full Sync"
    case vitals = "Vitals"
    case sleep = "Sleep"
    case workouts = "Workouts"
    case activity = "Activity"
}

struct SyncLog: Identifiable, Codable {
    let id: UUID
    let date: Date
    let type: SyncType
    var status: SyncStatus
    var recordsSynced: Int
    var errorMessage: String?
    var durationSeconds: Double
    var details: [SyncDetail]

    init(type: SyncType = .full) {
        self.id = UUID()
        self.date = Date()
        self.type = type
        self.status = .running
        self.recordsSynced = 0
        self.errorMessage = nil
        self.durationSeconds = 0
        self.details = []
    }

    var statusIcon: String {
        switch status {
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .partial: return "exclamationmark.circle.fill"
        case .running: return "arrow.trianglehead.2.counterclockwise.rotate.90.circle.fill"
        }
    }

    var statusColor: String {
        switch status {
        case .success: return "green"
        case .failed: return "red"
        case .partial: return "orange"
        case .running: return "blue"
        }
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var formattedDuration: String {
        if durationSeconds < 1 { return "<1s" }
        if durationSeconds < 60 { return "\(Int(durationSeconds))s" }
        return "\(Int(durationSeconds / 60))m \(Int(durationSeconds.truncatingRemainder(dividingBy: 60)))s"
    }
}

struct SyncDetail: Codable, Identifiable {
    let id: UUID
    let type: SyncType
    let recordsSynced: Int
    let error: String?

    init(type: SyncType, recordsSynced: Int, error: String? = nil) {
        self.id = UUID()
        self.type = type
        self.recordsSynced = recordsSynced
        self.error = error
    }
}

// MARK: - Persistence

final class SyncLogStore {
    static let shared = SyncLogStore()

    private let key = "syncLogs"
    private let maxLogs = 500
    private let defaults = UserDefaults.standard

    func load() -> [SyncLog] {
        guard let data = defaults.data(forKey: key),
              let logs = try? JSONDecoder().decode([SyncLog].self, from: data) else {
            return []
        }
        return logs
    }

    func save(_ logs: [SyncLog]) {
        let trimmed = Array(logs.suffix(maxLogs))
        if let data = try? JSONEncoder().encode(trimmed) {
            defaults.set(data, forKey: key)
        }
    }

    func append(_ log: SyncLog) {
        var logs = load()
        if let idx = logs.firstIndex(where: { $0.id == log.id }) {
            logs[idx] = log
        } else {
            logs.append(log)
        }
        save(logs)
    }

    func update(_ log: SyncLog) {
        var logs = load()
        if let idx = logs.firstIndex(where: { $0.id == log.id }) {
            logs[idx] = log
        }
        save(logs)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
