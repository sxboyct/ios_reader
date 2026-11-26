import Foundation
import Observation
import TVCore

struct DiscoverPreview: Identifiable {
    let kind: NovelExploreKind
    var books: [NovelBook] = []
    var loading = true
    var error: String?
    var id: String { kind.id }
}

@MainActor @Observable final class DiscoverPageModel {
    var kinds: [NovelExploreKind] = []
    var sections: [DiscoverPreview] = []
    var form: NovelSignInForm?
    var loading = false
    var loadingPreviews = false
    var saving = false
    var error: String?
    private var generation = UUID()
    var canLoadMore: Bool { sections.count < kinds.count }
    var filterFields: [NovelSignInForm.Field] {
        guard form?.rows.contains(where: { $0.action == "__yingxia_apply_text_settings__" }) == true else { return [] }
        return form?.rows.filter { ["线路（文字阅读）", "发现来源（文字阅读）", "频道（文字阅读）"].contains($0.name) } ?? []
    }
    func filterLabel(_ field: NovelSignInForm.Field) -> String {
        let value = form?.values[field.name] ?? ""
        let name = field.name.replacingOccurrences(of: "（文字阅读）", with: "").replacingOccurrences(of: "发现来源", with: "来源")
        return name + " " + (field.name.hasPrefix("线路") ? URL(string: value)?.host ?? value : value)
    }
    func reload(_ source: NovelSource) async {
        let request = UUID(); generation = request
        loading = true; loadingPreviews = false; error = nil; sections = []; kinds = []
        defer { if generation == request { loading = false } }
        do {
            if source.signsIn {
                let loaded = try? await NovelRuntime.shared.signInForm(source)
                guard generation == request, !Task.isCancelled else { return }
                form = loaded
            }
            let found = try await NovelRuntime.shared.exploreKinds(source)
            guard generation == request, !Task.isCancelled else { return }
            var seen = Set<String>()
            kinds = found.filter { !$0.url.isEmpty && seen.insert($0.url).inserted }
            loading = false
            await more(source)
        } catch {
            if generation == request { loading = false; self.error = error.localizedDescription }
        }
    }
    func select(_ field: NovelSignInForm.Field, value: String, source: NovelSource) async {
        guard !saving, var values = form?.values, field.chars.contains(value) else { return }
        saving = true; defer { saving = false }
        // Supersede in-flight preview requests before applying the new selection.
        generation = UUID(); loadingPreviews = false
        for at in sections.indices where sections[at].loading {
            sections[at].loading = false; sections[at].error = "筛选条件已更改，请刷新书单。"
        }
        values[field.name] = value
        do {
            _ = try await NovelRuntime.shared.signInAction(source, values: values, action: "__yingxia_apply_text_settings__")
            await reload(source)
        } catch { self.error = error.localizedDescription }
    }
    func more(_ source: NovelSource) async {
        guard !loadingPreviews, canLoadMore else { return }
        let next = Array(kinds.dropFirst(sections.count).prefix(4))
        sections.append(contentsOf: next.map { DiscoverPreview(kind: $0) })
        await previews(next, source: source)
    }
    func retry(_ section: DiscoverPreview, source: NovelSource) async {
        guard !loadingPreviews else { return }
        if let at = sections.firstIndex(where: { $0.id == section.id }) { sections[at].loading = true; sections[at].error = nil }
        await previews([section.kind], source: source)
    }
    private func previews(_ entries: [NovelExploreKind], source: NovelSource) async {
        let request = generation
        loadingPreviews = true
        defer { if generation == request { loadingPreviews = false } }
        // At most two lists at once; never request hundreds of categories on opening.
        for offset in stride(from: 0, to: entries.count, by: 2) {
            guard request == generation, !Task.isCancelled else { return }
            await withTaskGroup(of: (String, [NovelBook], String?).self) { group in
                for kind in entries.dropFirst(offset).prefix(2) {
                    group.addTask {
                        do {
                            let books = try await NovelRuntime.shared.explore(source, url: kind.url, page: 1)
                            return (kind.id, books, nil)
                        } catch { return (kind.id, [], error.localizedDescription) }
                    }
                }
                while let (id, books, failure) = await group.next() {
                    guard request == generation, !Task.isCancelled else { group.cancelAll(); return }
                    if let at = sections.firstIndex(where: { $0.id == id }) {
                        var seen = Set<String>()
                        sections[at].books = Array(books.filter { seen.insert($0.id).inserted }.prefix(4))
                        sections[at].error = failure; sections[at].loading = false
                    }
                }
            }
        }
    }
}
