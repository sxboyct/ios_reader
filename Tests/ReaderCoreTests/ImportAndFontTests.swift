import Foundation
import CoreText
import Testing
@testable import TVCore

private final class FontTestBundle: NSObject {}

@Suite(.serialized)
struct ImportAndFontTests {
    @Test func xbsKnownVectorAndInvalidPayload() throws {
        // Independently encoded with the xbs-booksource-workflow Python codec; not a packaged book source.
        let encrypted = try #require(Data(base64Encoded: "xn7fM1sWHeDMY61W/Chy36ccKaz0N2Md"))
        #expect(try XBSData.json(encrypted) == Data(#"{"text":"中文"}"#.utf8))
        #expect(try XBSData.json(Data("{}".utf8)) == Data("{}".utf8))
        #expect(throws: (any Error).self) { try XBSData.json(Data(repeating: 0, count: 16)) }
        #expect(throws: (any Error).self) { try XBSData.json(Data([1, 2, 3])) }
    }
    @Test func importFontRestoreDeduplicateAndRemove() throws {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: FontTestBundle.self)
        #endif
        let fixture = try #require(bundle.url(forResource: "ReaderTestFont", withExtension: "ttf", subdirectory: "Fixtures"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ReaderFontStore(directory: directory)
        defer {
            for file in Set(store.restore().faces.map(\.file)) { try? store.remove(file) }
            try? FileManager.default.removeItem(at: directory)
        }
        let faces = try store.add(fixture)
        let first = try #require(faces.first)
        #expect(first.postScriptName == "ReaderTestFont-Regular")
        #expect(CTFontCopyPostScriptName(CTFontCreateWithName(first.postScriptName as CFString, 20, nil)) as String == first.postScriptName)
        #expect(try store.add(fixture) == faces)
        let restored = ReaderFontStore(directory: directory).restore()
        #expect(restored.failures.isEmpty)
        #expect(restored.faces == faces)
        #expect(restored.problems.isEmpty)
        // Foundation enumeration can return an absolute URL while callers use a base-relative URL.
        let equivalent = URL(fileURLWithPath: directory.lastPathComponent + "/./", isDirectory: true,
            relativeTo: directory.deletingLastPathComponent())
        #expect(try ReaderFontStore(directory: equivalent).add(fixture) == faces)
        // Different file bytes/extension, same PostScript name: reuse the visible installed face.
        let renamed = directory.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".otf")
        defer { try? FileManager.default.removeItem(at: renamed) }
        var duplicate = try Data(contentsOf: fixture)
        duplicate.append(contentsOf: [0, 0, 0, 0])
        try duplicate.write(to: renamed)
        #expect(try store.add(renamed) == faces)
        #expect(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).count == 1)
        try store.remove(first.file)
        #expect(store.restore().faces.isEmpty)
    }

    @Test func leftoverInvalidFontRemainsVisibleAndRemovable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let broken = directory.appendingPathComponent("old-font.ttf")
        try Data("interrupted import".utf8).write(to: broken)
        let store = ReaderFontStore(directory: directory)
        let restored = store.restore()
        #expect(restored.faces.isEmpty)
        #expect(restored.failures.count == 1)
        let problem = try #require(restored.problems.first)
        #expect(problem.file.lastPathComponent == "old-font.ttf")
        try store.remove(problem.file)
        #expect(store.restore().problems.isEmpty)
    }

    @Test func invalidFilesAreRejectedAfterBroadSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let json = directory.appendingPathComponent("source.JSON")
        try Data("{}".utf8).write(to: json)
        #expect(try ImportedFile.read(json, extensions: ["json"], limit: 32) == Data("{}".utf8))
        #expect(throws: (any Error).self) { try ImportedFile.read(json, extensions: ["ttf", "otf"], limit: 32) }
        #expect(throws: (any Error).self) { try ImportedFile.read(json, extensions: ["json"], limit: 1) }
        let fake = directory.appendingPathComponent("bad.ttf")
        try Data("not a font".utf8).write(to: fake)
        let store = ReaderFontStore(directory: directory.appendingPathComponent("Imported"))
        #expect(throws: (any Error).self) { try store.add(fake) }
        #expect(store.restore().faces.isEmpty)
    }

    @Test func xiangseImportPreservesRulesAndEnabledState() throws {
        let json = #"{"test":{"sourceName":"香色示例","sourceUrl":"https://example.com/","sourceType":"text","enable":0,"searchBook":{},"bookDetail":{},"chapterList":{},"chapterContent":{}}}"#
        let source = try #require(NovelSource.list(from: Data(json.utf8))?.first)
        #expect(source.name == "香色示例")
        #expect(source.disabledByList)
        #expect(source.key == "xiangse:https://example.com/#test")
        let object = try #require(JSONSerialization.jsonObject(with: Data(source.json.utf8)) as? [String: Any])
        #expect((object["_xiangse"] as? [String: Any])?["sourceName"] as? String == "香色示例")
        #expect(try JSONDecoder().decode(NovelSource.self, from: JSONEncoder().encode(source)) == source)
    }

    @Test func nativeDispatcherBootsBothEngines() async throws {
        let session = try await ScriptSession.start(module: "assets://reader/engine.js", supplied: [:],
            profile: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), label: "xiangse-native", extension: NovelHost())
        defer { session.close() }
        let reply = await session.evaluate("typeof __reader.load + ':' + typeof __reader.content", within: 10)
        #expect(reply["error"] == nil)
        #expect(reply["value"]?.string == "function:function")
    }
}
