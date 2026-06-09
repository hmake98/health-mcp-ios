import Foundation
import SwiftUI

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

    var statusColor: Color {
        switch status {
        case .success: return .green
        case .failed: return .red
        case .partial: return .orange
        case .running: return .blue
        }
    }

    // Static formatter — DateFormatter is expensive to create; reuse on main thread.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var formattedDate: String { Self.dateFormatter.string(from: date) }

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
    // In-memory cache eliminates repeated JSON decoding on every read.
    private var cache: [SyncLog]?
    // Serial queue — writes are dispatched off the main thread.
    private let saveQueue = DispatchQueue(label: "com.hmake98.HealthSync.logStore", qos: .utility)

    func load() -> [SyncLog] {
        if let cache { return cache }
        guard let data = UserDefaults.standard.data(forKey: key),
              let logs = try? JSONDecoder().decode([SyncLog].self, from: data) else {
            cache = []
            return []
        }
        cache = logs
        return logs
    }

    func append(_ log: SyncLog) {
        var logs = load()
        if let idx = logs.firstIndex(where: { $0.id == log.id }) {
            logs[idx] = log
        } else {
            logs.append(log)
        }
        persist(logs)
    }

    func update(_ log: SyncLog) {
        var logs = load()
        guard let idx = logs.firstIndex(where: { $0.id == log.id }) else { return }
        logs[idx] = log
        persist(logs)
    }

    func clear() {
        cache = []
        saveQueue.async {
            UserDefaults.standard.removeObject(forKey: self.key)
        }
    }

    private func persist(_ logs: [SyncLog]) {
        let trimmed = Array(logs.suffix(maxLogs))
        cache = trimmed
        // Encode on main thread (fast), write to defaults on background queue.
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        saveQueue.async {
            UserDefaults.standard.set(data, forKey: self.key)
        }
    }
}
