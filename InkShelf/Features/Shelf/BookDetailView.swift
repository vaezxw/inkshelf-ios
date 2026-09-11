import SwiftUI
import SwiftData

struct BookDetailView: View {
    let bookID: String
    @Environment(\.modelContext) private var context
    @Query private var books: [BookEntity]
    @State private var refreshing = false
    @State private var message: String?

    private var book: BookEntity? { books.first { $0.id == bookID } }

    var body: some View {
        Group {
            if let book {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 16) {
                            cover(book)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(book.title)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(InkShelfColors.ink)
                                if let author = book.author {
                                    Text(author).foregroundStyle(InkShelfColors.inkMuted)
                                }
                                if book.isRemote {
                                    Text(book.sourceName ?? "书源")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(InkShelfColors.lamp)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .inkGlassCapsule(tint: InkShelfColors.lamp.opacity(0.3))
                                }
                                Text("进度 \(book.lastChapterIndex + 1)/\(max(book.chapterCount, 1))")
                                    .font(.caption)
                                    .foregroundStyle(InkShelfColors.inkMuted)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(16)
                        .inkGlass(cornerRadius: 20)

                        if let intro = book.intro, !intro.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("简介").font(.headline).foregroundStyle(InkShelfColors.ink)
                                Text(intro).foregroundStyle(InkShelfColors.inkMuted)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .inkGlass(cornerRadius: 18)
                        }

                        InkGlassGroup(spacing: 12) {
                            VStack(spacing: 12) {
                                NavigationLink {
                                    ReaderView(bookID: book.id)
                                } label: {
                                    Text("继续阅读")
                                        .frame(maxWidth: .infinity)
                                }
                                .tint(InkShelfColors.lamp)
                                .inkGlassProminentButton()

                                if book.isRemote {
                                    Button {
                                        Task { await refresh(book) }
                                    } label: {
                                        if refreshing {
                                            ProgressView()
                                                .frame(maxWidth: .infinity)
                                        } else {
                                            Label("从书源刷新目录", systemImage: "arrow.clockwise")
                                                .frame(maxWidth: .infinity)
                                        }
                                    }
                                    .inkGlassButton()
                                }
                            }
                        }

                        if let message {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(20)
                }
                .inkShelfScreenBackground()
                .navigationTitle("详情")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("书籍不存在", systemImage: "questionmark.folder")
                    .inkShelfScreenBackground()
            }
        }
    }

    private func cover(_ book: BookEntity) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(InkShelfColors.rule.opacity(0.35))
            .frame(width: 96, height: 128)
            .overlay {
                if let cover = book.coverUrl, let url = URL(string: cover) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.8)
            }
            .shadow(color: InkShelfColors.ink.opacity(0.1), radius: 8, y: 3)
    }

    private func refresh(_ book: BookEntity) async {
        refreshing = true
        defer { refreshing = false }
        do {
            try await SourceRepository.refreshToc(book: book, context: context)
            message = "目录已更新 · \(book.chapterCount) 章"
        } catch {
            message = "刷新失败：\(error.localizedDescription)"
        }
    }
}
