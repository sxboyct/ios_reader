import SwiftUI
import TVCore
import UniformTypeIdentifiers

@MainActor @Observable
final class ReaderFonts {
    static let shared = ReaderFonts()
    private let store = ReaderFontStore()
    var faces: [ReaderFontFace] = []
    var error: String?
    var problems: [ReaderFontProblem] = []
    var busy = false
    private init() {
        let restored = store.restore()
        faces = restored.faces; problems = restored.problems
        if !restored.failures.isEmpty { error = restored.failures.joined(separator: "\n") }
    }
    func reload() {
        let restored = store.restore()
        faces = restored.faces; problems = restored.problems
    }
    func add(_ url: URL) async throws -> String {
        busy = true
        defer { busy = false; reload() }
        let store = self.store
        let imported = try await Task.detached(priority: .userInitiated) { try store.add(url) }.value
        return imported.first?.postScriptName ?? ""
    }
    func removeProblem(_ problem: ReaderFontProblem) throws {
        try store.remove(problem.file)
        reload()
    }
    func remove(_ face: ReaderFontFace) throws {
        try store.remove(face.file)
        reload()
    }
    func font(_ selection: String, size: Double) -> Font {
        faces.contains(where: { $0.id == selection }) ? .custom(selection, fixedSize: size) : .system(size: size, design: .serif)
    }
}

struct FontSettingsView: View {
    var background: Color = Color(uiColor: .systemGroupedBackground)
    @State private var fonts = ReaderFonts.shared
    @AppStorage("reader.fontName") private var selection = ""
    @State private var importing = false
    var body: some View {
        List {
            Section {
                Button("导入 TTF / OTF 字体") { importing = true }.disabled(fonts.busy)
                if fonts.busy { ProgressView("正在导入字体…") }
                Text("导入后自动切换。字体保存在应用内，重启后仍然有效；缺失的字形由系统字体补足。重复导入同名字体会启用已有字体；替换同名的不同版本时，请先删除列表中的旧字体。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("阅读字体") {
                row("系统字体", id: "")
                ForEach(fonts.faces) { face in
                    row(face.displayName, id: face.id)
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                do {
                                    let removesSelected = fonts.faces.contains { $0.file == face.file && $0.id == selection }
                                    try fonts.remove(face)
                                    if removesSelected { selection = "" }
                                } catch { fonts.error = error.localizedDescription }
                            }
                        }
                }
            }
            if !fonts.problems.isEmpty {
                Section("需要修复的字体") {
                    ForEach(fonts.problems) { problem in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(problem.message).font(.footnote)
                            Button("删除此字体文件", role: .destructive) {
                                do { try fonts.removeProblem(problem); fonts.error = nil }
                                catch { fonts.error = error.localizedDescription }
                            }
                        }
                    }
                }
            }
            Section("预览") {
                Text("笔落纸端，勾勒回忆。\n山川与星河，都在书页之间。\nAa 0123456789")
                    .font(fonts.font(selection, size: 22)).lineSpacing(10).padding(.vertical)
            }
            if let error = fonts.error { Section("提示") { Text(error).foregroundStyle(.red) } }
        }
        .disabled(fonts.busy)
        .scrollContentBackground(.hidden)
        .background(background)
        .navigationTitle("阅读字体")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear { fonts.reload() }
        .sheet(isPresented: $importing) {
          DocumentImportPicker { url in
            importing = false
            guard let url else { return }
            Task {
                do {
                    selection = try await fonts.add(url); fonts.error = nil
                } catch { fonts.error = error.localizedDescription }
            }
          }.ignoresSafeArea()
        }
    }
    private func row(_ title: String, id: String) -> some View {
        Button { selection = id } label: {
            HStack { Text(title); Spacer(); if selection == id { Image(systemName: "checkmark") } }
        }
    }
}
