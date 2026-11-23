import SwiftUI
import TVCore
import UniformTypeIdentifiers

@MainActor @Observable
final class ReaderFonts {
    static let shared = ReaderFonts()
    private let store = ReaderFontStore()
    var faces: [ReaderFontFace] = []
    var error: String?
    private init() {
        let restored = store.restore()
        faces = restored.faces
        if !restored.failures.isEmpty { error = restored.failures.joined(separator: "\n") }
    }
    func add(_ url: URL) throws -> String {
        let imported = try store.add(url)
        faces = store.restore().faces
        return imported.first?.postScriptName ?? ""
    }
    func remove(_ face: ReaderFontFace) throws {
        try store.remove(face.file)
        faces.removeAll { $0.file == face.file }
    }
    func font(_ selection: String, size: Double) -> Font {
        faces.contains(where: { $0.id == selection }) ? .custom(selection, fixedSize: size) : .system(size: size, design: .serif)
    }
}

struct FontSettingsView: View {
    @State private var fonts = ReaderFonts.shared
    @AppStorage("reader.fontName") private var selection = ""
    @State private var importing = false
    var body: some View {
        List {
            Section {
                Button("导入 TTF / OTF 字体") { importing = true }
                Text("导入后自动切换。字体保存在应用内，重启后仍然有效；缺失的字形由系统字体补足。")
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
            Section("预览") {
                Text("笔落纸端，勾勒回忆。\n山川与星河，都在书页之间。\nAa 0123456789")
                    .font(fonts.font(selection, size: 22)).lineSpacing(10).padding(.vertical)
            }
            if let error = fonts.error { Section("提示") { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("阅读字体")
        .sheet(isPresented: $importing) {
          DocumentImportPicker { url in
            importing = false
            guard let url else { return }
            do {
                selection = try fonts.add(url); fonts.error = nil
            } catch { fonts.error = error.localizedDescription }
          }.ignoresSafeArea()
        }
    }
    private func row(_ title: String, id: String) -> some View {
        Button { selection = id } label: {
            HStack { Text(title); Spacer(); if selection == id { Image(systemName: "checkmark") } }
        }
    }
}
