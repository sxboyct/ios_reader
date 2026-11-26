import SwiftUI
import WebKit
import TVCore

struct SourceBrowserPage: Identifiable {
    let id = UUID()
    let url: URL
}

/// Login pages share only this source's cookies with the rule engine.
struct SourceBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    let source: NovelSource
    let page: SourceBrowserPage
    @State private var session = SourceBrowserSession()
    @State private var saving = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let message = session.message { Text(message).font(.footnote).padding() }
                SourceBrowserSurface(session: session)
            }
            .navigationTitle(page.url.host ?? "书源网页").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { Task {
                        saving = true
                        do { try await session.save(source: source); dismiss() }
                        catch { session.message = error.localizedDescription }
                        saving = false
                    } }.disabled(saving || !session.ready)
                }
            }
            .task { await session.load(source: source, url: page.url) }
            .interactiveDismissDisabled()
        }
    }
}

@MainActor @Observable final class SourceBrowserSession: NSObject, WKNavigationDelegate {
    let view: WKWebView
    var message: String?
    var ready = false
    private var loadedURL: URL?
    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        view = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        view.navigationDelegate = self
        view.allowsBackForwardNavigationGestures = true
    }
    func load(source: NovelSource, url: URL) async {
        guard !ready, let host = url.host else { return }
        do {
            let cookies = try await NovelRuntime.shared.signInCookies(source, page: url.absoluteString)
            for item in cookies.split(separator: ";") {
                let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { continue }
                var properties: [HTTPCookiePropertyKey: Any] = [
                    .domain: host, .path: "/", .name: parts[0].trimmingCharacters(in: .whitespaces),
                    .value: String(parts[1])
                ]
                if url.scheme == "https" { properties[.secure] = "TRUE" }
                if let cookie = HTTPCookie(properties: properties) {
                    await view.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
                }
            }
            ready = true
            loadedURL = url
            view.load(URLRequest(url: url))
        } catch { message = error.localizedDescription }
    }
    func save(source: NovelSource) async throws {
        guard let url = loadedURL, let host = url.host else { return }
        let cookies = await view.configuration.websiteDataStore.httpCookieStore.allCookies()
        var values: [String: String] = [:]
        for cookie in cookies.sorted(by: { $0.domain.count < $1.domain.count }) {
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            guard host == domain || host.hasSuffix("." + domain),
                  cookie.expiresDate.map({ $0 > Date() }) ?? true else { continue }
            values[cookie.name] = cookie.value
        }
        let value = values.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        try await NovelRuntime.shared.keepSignInCookies(source, page: url.absoluteString, cookies: value)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        let url = navigationAction.request.url
        guard let scheme = url?.scheme?.lowercased(), ["http", "https", "about"].contains(scheme) else {
            return .cancel
        }
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            return .cancel
        }
        return .allow
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        message = error.localizedDescription
    }
}

private struct SourceBrowserSurface: UIViewRepresentable {
    let session: SourceBrowserSession
    func makeUIView(context: Context) -> WKWebView { session.view }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: Void) { view.stopLoading() }
}
