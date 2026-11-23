import Foundation

public enum ImportDirectory {
    public struct Entry: Sendable {
        public let url: URL
        public let isDirectory: Bool
    }
    /// Lists only the folder explicitly granted by the user. Symlinks and packages are not traversed.
    public static func entries(at folder: URL) throws -> [Entry] {
        try FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey], options: [.skipsHiddenFiles])
            .compactMap { url -> Entry? in
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
                guard values.isSymbolicLink != true, values.isPackage != true else { return nil }
                let directory = values.isDirectory == true
                guard directory || ["json", "xbs"].contains(url.pathExtension.lowercased()) else { return nil }
                return Entry(url: url, isDirectory: directory)
            }
            .sorted {
                $0.isDirectory != $1.isDirectory ? $0.isDirectory :
                    $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
    }
}
