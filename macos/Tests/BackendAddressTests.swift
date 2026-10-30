import Foundation
import Testing
@testable import SkillAtlasCore

@Suite(.serialized) @MainActor
struct BackendAddressTests {
    @Test func normalizesAddressAndScope() throws {
        let address = try BackendAddress("  HTTPS://EXAMPLE.COM:443/ \n")
        #expect(address.text == "https://example.com")
        #expect(try BackendAddress("https://example.com") == address)
        #expect(try BackendAddress("https://[::1]:8447/").url.port == 8447)
        let original = try BackendAddress("https://localhost:8447")
        let a = BackendScope(address: address, defaultAddress: original)
        let b = BackendScope(address: try BackendAddress("https://EXAMPLE.com/"), defaultAddress: original)
        let c = BackendScope(address: try BackendAddress("https://example.com:8447"), defaultAddress: original)
        #expect(a == b && a != c && a.identifier.count == 64)
        let legacy = BackendScope(address: original, defaultAddress: original)
        let root = URL(fileURLWithPath: "/fixture/SkillAtlas")
        #expect(legacy.directory(in: root) == root)
        #expect(legacy.rememberKey == AccountController.rememberKey && legacy.vaultService == "local.skillatlas.session")
        #expect(a.directory(in: root) != root && a.directory(in: root) != c.directory(in: root))
        #expect(a.rememberKey != c.rememberKey && a.vaultService != legacy.vaultService)
    }

    @Test(arguments: ["", "localhost:8447", "http://localhost:8447", "ftp://example.com", "https://", "https://name:secret@example.com",
                      "https://example.com/v1", "https://example.com/?a=1", "https://example.com/#fragment", "https://example.com:0",
                      "https://example.com:65536", "https://example.com:abc", "https://example.com:", "https://bad host", "https://example.com/a/../"])
    func rejectsInvalidAddresses(_ text: String) {
        #expect(throws: APIError.self) { try BackendAddress(text) }
    }

    @Test func persistsRestoresAndClearsDefaultOverride() throws {
        let name = "local.skillatlas.backend-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let bundled = try BackendAddress("https://localhost:8447")
        let custom = try BackendAddress("https://127.0.0.1:8447/")
        let a = BackendPreferences(defaultAddress: bundled, preferences: defaults)
        #expect(a.current == bundled)
        a.save(custom)
        let b = BackendPreferences(defaultAddress: bundled, preferences: UserDefaults(suiteName: name)!)
        #expect(b.current == custom)
        b.save(bundled)
        #expect(defaults.object(forKey: BackendPreferences.addressKey) == nil && a.current == bundled)
        defaults.set("invalid", forKey: BackendPreferences.addressKey)
        #expect(a.current == bundled)
    }

    private func client(_ address: BackendAddress) -> APIClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [BackendTestProtocol.self]
        return APIClient(baseURL: address.url, session: URLSession(configuration: config))
    }

    @Test func healthProbeUsesCandidateWithoutAuthorization() async {
        BackendTestProtocol.state.reset()
        let check = BackendConnectionCheck(address: "https://candidate.invalid:8447", makeClient: client)
        await check.check()
        #expect(check.health?.database == "ready" && check.error == nil && !check.isChecking)
        let request = BackendTestProtocol.state.requests.first
        #expect(request?.url?.absoluteString == "https://candidate.invalid:8447/health")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == nil && request?.httpMethod == "GET")
    }

    @Test func failedProbeCanRetryAndRejectsOtherServices() async {
        BackendTestProtocol.state.reset(json: #"{"data":{"service":"Other","status":"ok","version":"1","database":"ready"}}"#)
        let check = BackendConnectionCheck(address: "https://candidate.invalid", makeClient: client)
        await check.check()
        #expect(check.health == nil && check.error?.contains("Skill Atlas") == true)
        BackendTestProtocol.state.reset()
        await check.check()
        #expect(check.health != nil && check.error == nil)
        check.address = "http://candidate.invalid"
        await check.check()
        #expect(check.health == nil && check.error != nil && BackendTestProtocol.state.requests.count == 1)
    }

    @Test func editedAddressRejectsLateProbeResult() async {
        BackendTestProtocol.state.reset(delayed: true)
        let check = BackendConnectionCheck(address: "https://old.invalid", makeClient: client)
        let task = Task { await check.check() }
        while !check.isChecking { await Task.yield() }
        check.address = "https://new.invalid"
        await task.value
        #expect(check.health == nil && check.error == nil && !check.isChecking)
        #expect(check.address == "https://new.invalid")
    }

    @Test func requestRejectsDifferentOriginBeforeSending() async throws {
        BackendTestProtocol.state.reset()
        let client = client(try BackendAddress("https://candidate.invalid"))
        defer { client.invalidate() }
        for path in ["https://other.invalid/private", "https://candidate.invalid:8447/private", "//other.invalid/private", "http://candidate.invalid/private"] {
            do { let _: Health = try await client.request(path, token: "fixture-token"); Issue.record("应拒绝跨来源请求") }
            catch let error as APIError { #expect(error.code == "invalid_url") }
        }
        #expect(BackendTestProtocol.state.requests.isEmpty)
    }

    @Test func redirectDelegateAllowsOnlySameHTTPSOrigin() async throws {
        let origin = try BackendAddress("https://candidate.invalid")
        let delegate = LocalCertificateDelegate(certificate: Data(), baseURL: origin.url, allowSystemTrust: true)
        let task = URLSession.shared.dataTask(with: origin.url)
        let response = HTTPURLResponse(url: origin.url, statusCode: 302, httpVersion: nil, headerFields: nil)!
        func redirect(_ url: String) async -> URLRequest? {
            await withCheckedContinuation { continuation in
                delegate.urlSession(.shared, task: task, willPerformHTTPRedirection: response,
                                    newRequest: URLRequest(url: URL(string: url)!)) { continuation.resume(returning: $0) }
            }
        }
        #expect(await redirect("https://candidate.invalid:443/next") != nil)
        for url in ["https://other.invalid/next", "http://candidate.invalid/next", "https://candidate.invalid:8447/next", "https://user:password@candidate.invalid/next"] {
            #expect(await redirect(url) == nil)
        }
    }
}

private final class BackendTestProtocol: URLProtocol, @unchecked Sendable {
    static let state = BackendTestState()
    private let lock = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (json, delayed) = Self.state.response(request)
        if delayed { DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { [self] in respond(json) } }
        else { respond(json) }
    }
    private func respond(_ json: String) {
        guard !lock.withLock({ stopped }) else { return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { lock.withLock { stopped = true } }
}

private final class BackendTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [URLRequest] = []
    private var json = ""
    private var delayed = false
    var requests: [URLRequest] { lock.withLock { seen } }
    func reset(json: String = #"{"data":{"service":"Skill Atlas","status":"ok","version":"fixture","database":"ready"}}"#, delayed: Bool = false) {
        lock.withLock { seen = []; self.json = json; self.delayed = delayed }
    }
    func response(_ request: URLRequest) -> (String, Bool) { lock.withLock { seen.append(request); return (json, delayed) } }
}
