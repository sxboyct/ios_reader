import CoreGraphics
import Foundation
import Testing
@testable import TVCore

/// #1007: chapters shown in the script the reader picks, phrases converted as phrases.
@Test func novelScriptConvertsBetweenSimplifiedAndTraditional() {
    #expect(NovelScript.traditional.convert("头发很长，后来我们干杯了") == "頭髮很長，後來我們乾杯了")
    #expect(NovelScript.simplified.convert("頭髮很長，後來我們乾杯了") == "头发很长，后来我们干杯了")
    #expect(NovelScript.original.convert("头发") == "头发")

    let content = NovelContent(title: "第一章 归来", paragraphs: ["他说：“这里发生了什么？”", "", "联系我们"])
    let converted = NovelScript.traditional.convert(content)
    #expect(converted.title == "第一章 歸來")
    #expect(converted.paragraphs == ["他說：“這裡發生了什麼？”", "", "聯繫我們"])
    #expect(NovelScript.original.convert(content) == content)

    // Titles in one pass, the same as one by one; a title holding the separator still comes back in its place.
    let titles = ["第一章 归来", "第二章 后会有期", "", "第三章 \u{1E}发"]
    #expect(NovelScript.traditional.convert(titles) == titles.map(NovelScript.traditional.convert))
}

/// #1265: a picked photo is kept as one upright JPEG no larger than the reader draws.
