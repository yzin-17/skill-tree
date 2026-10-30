import Foundation

@main
struct Connectivity {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let configuration = try JSONDecoder().decode(ClientConfiguration.self, from: Data(contentsOf: root.appendingPathComponent("client-config.json")))
        let cert = try Data(contentsOf: root.appendingPathComponent("tls/cert.der"))
        let client = APIClient(baseURL: configuration.baseURL, certificate: cert)
        do {
            let health: Health = try await client.request("/health")
            print("原生 HTTPS：\(health.status)，数据库：\(health.database)")
        } catch {
            let error = error as NSError
            print("连接错误：\(error.domain) \(error.code) \(error.localizedDescription)")
            exit(1)
        }
    }
}
