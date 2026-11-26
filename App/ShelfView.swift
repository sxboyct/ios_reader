import SwiftUI
import TVCore

struct ShelfView: View {
    @Environment(ReaderLibrary.self) private var library
    @State private var query = ""
    @State private var onlyStarted = false
    private var books: [NovelLibrary.ShelfBook] {
        library.shelf.filter {
            (!onlyStarted || $0.started) && (query.isEmpty || ($0.book.name + $0.book.author).localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        List {
            HStack {
                Text(onlyStarted ? "继续你的阅读" : "我的藏书").font(.title3.bold())
                Spacer()
                Text("\(books.count) 本").font(.subheadline).foregroundStyle(.secondary)
            }.padding(.vertical, 4).cardListRow()
            ForEach(books) { entry in
                NavigationLink { BookDetailView(book: entry.book) } label: { ShelfBookCard(entry: entry) }
                    .buttonStyle(.plain).cardListRow()
                    .swipeActions {
                        Button("移出书架", role: .destructive) { library.remove(entry.book) }
                    }
                    .contextMenu {
                        Button(role: .destructive) { library.remove(entry.book) } label: { Label("移出书架", systemImage: "trash") }
                    }
            }
        }
        .listStyle(.plain).appPage()
        .overlay {
            if books.isEmpty {
                ContentUnavailableView(library.shelf.isEmpty ? "把喜欢的故事留在这里" : "没有找到书籍",
                    systemImage: library.shelf.isEmpty ? "books.vertical" : "magnifyingglass",
                    description: Text(library.shelf.isEmpty ? "在找书或发现中挑选一本，开启阅读。" : "试试其他书名，或切换为全部藏书。"))
            }
        }
        .navigationTitle("书架")
        .task { await library.refreshMissingCovers() }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索书名或作者")
        .toolbar {
            Menu {
                Picker("显示书籍", selection: $onlyStarted) {
                    Text("全部藏书").tag(false)
                    Text("正在阅读").tag(true)
                }
            } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                .accessibilityLabel("筛选书架")
        }
    }
}

private struct ShelfBookCard: View {
    let entry: NovelLibrary.ShelfBook
    private var progress: Double {
        guard entry.chapterCount > 0 else { return 0 }
        return min(1, max(0, (Double(entry.chapterIndex) + entry.position) / Double(entry.chapterCount)))
    }
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BookCover(book: entry.book, width: 86)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 6) {
                    Text(entry.book.name).font(.headline).lineLimit(2).foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Text(entry.started ? "\(Int(progress * 100))%" : "未读")
                        .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(AppPalette.accent)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(AppPalette.accent.opacity(0.08), in: Capsule())
                }
                Text(entry.book.author.isEmpty ? "佚名" : entry.book.author).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Label(entry.started ? entry.chapterTitle : "尚未开始阅读", systemImage: "bookmark.fill")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !entry.book.lastChapter.isEmpty {
                    Label(entry.book.lastChapter, systemImage: "arrow.up.circle").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if !entry.book.wordCount.isEmpty {
                    Text(entry.book.wordCount).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                ProgressView(value: progress).tint(AppPalette.accent).padding(.top, 3)
                    .accessibilityLabel("阅读进度").accessibilityValue("\(Int(progress * 100))%")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(14).bookCard().contentShape(Rectangle())
    }
}

