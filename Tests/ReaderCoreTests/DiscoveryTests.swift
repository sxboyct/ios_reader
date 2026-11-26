import Foundation
import Testing
@testable import TVCore

@Test func discoveryRuntimeReloadsSettingsAndHandsOffLogin() async throws {
    let key = "https://discovery-\(UUID().uuidString).example"
    let source = try #require(NovelSource(object: [
        "bookSourceUrl": key, "bookSourceType": 0,
        "jsLib": "const {sourceHeading} = {sourceHeading: '发现'};\nconst channel = source.getVariable() || '男频';",
        "exploreUrl": "@js:JSON.stringify([{title: sourceHeading + channel, url: 'https://example.invalid/list'}])",
        "searchUrl": "@js:'data:application/json,' + encodeURIComponent(JSON.stringify({data:[{name:channel,url:'https://example.invalid/book'}]}))",
        "ruleSearch": ["bookList": "$.data", "name": "$.name", "bookUrl": "$.url"],
        "loginUi": #"[{"name":"邮箱","type":"text"},{"name":"登录","type":"button","action":"login()","style":{"layout_flexBasisPercent":1}}]"#,
        "loginUrl": "function login() { java.startBrowser('https://example.invalid/login'); }"
    ]))
    let runtime = NovelRuntime()
    let first = try await runtime.exploreKinds(source)
    #expect(first.first?.title == "发现男频")
    let firstSearch = try await runtime.search(source, keyword: "fixture", page: 1)
    #expect(firstSearch.first?.name == "男频")
    let form = try await runtime.signInForm(source)
    #expect(form.rows.last?.wide == true)
    _ = try await runtime.signInAction(source, values: [:], action: "source.setVariable('女频')")
    let updatedSearch = try await runtime.search(source, keyword: "fixture", page: 1)
    #expect(updatedSearch.first?.name == "女频")
    let changed = try await runtime.exploreKinds(source)
    #expect(changed.first?.title == "发现女频")
    let login = try await runtime.signInAction(source, values: [:], action: "login()")
    #expect(login.open == "https://example.invalid/login")
    try await runtime.keepSignInCookies(source, page: key, cookies: "session=fixture; old=value")
    try await runtime.keepSignInCookies(source, page: key, cookies: "session=new")
    let cookies = try await runtime.signInCookies(source, page: key)
    #expect(cookies == "session=new")
    try await runtime.keepSignInCookies(source, page: key, cookies: "")
    let cleared = try await runtime.signInCookies(source, page: key)
    #expect(cleared.isEmpty)
    await runtime.reset(key)
}
