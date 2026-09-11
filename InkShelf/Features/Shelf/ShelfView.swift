import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ShelfView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BookEntity.addedAt, order: .reverse) private var books: [BookEntity]
    @State private var query = ""
    @State private var importing = false
    @State private var importProgress: ImportProgress?
    @State private var showImporter = false
    @State private var toast: String?
    @State private var path = NavigationPath()
    @State private var readingBook: ReadingBookID?

    private var visible: [BookEntity] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return books }
        return books.filter {
            $0.title.lowercased().contains(q) || ($0.author ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if books.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 14)], spacing: 16) {
                            ForEach(visible, id: \.id) { book in
                                Button {
                                    readingBook = ReadingBookID(id: book.id)
                                } label: {
                                    BookCoverCell(book: book)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("打开阅读") { readingBook = ReadingBookID(id: book.id) }
                                    Button("详情") { path.append(DetailRoute(id: book.id)) }
                                    Button("删除", role: .destructive) {
                                        delete(book)
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .inkShelfScreenBackground()
            .navigationTitle("书架")
            .navigationDestination(for: DetailRoute.self) { route in
                if let book = books.first(where: { $0.id == route.id }) {
                    BookDetailView(bookID: book.id)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if importing {
                        ProgressView()
                    } else {
                        Button {
                            showImporter = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .accessibilityLabel("导入 TXT")
                    }
                }
            }
            .searchable(text: $query, prompt: "搜索书名或作者")
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.plainText, .text, UTType(filenameExtension: "txt") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .overlay {
                if importing {
                    ZStack {
                        Color.black.opacity(0.28).ignoresSafeArea()
                        VStack(spacing: 14) {
                            ProgressView(value: importProgress?.fraction ?? 0.05)
                                .progressViewStyle(.linear)
                                .frame(width: 180)
                            Text(importProgress?.stage.rawValue ?? "正在导入…")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(InkShelfColors.ink)
                            Text("大文件在后台处理，界面可保持响应")
                                .font(.caption)
                                .foregroundStyle(InkShelfColors.inkMuted)
                                .multilineTextAlignment(.center)
                        }
                        .padding(24)
                        .inkGlass(cornerRadius: 20)
                    }
                    .allowsHitTesting(true)
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    GlassToast(message: toast)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: toast)
            .fullScreenCover(item: $readingBook) { item in
                ReaderView(bookID: item.id)
                    .environmentObject(ReaderPrefs.shared)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(InkShelfColors.lamp)
                .padding(22)
                .inkGlass(cornerRadius: 28, tint: InkShelfColors.lamp.opacity(0.35))

            Text("还没有书")
                .font(.title3.weight(.semibold))
                .foregroundStyle(InkShelfColors.ink)

            Text("导入 TXT，或从书源搜索后加入书架。")
                .font(.subheadline)
                .foregroundStyle(InkShelfColors.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("导入 TXT") { showImporter = true }
                .tint(InkShelfColors.lamp)
                .inkGlassProminentButton()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            flash("导入失败：\(error.localizedDescription)")
        case .success(let urls):
            guard let url = urls.first else { return }
            importing = true
            importProgress = ImportProgress(stage: .reading, fraction: 0.02)
            Task {
                defer {
                    importing = false
                    importProgress = nil
                }
                do {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let data = try await Task.detached(priority: .userInitiated) {
                        try Data(contentsOf: url)
                    }.value
                    let name = url.deletingPathExtension().lastPathComponent
                    let book = try await LibraryService.importTxt(
                        data: data,
                        displayName: name,
                        context: context
                    ) { progress in
                        importProgress = progress
                    }
                    flash("已导入「\(book.title)」· \(book.chapterCount) 章")
                } catch {
                    flash("导入失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func delete(_ book: BookEntity) {
        do {
            try LibraryService.deleteBook(book, context: context)
            flash("已删除")
        } catch {
            flash("删除失败：\(error.localizedDescription)")
        }
    }

    private func flash(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toast == message { toast = nil }
        }
    }
}

struct DetailRoute: Hashable {
    var id: String
}

struct BookCoverCell: View {
    let book: BookEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(InkShelfColors.rule.opacity(0.28))
                    .aspectRatio(0.72, contentMode: .fit)
                    .overlay {
                        if let cover = book.coverUrl, let url = URL(string: cover) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().scaledToFill()
                                default:
                                    titlePlaceholder
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else {
                            titlePlaceholder
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8)
                    }
                    .shadow(color: InkShelfColors.ink.opacity(0.08), radius: 10, y: 4)

                Text("\(Int(book.progress * 100))%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(InkShelfColors.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .inkGlassCapsule(tint: InkShelfColors.lamp.opacity(0.25))
                    .padding(8)
            }

            Text(book.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(InkShelfColors.ink)
                .lineLimit(2)

            if book.isRemote {
                Text(book.sourceName ?? "书源")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(InkShelfColors.lamp)
            }
        }
    }

    private var titlePlaceholder: some View {
        Text(book.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(InkShelfColors.ink)
            .multilineTextAlignment(.center)
            .padding(10)
    }
}
