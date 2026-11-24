import Foundation
import Testing
import UIKit
@testable import TVCore

@MainActor
struct ReaderBackgroundStoreTests {
    @Test func importsDownsamplesRestoresAndRemoves() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReaderBackgroundStore(directory: directory)
        #expect(store.load() == nil)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1500), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1500))
        }
        let saved = try store.save(#require(image.jpegData(compressionQuality: 0.8)))
        let restored = try #require(UIImage(data: saved)?.cgImage)
        #expect(restored.width == ReaderBackgroundStore.pixelLimit)
        #expect(restored.height == ReaderBackgroundStore.pixelLimit / 2)
        #expect(ReaderBackgroundStore(directory: directory).load() == saved)
        #expect(throws: (any Error).self) { try store.save(Data("not an image".utf8)) }
        #expect(store.load() == saved)
        try store.remove()
        try store.remove()
        #expect(store.load() == nil)
    }

    @Test func rejectsOversizedInputWithoutSaving() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReaderBackgroundStore(directory: directory)
        #expect(throws: (any Error).self) { try store.save(Data(count: ReaderBackgroundStore.byteLimit + 1)) }
        #expect(store.load() == nil)
    }
}
