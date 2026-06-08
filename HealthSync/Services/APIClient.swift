import Foundation

enum APIError: LocalizedError {
    case unauthenticated
    case httpError(Int, String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "No API key found. Please sign in."
        case .httpError(let code, let message):
            return "Server error \(code): \(message)"
        case .networkError(let err):
            return err.localizedDescription
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
    }

    // MARK: - Auth Endpoints (no API key required)

    func login(email: String, password: String) async throws -> AuthResponse {
        let body = try encoder.encode(LoginRequest(email: email, password: password))
        var request = URLRequest(url: try url("/auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await perform(request, requiresAuth: false)
        return try decoder.decode(AuthResponse.self, from: data)
    }

    func checkHealth() async -> Bool {
        guard let url = URL(string: "\(Config.serverURL)/health") else { return false }
        guard let (_, response) = try? await session.data(for: URLRequest(url: url)),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    // MARK: - Health Sync Endpoints (API key required)

    func syncVitals(records: [VitalRecord]) async throws -> Int {
        guard !records.isEmpty else { return 0 }
        var total = 0
        for batch in records.chunked(into: 500) {
            let body = try encoder.encode(VitalsRequest(records: batch))
            let request = try authedRequest(path: "/api/health/vitals", body: body)
            _ = try await perform(request)
            total += batch.count
        }
        return total
    }

    func syncSleep(records: [SleepRecord]) async throws -> Int {
        guard !records.isEmpty else { return 0 }
        var total = 0
        for batch in records.chunked(into: 500) {
            let body = try encoder.encode(SleepRequest(records: batch))
            let request = try authedRequest(path: "/api/health/sleep", body: body)
            _ = try await perform(request)
            total += batch.count
        }
        return total
    }

    func syncWorkouts(records: [WorkoutRecord]) async throws -> Int {
        guard !records.isEmpty else { return 0 }
        var total = 0
        for batch in records.chunked(into: 500) {
            let body = try encoder.encode(WorkoutsRequest(records: batch))
            let request = try authedRequest(path: "/api/health/workouts", body: body)
            _ = try await perform(request)
            total += batch.count
        }
        return total
    }

    func syncActivity(records: [ActivityRecord]) async throws -> Int {
        guard !records.isEmpty else { return 0 }
        var total = 0
        for batch in records.chunked(into: 500) {
            let body = try encoder.encode(ActivityRequest(records: batch))
            let request = try authedRequest(path: "/api/health/activity", body: body)
            _ = try await perform(request)
            total += batch.count
        }
        return total
    }

    // MARK: - Private Helpers

    private func url(_ path: String) throws -> URL {
        guard let url = URL(string: "\(Config.serverURL)\(path)") else {
            throw APIError.networkError(URLError(.badURL))
        }
        return url
    }

    private var storedAPIKey: String {
        UserDefaults.standard.string(forKey: "auth.apiKey") ?? ""
    }

    private func authedRequest(path: String, body: Data) throws -> URLRequest {
        let key = storedAPIKey
        guard !key.isEmpty else { throw APIError.unauthenticated }
        var request = URLRequest(url: try url(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.httpBody = body
        return request
    }

    @discardableResult
    private func perform(_ request: URLRequest, requiresAuth: Bool = true) async throws -> (Data, HTTPURLResponse) {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = (try? decoder.decode(APIErrorResponse.self, from: data))?.displayMessage
                ?? String(data: data, encoding: .utf8)
                ?? "Unknown error"
            throw APIError.httpError(http.statusCode, msg)
        }
        return (data, http)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
