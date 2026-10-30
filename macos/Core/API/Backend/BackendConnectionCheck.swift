import Foundation
import Observation

@MainActor @Observable
public final class BackendConnectionCheck {
    public var address: String {
        didSet { if address != oldValue { cancel(); health = nil; error = nil } }
    }
    public private(set) var isChecking = false
    public private(set) var health: Health?
    public private(set) var error: String?
    @ObservationIgnored private let makeClient: @MainActor (BackendAddress) throws -> APIClient
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var activeClient: APIClient?
    public var validationError: String? {
        do { _ = try BackendAddress(address); return nil }
        catch { return error.localizedDescription }
    }
    public init(address: String, makeClient: @escaping @MainActor (BackendAddress) throws -> APIClient) {
        self.address = address; self.makeClient = makeClient
    }
    public func cancel() {
        generation = UUID(); activeClient?.invalidate(); activeClient = nil; isChecking = false
    }
    public func check() async {
        cancel(); health = nil; error = nil
        let current = generation
        do {
            let address = try BackendAddress(address)
            let client = try makeClient(address); activeClient = client; isChecking = true
            defer { client.invalidate(); if generation == current { activeClient = nil; isChecking = false } }
            let value = try await client.checkHealth()
            guard generation == current else { return }
            health = value
        } catch {
            guard generation == current else { return }
            self.error = Self.message(error)
        }
    }
    public static func message(_ error: Error) -> String {
        if let api = error as? APIError { return api.message }
        if let network = error as? URLError {
            switch network.code {
            case .timedOut: return "连接超时，请检查后端地址与网络。"
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid, .secureConnectionFailed:
                return "证书校验失败，请使用受信任的 HTTPS 服务。"
            default: break
            }
        }
        return "无法连接后端，请检查地址与服务状态。"
    }
}
