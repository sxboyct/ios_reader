import SwiftUI
import TVCore

struct SourceSignInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let source: NovelSource
    @State private var form: NovelSignInForm?
    @State private var values: [String: String] = [:]
    @State private var busy = false
    @State private var message: String?
    @State private var pendingAction: NovelSignInForm.Field?
    @State private var browser: SourceBrowserPage?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if busy { ProgressView() }
                    if let message { Text(message).font(.footnote).textSelection(.enabled) }
                    if let form {
                        ForEach(Array(layoutRows(form.rows).enumerated()), id: \.offset) { _, fields in
                            HStack(spacing: 14) {
                                ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                                    fieldView(field).frame(maxWidth: .infinity, minHeight: 42).padding(12)
                                    .bookCard()
                                }
                            }
                        }
                        if let web = form.web, let url = webURL(web) { Button("打开登录页") { browser = SourceBrowserPage(url: url) } }
                    }
                    if form == nil && !busy { Button("重新加载") { Task { await load() } } }
                }.padding().disabled(busy)
            }
            .appPage()
            .navigationTitle("登录与设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("登录") { Task { await run(nil) } }.disabled(busy || form == nil || form?.rows.isEmpty == true) }
            }
            .task { await load() }
            .confirmationDialog(pendingAction?.name ?? "书源操作", isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })) {
                Button("确认清理", role: .destructive) { if let action = pendingAction?.action { Task { await run(action) } }; pendingAction = nil }
            }
            .sheet(item: $browser, onDismiss: { Task { await load() } }) { page in
                SourceBrowserView(source: source, page: page)
            }
        }
    }
    private func layoutRows(_ fields: [NovelSignInForm.Field]) -> [[NovelSignInForm.Field]] {
        var rows: [[NovelSignInForm.Field]] = []
        for field in fields {
            let compact = field.type == "button" && !field.wide && !dynamicTypeSize.isAccessibilitySize
            if compact, let previous = rows.last, previous.count == 1,
               previous[0].type == "button", !previous[0].wide {
                rows[rows.count - 1].append(field)
            } else { rows.append([field]) }
        }
        return rows
    }
    @ViewBuilder private func fieldView(_ field: NovelSignInForm.Field) -> some View {
        let binding = Binding(get: { values[field.name] ?? "" }, set: { values[field.name] = $0 })
        switch field.type {
        case "button":
            if let action = field.action {
                Button(field.name) {
                    if field.name.contains("清空") || field.name.contains("清理设备") { pendingAction = field }
                    else { Task { await run(action) } }
                }.frame(maxWidth: .infinity, minHeight: 42)
            } else { Text(field.name).font(.footnote).foregroundStyle(.secondary) }
        case "password": SecureField(field.name, text: binding)
        case "select", "toggle":
            Picker(field.name.replacingOccurrences(of: "（文字阅读）", with: ""), selection: binding) {
                ForEach(field.chars, id: \.self) { Text($0).tag($0) }
            }
                .onChange(of: values[field.name]) { _, _ in
                    if field.type == "toggle", !busy, let action = field.action { Task { await run(action) } }
                }
        case "label": Text(field.name)
        default: TextField(field.name, text: binding).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }
    private func webURL(_ value: String) -> URL? {
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
    private func load() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { let loaded = try await NovelRuntime.shared.signInForm(source); form = loaded; values = loaded.values }
        catch { message = error.localizedDescription }
    }
    private func run(_ action: String?) async {
        guard !busy else { return }
        busy = true; message = nil; defer { busy = false }
        do {
            let outcome: NovelSignInOutcome
            if let action { outcome = try await NovelRuntime.shared.signInAction(source, values: values, action: action) }
            else { outcome = try await NovelRuntime.shared.signIn(source, values: values) }
            message = outcome.said.joined(separator: "\n")
            if let address = outcome.open, let url = webURL(address) { browser = SourceBrowserPage(url: url) }
            let refreshed = try await NovelRuntime.shared.signInForm(source)
            form = refreshed; values.merge(refreshed.values) { _, new in new }
            if let updated = outcome.values { values.merge(updated) { _, new in new } }
        } catch { message = error.localizedDescription }
    }
}
