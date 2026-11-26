import SwiftUI
import UIKit
import ImageIO
import TVCore

enum AppPalette {
    static let accent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 1, green: 0.69, blue: 0.31, alpha: 1)
        : UIColor(red: 0.79, green: 0.40, blue: 0.08, alpha: 1) })
    static let paper = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.08, green: 0.085, blue: 0.09, alpha: 1)
        : UIColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1) })
    static let card = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.13, green: 0.135, blue: 0.14, alpha: 1)
        : UIColor(red: 1, green: 0.995, blue: 0.97, alpha: 1) })
}

extension View {
    func appPage() -> some View {
        scrollContentBackground(.hidden).background(AppPalette.paper)
            .toolbarBackground(AppPalette.paper, for: .navigationBar)
    }
    func bookCard() -> some View {
        background(AppPalette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.045), lineWidth: 1) }
            .shadow(color: .black.opacity(0.035), radius: 12, x: 0, y: 6)
    }
    func cardListRow() -> some View {
        listRowSeparator(.hidden).listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
    }
}

struct BookCover: View {
    let book: NovelBook
    var width: CGFloat = 72
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            LinearGradient(colors: [AppPalette.accent.opacity(0.20), AppPalette.card], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else {
                VStack(spacing: 10) {
                    Image(systemName: "book.closed").font(.title3)
                    Text(book.name).font(.system(size: max(11, width / 7), weight: .semibold, design: .serif))
                        .lineLimit(3).multilineTextAlignment(.center)
                }.padding(9).foregroundStyle(AppPalette.accent)
            }
        }
        .frame(width: width, height: width * 1.38).clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.06), lineWidth: 0.5) }
        .accessibilityHidden(true)
        .task(id: book.cover) {
            image = nil
            let loaded = await BookCoverCache.shared.image(for: book)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

@MainActor private final class BookCoverCache {
    static let shared = BookCoverCache()
    private let images = NSCache<NSString, UIImage>()
    init() { images.totalCostLimit = 32 * 1024 * 1024; images.countLimit = 160 }
    func image(for book: NovelBook) async -> UIImage? {
        guard let cover = book.coverRequest else { return nil }
        let key = book.cover as NSString
        if let kept = images.object(forKey: key) { return kept }
        do {
            let (data, _) = try await HTTPClient().get(cover.url, headers: cover.headers, limit: 8 * 1024 * 1024)
            // Decode a thumbnail away from the UI thread; the original may be very large.
            let thumbnail = await Task.detached(priority: .utility) { () -> Data? in
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 480,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { return nil }
                let output = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
                CGImageDestinationAddImage(destination, cg, nil)
                guard CGImageDestinationFinalize(destination) else { return nil }
                return output as Data
            }.value
            guard !Task.isCancelled, let thumbnail, let image = UIImage(data: thumbnail) else { return nil }
            images.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4))
            return image
        } catch { return nil }
    }
}

struct BookRow: View {
    let book: NovelBook
    var rank: Int? = nil
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let rank {
                Text("\(rank)").font(.headline.monospacedDigit())
                    .foregroundStyle(rank <= 3 ? Color.white : Color.secondary)
                    .frame(width: 28, height: 30)
                    .background(rank == 1 ? Color.red.opacity(0.85) : rank <= 3 ? AppPalette.accent : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("第 \(rank) 名")
            }
            BookCover(book: book)
            VStack(alignment: .leading, spacing: 6) {
                Text(book.name).font(.headline).foregroundStyle(.primary).lineLimit(2)
                Text(book.author.isEmpty ? "佚名" : book.author).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if !book.intro.isEmpty {
                    Text(book.intro).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                } else if !book.lastChapter.isEmpty {
                    Text(book.lastChapter).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if !book.wordCount.isEmpty {
                    Text(book.wordCount).font(.caption2.weight(.medium)).foregroundStyle(AppPalette.accent)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(14).bookCard().contentShape(Rectangle())
    }
}
