import XCTest
@testable import SkillAtlasCore

final class AccountTests: XCTestCase {
    func testKeychainRoundTripAndDelete() throws {
        let vault = KeychainSessionVault(service: "local.skillatlas.tests.\(UUID().uuidString)")
        defer { try? vault.clear() }
        XCTAssertNil(try vault.read())
        let user = AccountUser(id: UUID().uuidString, email: "keychain@example.invalid", timezone: "Asia/Shanghai", createdAt: Date(timeIntervalSince1970: 1_790_000_000))
        let session = AccountSession(user: user, token: "test-credential-not-a-live-token", expiresAt: Date(timeIntervalSince1970: 1_800_000_000))
        try vault.save(session)
        XCTAssertEqual(try vault.read(), session)
        try vault.save(AccountSession(user: user, token: "test-rotated-credential", expiresAt: session.expiresAt))
        XCTAssertEqual(try vault.read()?.token, "test-rotated-credential")
        try vault.clear(); XCTAssertNil(try vault.read()); XCTAssertNoThrow(try vault.clear())
    }
    func testSharedAuthFixture() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        struct Contract: Decodable { let fixtures: [AccountCredentials] }
        let contract = try JSONDecoder().decode(Contract.self, from: Data(contentsOf: root.appendingPathComponent("server/contracts/auth.yaml")))
        XCTAssertEqual(contract.fixtures.count, 2)
        XCTAssertEqual(contract.fixtures[0].timezone, "Asia/Shanghai")
        let data = Data(#"{"data":{"user":{"id":"example","email":"owner@example.invalid","timezone":"Asia/Shanghai","created_at":"2026-10-29T00:00:00Z"},"token":"test","expires_at":"2026-11-29T00:00:00Z"}}"#.utf8)
        struct Response: Decodable { let data: AccountSession }
        XCTAssertEqual(try APIClient.decoder().decode(Response.self, from: data).data.user.email, contract.fixtures[0].email)
    }
}
