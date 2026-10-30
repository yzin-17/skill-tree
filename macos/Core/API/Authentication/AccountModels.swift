import Foundation

public struct AccountUser: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let email: String
    public var timezone: String
    public let createdAt: Date
    public init(id: String, email: String, timezone: String, createdAt: Date) {
        self.id = id; self.email = email; self.timezone = timezone; self.createdAt = createdAt
    }
}

public struct AccountSession: Codable, Sendable, Equatable {
    public var user: AccountUser
    public let token: String
    public let expiresAt: Date
    public init(user: AccountUser, token: String, expiresAt: Date) { self.user = user; self.token = token; self.expiresAt = expiresAt }
}

public struct AccountCredentials: Codable, Sendable {
    public var email: String
    public var password: String
    public var timezone: String?
    public init(email: String, password: String, timezone: String? = nil) { self.email = email; self.password = password; self.timezone = timezone }
}

public struct LogoutResult: Codable, Sendable { public let loggedOut: Bool }
