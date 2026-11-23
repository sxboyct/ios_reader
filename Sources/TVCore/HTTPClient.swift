import Foundation

public struct HTTPClient: Sendable {
    public static let subscriptionUserAgent = NovelRuntime.userAgent
    public static let subscriptionLimit = 32 * 1024 * 1024
    public init() {}
    public func get(_ url: URL, headers: [String: String] = [:], limit: Int = subscriptionLimit) async throws -> (Data, URL) {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { throw TVError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 30)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw TVError.invalidConfiguration }
        guard (200..<300).contains(http.statusCode) else { throw TVError.http(http.statusCode) }
        guard response.expectedContentLength <= Int64(limit) else { throw TVError.unsupported("书源文件超过大小限制。") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw TVError.unsupported("书源文件超过大小限制。") }
            data.append(byte)
        }
        return (data, response.url ?? url)
    }
}
