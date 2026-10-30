import XCTest
@testable import SkillAtlasCore

final class APIClientTests: XCTestCase {
    func testDatesAcceptServerPrecision() throws {
        struct Value: Decodable { let date: Date }
        for value in ["2026-10-29T04:00:01Z", "2026-10-29T04:00:01.123456Z"] {
            XCTAssertNoThrow(try APIClient.decoder().decode(Value.self, from: Data("{\"date\":\"\(value)\"}".utf8)))
        }
        XCTAssertThrowsError(try APIClient.decoder().decode(Value.self, from: Data("{\"date\":\"invalid\"}".utf8)))
    }

    func testRejectsInsecureTransport() async {
        let client = APIClient(baseURL: URL(string: "http://localhost:8447")!, session: .shared)
        do {
            let _: Health = try await client.request("/health")
            XCTFail("不应允许明文连接")
        } catch let error as APIError { XCTAssertEqual(error.code, "invalid_url") }
        catch { XCTFail("应在发送前拒绝 HTTP") }
    }
}
