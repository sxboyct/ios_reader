import SwiftUI
import UIKit
import PhotosUI
import TVCore

@MainActor @Observable
final class ReaderBackgrounds {
    static let shared = ReaderBackgrounds()
    private let store = ReaderBackgroundStore()
    var image: UIImage?
    var busy = false
    var error: String?

    private init() { image = store.load().flatMap { UIImage(data: $0) } }

    func importPhoto(_ item: PhotosPickerItem) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                error = "无法读取照片，请确认照片已下载后重试。"
                return
            }
            let store = self.store
            let normalized = try await Task.detached(priority: .userInitiated) { try store.save(data) }.value
            image = UIImage(data: normalized)
        } catch { self.error = error.localizedDescription }
    }

    func remove() {
        do { try store.remove(); image = nil }
        catch { self.error = error.localizedDescription }
    }
}
