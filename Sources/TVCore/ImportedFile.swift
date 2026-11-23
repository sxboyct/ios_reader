import Foundation

/// Content validation follows a deliberately broad Files picker; file-provider UTIs are unreliable.
public enum ImportedFile {
    public static func read(_ url: URL, extensions: Set<String>, limit: Int) throws -> Data {
        guard extensions.contains(url.pathExtension.lowercased()) else {
            throw TVError.unsupported("请选择 " + extensions.sorted().joined(separator: " / ") + " 文件。")
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var outcome: Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { local in
            outcome = Result {
                guard try local.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    throw TVError.unsupported("请选择文件，不能导入文件夹。")
                }
                let handle = try FileHandle(forReadingFrom: local)
                defer { try? handle.close() }
                var data = Data()
                while data.count <= limit {
                    let chunk = try handle.read(upToCount: min(64 * 1024, limit + 1 - data.count)) ?? Data()
                    if chunk.isEmpty { break }
                    data.append(chunk)
                }
                guard !data.isEmpty, data.count <= limit else { throw TVError.unsupported("文件为空或超过大小限制。") }
                return data
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw TVError.unsupported("文件暂不可读，请先在「文件」中下载到本机。") }
        return try outcome.get()
    }
}
