import SwiftUI
import UIKit
import UniformTypeIdentifiers
import TVCore

/// Use an imported copy instead of asking a provider to open an in-place editable document.
struct DocumentImportPicker: UIViewControllerRepresentable {
    var completion: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.data, .content, .json, .plainText]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
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

struct SourceFileImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var busy = false
    @State private var error: String?
    var imported: (URL, Data) -> Void
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("选择 JSON / XBS 文件", systemImage: "doc.badge.plus") { picking = true }
                    Text("请选择 JSON / XBS 书源文件。如文件在 iCloud 或其他云盘，请先下载到本机。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.disabled(busy)
                if busy { ProgressView("正在读取文件…") }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("导入书源")
            .toolbar { Button("取消") { dismiss() } }
            .sheet(isPresented: $picking) {
                DocumentImportPicker { url in
                    picking = false
                    guard let url else { return }
                    read(url)
                }.ignoresSafeArea()
            }
        }
    }
    private func read(_ url: URL) {
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try ImportedFile.read(url, extensions: ["json", "xbs"], limit: HTTPClient.subscriptionLimit)
                }.value
                imported(url, data); dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

