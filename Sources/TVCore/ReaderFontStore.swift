import Foundation
import CoreText

public struct ReaderFontFace: Identifiable, Hashable, Sendable {
    public var id: String { postScriptName }
    public let postScriptName: String
    public let displayName: String
    public let file: URL
}

/// Imported fonts live in Application Support; CoreText process registration is restored on launch.
public struct ReaderFontStore: Sendable {
    public let directory: URL
    public init(directory: URL = NovelLibrary.root.appendingPathComponent("Fonts", isDirectory: true)) { self.directory = directory }
    public func faces(at file: URL) throws -> [ReaderFontFace] {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor], !descriptors.isEmpty else {
            throw TVError.unsupported("无法识别字体，请选择有效的 TTF 或 OTF 文件。")
        }
        return try descriptors.map { descriptor in
            guard let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String, !name.isEmpty else {
                throw TVError.unsupported("字体缺少内部名称。")
            }
            let display = CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute) as? String ?? name
            return ReaderFontFace(postScriptName: name, displayName: display, file: file)
        }
    }
    private func register(_ url: URL) throws {
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            if let error = error?.takeRetainedValue() {
                guard CFErrorGetCode(error) == CTFontManagerError.alreadyRegistered.rawValue else {
                    throw TVError.unsupported("注册字体失败：" + (CFErrorCopyDescription(error) as String))
                }
            } else { throw TVError.unsupported("注册字体失败。") }
        }
    }
    public func restore() -> (faces: [ReaderFontFace], failures: [String]) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var result: [ReaderFontFace] = [], failures: [String] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where ["ttf", "otf"].contains(file.pathExtension.lowercased()) {
            do { let found = try faces(at: file); try register(file); result.append(contentsOf: found) }
            catch { failures.append(file.lastPathComponent + "：" + error.localizedDescription) }
        }
        return (result, failures)
    }
    public func add(_ url: URL) throws -> [ReaderFontFace] {
        let data = try ImportedFile.read(url, extensions: ["ttf", "otf"], limit: 32 * 1024 * 1024)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(PluginChecksum.sha256(data) + "." + url.pathExtension.lowercased())
        if FileManager.default.fileExists(atPath: destination.path) { try register(destination); return try faces(at: destination) }
        try data.write(to: destination, options: .atomic)
        do {
            let imported = try faces(at: destination)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let existing = files.filter { $0 != destination }.flatMap { (try? faces(at: $0)) ?? [] }
            guard !imported.contains(where: { face in existing.contains { $0.postScriptName == face.postScriptName } }) else {
                throw TVError.unsupported("已存在相同内部名称的字体，请先删除旧字体。")
            }
            try register(destination)
            return imported
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
    public func remove(_ file: URL) throws {
        guard file.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else {
            throw TVError.unsupported("字体文件路径无效。")
        }
        CTFontManagerUnregisterFontsForURL(file as CFURL, .process, nil)
        do { try FileManager.default.removeItem(at: file) }
        catch { try? register(file); throw error }
    }
}
