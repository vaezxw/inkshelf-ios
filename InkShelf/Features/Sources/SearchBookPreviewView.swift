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

    var body: some View {
        NavigationStack {
            List {
                Section {
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
                            .padding(.top, 4)

                        Text(introText)
                            .font(.subheadline)
                            .foregroundStyle(InkShelfColors.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                }

                Section {
                    if loadingTOC {
                        HStack {
                            ProgressView()
                            Text("加载目录…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let tocError {
                        Text(tocError)
                            .foregroundStyle(.secondary)
                    } else if chapters.isEmpty {
                        Text("目录为空")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, alignment: .trailing)
                                Text(chapter.title)
                                    .font(.subheadline)
                            }
                        }
                    }
                } header: {
                    Text(loadingTOC ? "目录" : "目录 · \(chapters.count) 章")
                }

                Section {
                    Button {
                        Task { await addToShelf() }
                    } label: {
                        if adding {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("加入书架")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .tint(InkShelfColors.lamp)
                    .inkGlassProminentButton()
                    .disabled(adding || loadingTOC)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .inkShelfScreenBackground()
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
                        .padding(.bottom, 12)
                }
            }
            .task { await loadTOC() }
        }
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
