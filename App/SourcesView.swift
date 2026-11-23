import SwiftUI
import UniformTypeIdentifiers
import TVCore

struct SourcesView: View {
    @Environment(ReaderLibrary.self) private var library
    @State private var address = ""
    @State private var importing = false
    @State private var busy = false
    @State private var message: String?
    @State private var filter = ""
    var body: some View {
        List {
            Section("导入 Legado / 香色文字书源") {
                TextField("https://example.com/books.json", text: $address)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("从网址导入") { Task { await importURL() } }.disabled(busy || address.isEmpty)
                Button("从 JSON / XBS 文件导入") { importing = true }.disabled(busy)
                if busy { ProgressView("正在导入…") }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("已导入的书源列表") {
                ForEach(library.lists) { list in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NovelSources.title(of: list)).font(.headline)
                        Text("\(list.count) 个文字书源").font(.caption).foregroundStyle(.secondary)
                        if !list.address.isFileURL {
                            Button("刷新") { Task {
                                busy = true
                                do { _ = try await NovelSources.shared.refresh(list.address); message = "刷新完成" }
                                catch { message = error.localizedDescription }
                                busy = false; library.reloadSources()
                            } }.disabled(busy)
                        }
                    }.swipeActions {
                        Button("删除列表", role: .destructive) { NovelSources.shared.remove(list.address); library.reloadSources() }
                    }
                }
            }
            Section("启用的书源参与搜索") {
                ForEach(library.sources.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }) { source in
                    Toggle(isOn: Binding(get: { NovelSources.shared.isEnabled(source) }, set: {
                        NovelSources.shared.setEnabled($0, for: [source.key]); library.reloadSources()
                    })) {
                        VStack(alignment: .leading) {
                            Text(source.name)
                            if !source.group.isEmpty { Text(source.group).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            Section {
                Text("仅支持文字书源。不提供内置内容，也不支持 EPUB/PDF 文件或有声书。网站失效时可在搜索结果中选择其他书源。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("书源")
        .searchable(text: $filter, prompt: "筛选书源")
        // Some Files providers expose .json as public.data rather than public.json.
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let data = try ImportedFile.read(url, extensions: ["json", "xbs"], limit: HTTPClient.subscriptionLimit)
                // Stable identity; NovelSources copies the actual JSON into its own storage.
                let identity = URL(fileURLWithPath: "/ImportedSources/" + url.lastPathComponent)
                let list = try NovelSources.shared.add(identity, data: data, name: url.deletingPathExtension().lastPathComponent)
                message = "已导入 \(list.count) 个文字书源"; library.reloadSources()
            } catch { message = error.localizedDescription }
        }
    }
    private func importURL() async {
        busy = true; message = nil
        defer { busy = false; library.reloadSources() }
        do {
            let url = try WebAddress.resolve(address.trimmingCharacters(in: .whitespacesAndNewlines))
            let list = try await NovelSources.shared.refresh(url)
            message = "已导入 \(list.count) 个文字书源"; address = ""
        } catch { message = error.localizedDescription }
    }
}
