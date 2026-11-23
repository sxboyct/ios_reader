import SwiftUI
import UIKit
import UniformTypeIdentifiers
import TVCore

/// Use an imported copy instead of asking a provider to open an in-place editable document.
struct DocumentImportPicker: UIViewControllerRepresentable {
    var folder = false
    var completion: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = folder ? [.folder] : [.data, .content, .json, .plainText]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: !folder)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (URL?) -> Void
        init(_ completion: @escaping (URL?) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(nil) }
    }
}

/// Retain the security-scoped grant while the user browses the selected folder and its descendants.
final class ImportFolderAccess {
    let url: URL
    private let granted: Bool
    init(_ url: URL) { self.url = url; granted = url.startAccessingSecurityScopedResource() }
    deinit { if granted { url.stopAccessingSecurityScopedResource() } }
}

struct SourceFileImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var picker: PickerKind?
    @State private var folder: ImportFolderAccess?
    @State private var busy = false
    @State private var error: String?
    var imported: (URL, Data) -> Void
    enum PickerKind: String, Identifiable { case file, folder; var id: String { rawValue } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("选择 JSON / XBS 文件", systemImage: "doc.badge.plus") { picker = .file }
                    Button("从文件夹导入", systemImage: "folder") { picker = .folder }
                    Text("若文件显示灰色，选择「从文件夹导入」，打开保存书源的文件夹并点「打开」，然后在下方列表选择文件。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.disabled(busy)
                if busy { ProgressView("正在读取文件…") }
                if let error { Text(error).foregroundStyle(.red) }
                if let folder {
                    Section(folder.url.lastPathComponent) {
                        FolderImportRows(directory: folder.url, busy: busy, select: read)
                    }.id(folder.url)
                }
            }
            .navigationTitle("导入书源")
            .toolbar { Button("取消") { dismiss() } }
            .sheet(item: $picker) { kind in
                DocumentImportPicker(folder: kind == .folder) { url in
                    picker = nil
                    guard let url else { return }
                    if kind == .folder { folder = ImportFolderAccess(url); error = nil }
                    else { read(url) }
                }.ignoresSafeArea()
            }
        }
    }
    private func read(_ url: URL) {
        busy = true; error = nil
        // Keep the folder grant alive through coordinated reads, including iCloud materialization.
        let access = folder
        Task {
            defer { busy = false; withExtendedLifetime(access) {} }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try ImportedFile.read(url, extensions: ["json", "xbs"], limit: HTTPClient.subscriptionLimit)
                }.value
                imported(url, data); dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct FolderImportRows: View {
    let directory: URL
    let busy: Bool
    let select: (URL) -> Void
    @State private var entries: [ImportDirectory.Entry] = []
    @State private var failure: String?
    var body: some View {
        Group {
            ForEach(entries, id: \.url) { entry in
                if entry.isDirectory {
                    NavigationLink {
                        List { FolderImportRows(directory: entry.url, busy: busy, select: select) }
                            .navigationTitle(entry.url.lastPathComponent)
                    } label: { Label(entry.url.lastPathComponent, systemImage: "folder") }
                } else {
                    Button { select(entry.url) } label: { Label(entry.url.lastPathComponent, systemImage: "doc.text") }
                        .disabled(busy)
                }
            }
            if let failure { Text(failure).foregroundStyle(.red) }
            if entries.isEmpty && failure == nil { Text("此文件夹内没有 JSON / XBS 文件。请确认文件已下载到本机，或进入子文件夹。") }
        }
        .task {
            let target = directory
            do { entries = try await Task.detached { try ImportDirectory.entries(at: target) }.value }
            catch { failure = error.localizedDescription }
        }
    }
}
