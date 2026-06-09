import Foundation

@MainActor
@Observable
final class AuthService {
    static let shared = AuthService()

    private enum Key {
        static let apiKey = "auth.apiKey"
        static let userId = "auth.userId"
        static let userName = "auth.userName"
        static let userEmail = "auth.userEmail"
    }

    private let defaults = UserDefaults.standard

    var isAuthenticated = false
    var apiKey: String = ""
    var userId: String?
    var userName: String?
    var userEmail: String?

    init() {
        apiKey = defaults.string(forKey: Key.apiKey) ?? ""
        userId = defaults.string(forKey: Key.userId)
        userName = defaults.string(forKey: Key.userName)
        userEmail = defaults.string(forKey: Key.userEmail)
        isAuthenticated = !apiKey.isEmpty
    }

    func signIn(email: String, password: String) async throws {
        let response = try await APIClient.shared.login(email: email, password: password)
        persist(apiKey: response.apiKey, id: response.id, name: response.name, email: response.email)
    }

    func signUp(name: String, email: String, password: String) async throws {
        let response = try await APIClient.shared.register(name: name, email: email, password: password)
        persist(apiKey: response.apiKey, id: response.id, name: response.name, email: response.email)
    }

    func signOut() {
        apiKey = ""
        userId = nil
        userName = nil
        userEmail = nil
        isAuthenticated = false
        [Key.apiKey, Key.userId, Key.userName, Key.userEmail].forEach {
            defaults.removeObject(forKey: $0)
        }
        AppSettings.shared.clearSyncDates()
        SyncLogStore.shared.clear()
    }

    private func persist(apiKey: String, id: String?, name: String?, email: String?) {
        self.apiKey = apiKey
        self.userId = id
        self.userName = name
        self.userEmail = email
        self.isAuthenticated = true

        defaults.set(apiKey, forKey: Key.apiKey)
        defaults.set(id, forKey: Key.userId)
        defaults.set(name, forKey: Key.userName)
        defaults.set(email, forKey: Key.userEmail)
    }

    var displayName: String { userName ?? "User" }
    var displayEmail: String { userEmail ?? "" }
    var avatarInitials: String {
        let parts = displayName.split(separator: " ").compactMap { $0.first.map(String.init) }
        return parts.prefix(2).joined().uppercased()
    }
}
