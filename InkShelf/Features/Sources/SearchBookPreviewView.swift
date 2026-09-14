import SwiftUI
import SwiftData

struct SearchBookPreviewView: View {
    let hit: SearchBookHit
    let source: BookSourceEntity
    var onAdded: ((BookEntity) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var chapters: [RemoteChapter] = []
    @State private var loadingTOC = true
    @State private var tocError: String?
    @State private var adding = false
    @State private var toast: String?
    @State private var showAllChapters = false
    @State private var expandIntro = false

    private let previewChapterLimit = 40

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    bookHeader
                    tocSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
            .scrollContentBackground(.hidden)
            .inkShelfScreenBackground()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                addBar
            }
            .navigationTitle("书籍预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    GlassToast(message: toast)
                        .padding(.bottom, 88)
                }
            }
            .task { await loadTOC() }
        }
    }

    private var bookHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hit.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(InkShelfColors.ink)

            HStack(spacing: 8) {
                if let author = hit.author, !author.isEmpty {
                    Label(author, systemImage: "person")
                }
                Text(hit.sourceName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(InkShelfColors.lamp)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .inkGlassCapsule(tint: InkShelfColors.lamp.opacity(0.28))
            }
            .font(.subheadline)
            .foregroundStyle(InkShelfColors.inkMuted)

            Text("简介")
                .font(.headline)
                .foregroundStyle(InkShelfColors.ink)
                .padding(.top, 2)

            Text(introText)
                .font(.subheadline)
                .foregroundStyle(InkShelfColors.inkMuted)
                .lineLimit(expandIntro ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)

            if introText.count > 80 {
                Button(expandIntro ? "收起简介" : "展开简介") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandIntro.toggle()
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(InkShelfColors.lamp)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var tocSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tocTitle)
                    .font(.headline)
                    .foregroundStyle(InkShelfColors.ink)
                Spacer()
                if !loadingTOC, chapters.count > previewChapterLimit {
                    Button(showAllChapters ? "只看前 \(previewChapterLimit) 章" : "展开全部") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAllChapters.toggle()
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(InkShelfColors.lamp)
                }
            }

            if loadingTOC {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("加载目录…")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if let tocError {
                Text(tocError)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if chapters.isEmpty {
                Text("目录为空（仍可尝试加入书架，加入时会再拉一次目录）")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visibleChapters.enumerated()), id: \.offset) { index, chapter in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                            Text(chapter.title)
                                .font(.subheadline)
                                .foregroundStyle(InkShelfColors.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 8)
                        if index < visibleChapters.count - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }

                if !showAllChapters, chapters.count > previewChapterLimit {
                    Text("已预览 \(previewChapterLimit)/\(chapters.count) 章 · 完整目录加入书架后可在阅读页查看")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var addBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            Button {
                Task { await addToShelf() }
            } label: {
                Group {
                    if adding {
                        ProgressView()
                    } else {
                        Text("加入书架")
                            .font(.body.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .tint(InkShelfColors.lamp)
            .inkGlassProminentButton()
            .disabled(adding)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(.bar)
        }
    }

    private var tocTitle: String {
        if loadingTOC { return "目录" }
        if chapters.isEmpty { return "目录" }
        return "目录 · \(chapters.count) 章"
    }

    private var visibleChapters: [RemoteChapter] {
        if showAllChapters || chapters.count <= previewChapterLimit {
            return chapters
        }
        return Array(chapters.prefix(previewChapterLimit))
    }

    private var introText: String {
        let intro = hit.intro?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return intro.isEmpty ? "暂无简介" : intro
    }

    private func loadTOC() async {
        loadingTOC = true
        tocError = nil
        defer { loadingTOC = false }
        do {
            chapters = try await SourceEngine.fetchToc(
                rawSourceJSON: source.legadoRaw,
                bookUrl: hit.bookUrl
            )
        } catch {
            tocError = error.localizedDescription
            chapters = []
        }
    }

    private func addToShelf() async {
        adding = true
        defer { adding = false }
        do {
            let book = try await SourceRepository.addRemoteBook(
                hit: hit,
                source: source,
                context: context
            )
            toast = "已加入「\(book.title)」"
            onAdded?(book)
            try? await Task.sleep(nanoseconds: 600_000_000)
            dismiss()
        } catch {
            toast = "加入失败：\(error.localizedDescription)"
        }
    }
}
