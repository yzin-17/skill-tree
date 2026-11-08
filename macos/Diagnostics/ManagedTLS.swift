import Foundation

// 独立诊断程序：验证应用内置根 CA 与旧版客户端的系统信任连接路径。
@main
struct ManagedTLSDiagnostic {
    static func main() async {
        do {
            guard CommandLine.arguments.count == 4 else {
                throw APIError(code: "arguments", message: "参数：根证书 DER、旧叶证书 DER、局域网 HTTPS 根地址")
            }
            let root = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let legacy = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
            for address in ["https://localhost:8447", "https://127.0.0.1:8447", CommandLine.arguments[3]] {
                let client = APIClient(baseURL: URL(string: address)!, certificate: root)
                defer { client.invalidate() }
                _ = try await client.checkHealth()
                print("应用内置根 CA 验证通过：\(address)")
            }
            let rejected = APIClient(baseURL: URL(string: "https://localhost:8447")!, certificate: legacy)
            defer { rejected.invalidate() }
            do {
                _ = try await rejected.checkHealth()
                throw APIError(code: "unexpected_trust", message: "旧叶证书不应信任新服务端证书")
            } catch let error as APIError where error.code == "unexpected_trust" {
                throw error
            } catch {
                guard let error = error as? URLError,
                      [.cancelled, .secureConnectionFailed, .serverCertificateUntrusted,
                       .serverCertificateHasUnknownRoot].contains(error.code) else { throw error }
                print("旧叶证书固定信任拒绝新证书：通过")
            }
            let custom = APIClient(baseURL: URL(string: "https://127.0.0.1:8447")!,
                                   certificate: legacy, allowSystemTrust: true)
            defer { custom.invalidate() }
            _ = try await custom.checkHealth()
            print("自定义地址的系统根信任验证通过；无需更新旧客户端安装包。")
        } catch {
            print("自动 TLS 诊断失败：\(error)")
            exit(1)
        }
    }
}
