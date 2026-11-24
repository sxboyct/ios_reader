import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ReaderBackgroundStore: Sendable {
    public static let byteLimit = 32 * 1024 * 1024
    public static let pixelLimit = 2048
    public let file: URL

    public init(directory: URL = NovelLibrary.root.appendingPathComponent("Backgrounds", isDirectory: true)) {
        file = directory.appendingPathComponent("reading-background.png")
    }

    public func load() -> Data? {
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= Self.byteLimit else { return nil }
        return try? Data(contentsOf: file)
    }

    public func save(_ data: Data) throws -> Data {
        guard data.count <= Self.byteLimit else { throw ImportError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Self.pixelLimit,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw ImportError.invalidImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            throw ImportError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImportError.invalidImage }
        let normalized = output as Data
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try normalized.write(to: file, options: .atomic)
        return normalized
    }

    public func remove() throws {
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    private enum ImportError: LocalizedError {
        case tooLarge, invalidImage
        var errorDescription: String? {
            switch self {
            case .tooLarge: "背景图片不能超过 32 MB，请选择较小的图片。"
            case .invalidImage: "无法读取这张图片，请选择其他照片。"
            }
        }
    }
}
