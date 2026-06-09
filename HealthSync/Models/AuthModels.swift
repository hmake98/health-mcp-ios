import Foundation

struct AuthResponse: Decodable {
    let id: String
    let name: String
    let email: String
    let apiKey: String
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct RegisterRequest: Encodable {
    let name: String
    let email: String
    let password: String
}

struct APIErrorResponse: Decodable {
    let error: String?
    let message: String?

    var displayMessage: String {
        error ?? message ?? "Something went wrong. Please try again."
    }
}
