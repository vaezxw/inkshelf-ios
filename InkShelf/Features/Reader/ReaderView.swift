import SwiftUI
import SwiftData
import UIKit

struct ReadingBookID: Identifiable, Hashable {
    var id: String
}

struct ReaderView: View {
    let bookID: String

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var prefs: ReaderPrefs
    @Query private var books: [BookEntity]

    @StateObject private var speech = SpeechController()
    @State private var chapterIndex = 0
    @State private var chapterText = ""
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var showChrome = true
    @State private var showTOC = false
    @State private var showPrefs = false
    @State private var pageIndex = 0
    @State private var pageStrings: [String] = [""]
    @State private var toast: String?
    @State private var autoTask: Task<Void, Never>?
    @State private var pageSize: CGSize = CGSize(width: 320, height: 480)
    @State private var paginateGeneration = 0

    private var book: BookEntity? { books.first { $0.id == bookID } }
    private var chapters: [ChapterEntity] {
        (book?.chapters ?? []).sorted { $0.index < $1.index }
    }

    var body: some View {
        ZStack {
            palette.bg.ignoresSafeArea()

            contentBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showChrome {
                VStack(spacing: 0) {
                    topChrome
                    Spacer(minLength: 0)
                    bottomChrome
                }
                .transition(.opacity)
            }

            if let toast {
                VStack {
                    Spacer()
                    GlassToast(message: toast)
                        .padding(.bottom, showChrome ? 120 : 36)
                }
            }
        }
        .statusBarHidden(!showChrome)
        .onAppear {
            guard let book else { return }
            chapterIndex = min(max(book.lastChapterIndex, 0), max(chapters.count - 1, 0))
            applyBrightness()
            Task { await loadChapter(resetPage: true) }
        }
        .onDisappear {
            stopAutoRead()
            speech.stop()
            ScreenBrightness.restoreIfNeeded()
            saveProgress()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerPageDidChange)) { note in
            if let idx = note.object as? Int {
                pageIndex = idx
                saveProgress()
            }
        }
        .onChange(of: prefs.fontSize) { _, _ in Task { await rebuildPagesIncremental(resetPage: false) } }
        .onChange(of: prefs.lineHeight) { _, _ in Task { await rebuildPagesIncremental(resetPage: false) } }
        .onChange(of: prefs.autoReadEnabled) { _, enabled in
            if enabled { startAutoRead() } else { stopAutoRead() }
        }
        .onChange(of: prefs.autoReadSpeed) { _, _ in
            if prefs.autoReadEnabled { startAutoRead() }
        }
        .onChange(of: prefs.followSystemBrightness) { _, _ in applyBrightness() }
        .onChange(of: prefs.brightness) { _, _ in applyBrightness() }
        .sheet(isPresented: $showTOC) { tocSheet }
        .sheet(isPresented: $showPrefs) { ReaderPrefsSheet() }
    }

    @ViewBuilder
    private var contentBody: some View {
        if loading && chapterText.isEmpty {
            ProgressView("加载中…")
        } else if let errorMessage, chapterText.isEmpty {
            ContentUnavailableView {
                Label("无法打开", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("重试") { Task { await loadChapter(resetPage: true) } }
                    .tint(InkShelfColors.lamp)
                    .inkGlassProminentButton()
            }
        } else {
            GeometryReader { geo in
                let size = CGSize(
                    width: max(geo.size.width - 32, 40),
                    height: max(geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom - 24, 80)
                )
                Group {
                    switch prefs.readMode {
                    case .pageFlip:
                        ReaderPageHost(
                            pages: pageStrings,
                            pageIndex: $pageIndex,
                            fontSize: prefs.fontSize,
                            lineHeight: prefs.lineHeight,
                            textColor: UIColor(palette.fg),
                            backgroundColor: UIColor(palette.bg),
                            onToggleChrome: {
                                withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
                            },
                            onTurnPastEnd: { goChapter(chapterIndex + 1) },
                            onTurnPastStart: { goChapter(chapterIndex - 1) }
                        )
                    case .verticalScroll:
                        ReaderScrollHost(
                            text: chapterText,
                            fontSize: prefs.fontSize,
                            lineHeight: prefs.lineHeight,
                            textColor: UIColor(palette.fg),
                            backgroundColor: UIColor(palette.bg),
                            onToggleChrome: {
                                withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
                            }
                        )
                    }
                }
                .onAppear {
                    if abs(pageSize.width - size.width) > 1 || abs(pageSize.height - size.height) > 1 {
                        pageSize = size
                        Task { await rebuildPagesIncremental(resetPage: false) }
                    }
                }
                .onChange(of: geo.size) { _, _ in
                    let next = CGSize(
                        width: max(geo.size.width - 32, 40),
                        height: max(geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom - 24, 80)
                    )
                    guard abs(pageSize.width - next.width) > 1 || abs(pageSize.height - next.height) > 1 else { return }
                    pageSize = next
                    Task { await rebuildPagesIncremental(resetPage: false) }
                }
            }
        }
    }

    private var topChrome: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(book?.title ?? "")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.fg)
                    .lineLimit(1)
                Text(chapters.indices.contains(chapterIndex) ? chapters[chapterIndex].title : "")
                    .font(.caption2)
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(pageLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.muted)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private var bottomChrome: some View {
        VStack(spacing: 8) {
            HStack {
                chromeButton("chevron.left.2", "上一章", disabled: chapterIndex <= 0) {
                    goChapter(chapterIndex - 1)
                }
                chromeButton("list.bullet", "目录") { showTOC = true }
                chromeButton("chevron.right.2", "下一章", disabled: chapterIndex >= chapters.count - 1) {
                    goChapter(chapterIndex + 1)
                }
            }
            HStack {
                chromeButton(isBookmarked ? "bookmark.fill" : "bookmark", "书签") { toggleBookmark() }
                chromeButton(speech.isSpeaking ? "stop.fill" : "speaker.wave.2.fill", "听书") {
                    if speech.isSpeaking {
                        speech.stop()
                    } else {
                        prefs.autoReadEnabled = false
                        speech.speak(chapterText)
                    }
                }
                chromeButton("textformat.size", "排版") { showPrefs = true }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var pageLabel: String {
        if prefs.readMode == .pageFlip, pageStrings.count > 0 {
            return "\(pageIndex + 1)/\(pageStrings.count) · \(chapterIndex + 1)/\(max(chapters.count, 1))"
        }
        return "\(chapterIndex + 1)/\(max(chapters.count, 1))"
    }

    private func chromeButton(
        _ systemName: String,
        _ title: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.body.weight(.medium))
                Text(title).font(.caption2)
            }
            .foregroundStyle(palette.fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .buttonStyle(.plain)
    }

    private var palette: (bg: Color, fg: Color, muted: Color) {
        switch prefs.themeMode {
        case .night:
            return (InkShelfColors.nightPaper, InkShelfColors.nightInk, InkShelfColors.nightMuted)
        case .paper:
            return (InkShelfColors.paper, InkShelfColors.ink, InkShelfColors.inkMuted)
        case .system:
            return (Color(.systemBackground), Color(.label), Color(.secondaryLabel))
        }
    }

    private var tocSheet: some View {
        NavigationStack {
            List {
                Section("目录") {
                    ForEach(chapters, id: \.id) { ch in
                        Button {
                            showTOC = false
                            goChapter(ch.index)
                        } label: {
                            HStack {
                                Text(ch.title).foregroundStyle(palette.fg)
                                Spacer()
                                if ch.index == chapterIndex {
                                    Image(systemName: "checkmark").foregroundStyle(InkShelfColors.lamp)
                                }
                            }
                        }
                    }
                }
                if let book, !book.bookmarks.isEmpty {
                    Section("书签") {
                        ForEach(book.bookmarks.sorted(by: { $0.createdAt > $1.createdAt }), id: \.id) { bm in
                            Button {
                                showTOC = false
                                goChapter(bm.chapterIndex)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(bm.title)
                                    Text("第 \(bm.chapterIndex + 1) 章").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("目录与书签")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showTOC = false }
                }
            }
        }
    }

    private var isBookmarked: Bool {
        book?.bookmarks.contains(where: { $0.chapterIndex == chapterIndex }) == true
    }

    private func loadChapter(resetPage: Bool) async {
        guard let book else { return }
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            let text: String
            if book.isRemote {
                text = try await SourceRepository.loadRemoteChapterText(
                    book: book,
                    chapterIndex: chapterIndex,
                    context: context
                )
            } else {
                let chaptersSorted = chapters
                guard chapterIndex >= 0, chapterIndex < chaptersSorted.count else {
                    text = ""
                    chapterText = text
                    return
                }
                let ch = chaptersSorted[chapterIndex]
                let bookId = book.id
                let start = ch.startOffset
                let length = ch.length
                let idx = chapterIndex
                text = try await Task.detached(priority: .userInitiated) {
                    try LibraryService.loadLocalChapterText(
                        bookId: bookId,
                        chapterIndex: idx,
                        start: start,
                        length: length
                    )
                }.value
            }
            chapterText = text
            if text.isEmpty && book.isRemote {
                errorMessage = "章节内容为空（请换书源，或该站正文规则含 JS）"
            }
            await rebuildPagesIncremental(resetPage: resetPage)
            saveProgress()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rebuildPagesIncremental(resetPage: Bool) async {
        guard prefs.readMode == .pageFlip else {
            pageStrings = [chapterText]
            return
        }
        paginateGeneration += 1
        let gen = paginateGeneration
        let text = chapterText
        let size = pageSize
        let fontSize = prefs.fontSize
        let lineHeight = prefs.lineHeight
        guard size.width > 20, size.height > 40 else {
            pageStrings = text.isEmpty ? [""] : [text]
            return
        }

        if resetPage {
            pageIndex = 0
            pageStrings = [""]
        }

        let stream = AsyncStream<[String]> { continuation in
            Task.detached(priority: .userInitiated) {
                let ns = text as NSString
                var ranges: [PageRange] = []
                for await range in PagePaginator.paginateRangesStream(
                    text: text,
                    size: size,
                    font: UIFont.systemFont(ofSize: fontSize),
                    lineHeightMultiple: lineHeight
                ) {
                    ranges.append(range)
                    if ranges.count == 1 || ranges.count % 8 == 0 {
                        continuation.yield(ranges.map { ns.substring(with: $0.nsRange) })
                    }
                }
                let finalPages = ranges.map { ns.substring(with: $0.nsRange) }
                continuation.yield(finalPages.isEmpty ? [""] : finalPages)
                continuation.finish()
            }
        }

        for await pages in stream {
            guard gen == paginateGeneration else { return }
            pageStrings = pages
            pageIndex = min(pageIndex, max(pages.count - 1, 0))
        }
    }

    private func goChapter(_ index: Int) {
        guard index >= 0, index < chapters.count, index != chapterIndex else { return }
        speech.stop()
        chapterIndex = index
        Task { await loadChapter(resetPage: true) }
    }

    private func nextPageOrChapter() {
        if pageIndex < pageStrings.count - 1 {
            pageIndex += 1
        } else {
            goChapter(chapterIndex + 1)
        }
    }

    private func toggleBookmark() {
        guard let book else { return }
        let title = chapters.indices.contains(chapterIndex) ? chapters[chapterIndex].title : "书签"
        do {
            let added = try LibraryService.toggleBookmark(
                book: book,
                chapterIndex: chapterIndex,
                title: title,
                scrollOffset: Double(pageIndex),
                context: context
            )
            flash(added ? "已添加书签" : "已移除书签")
        } catch {
            flash("书签失败")
        }
    }

    private func saveProgress() {
        guard let book else { return }
        try? LibraryService.updateProgress(
            book: book,
            chapterIndex: chapterIndex,
            scrollOffset: Double(pageIndex),
            context: context
        )
    }

    private func applyBrightness() {
        ScreenBrightness.apply(followSystem: prefs.followSystemBrightness, value: prefs.brightness)
    }

    private func startAutoRead() {
        stopAutoRead()
        speech.stop()
        autoTask = Task { @MainActor in
            while !Task.isCancelled, prefs.autoReadEnabled {
                let interval = 1.8 / max(prefs.autoReadSpeed, 0.4)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, prefs.autoReadEnabled else { break }
                if prefs.readMode == .pageFlip {
                    nextPageOrChapter()
                } else if chapterIndex < chapters.count - 1 {
                    goChapter(chapterIndex + 1)
                } else {
                    prefs.autoReadEnabled = false
                    break
                }
            }
        }
    }

    private func stopAutoRead() {
        autoTask?.cancel()
        autoTask = nil
    }

    private func flash(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if toast == message { toast = nil }
        }
    }
}

struct ReaderPrefsSheet: View {
    @EnvironmentObject private var prefs: ReaderPrefs
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("阅读模式") {
                    Picker("模式", selection: $prefs.readMode) {
                        ForEach(ReadMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }
                Section("排版") {
                    HStack {
                        Text("字号 \(Int(prefs.fontSize))")
                        Slider(value: $prefs.fontSize, in: 14...28, step: 1)
                    }
                    HStack {
                        Text("行距 \(String(format: "%.1f", prefs.lineHeight))")
                        Slider(value: $prefs.lineHeight, in: 1.2...2.2, step: 0.1)
                    }
                    Picker("主题", selection: $prefs.themeMode) {
                        ForEach(ReaderThemeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }
                Section("自动阅读") {
                    Toggle("开启自动翻页", isOn: $prefs.autoReadEnabled)
                    if prefs.autoReadEnabled {
                        HStack {
                            Text("速度 \(String(format: "%.1f", prefs.autoReadSpeed))x")
                            Slider(value: $prefs.autoReadSpeed, in: 0.4...3.0, step: 0.1)
                        }
                    }
                }
                Section("亮度") {
                    Toggle("跟随系统", isOn: $prefs.followSystemBrightness)
                    if !prefs.followSystemBrightness {
                        HStack {
                            Text("\(Int(prefs.brightness * 100))%")
                            Slider(value: $prefs.brightness, in: 0.05...1.0)
                        }
                    }
                }
            }
            .navigationTitle("阅读设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
