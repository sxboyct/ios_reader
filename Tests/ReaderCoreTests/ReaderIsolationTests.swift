import Foundation
import Testing
@testable import TVCore

@Test func textOnlySources() throws {
    let data = Data(#"[{"bookSourceUrl":"https://text.example","bookSourceType":0,"searchUrl":"/search"},{"bookSourceUrl":"https://audio.example","bookSourceType":1,"searchUrl":"/search"},{"bookSourceUrl":"https://image.example","bookSourceType":2,"searchUrl":"/search"}]"#.utf8)
    let sources = try #require(NovelSource.list(from: data))
    #expect(sources.map(\.key) == ["https://text.example"])
}

@Test func bundledRuleEngineBootsAndExtractsText() async throws {
    let session = try await ScriptSession.start(module: "assets://legado/engine.js", supplied: [:],
        profile: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), label: "reader-test", extension: NovelHost())
    defer { session.close() }
    let answer = await session.evaluate(#"JSON.stringify(__legado.rule('class.item@text', '<div class="item">第一段</div><div class="item">第二段</div>', 'https://example.com'))"#, within: 10)
    #expect(answer["error"] == nil)
    let text = try #require(answer["value"]?.string)
    let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    #expect(object["error"] == nil)
    #expect(object["value"] as? [String] == ["第一段", "第二段"])
}
