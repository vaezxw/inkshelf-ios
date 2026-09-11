import SwiftUI
import SwiftData
import UIKit

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
    @State private var pages: [String] = [""]
    @State private var toast: String?
    @State private var autoTask: Task<Void, Never>?
    @State private var contentSize: CGSize = .zero

    private var book: BookEntity? { books.first { $0.id == bookID } }
    private var chapters: [ChapterEntity] {
        (book?.chapters ?? []).sorted { $0.index < $1.index }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                palette.bg.ignoresSafeArea()
                if loading && chapterText.isEmpty {
                    ProgressView("加载中…")
                } else if let errorMessage, chapterText.isEmpty {
                    ContentUnavailableView("无法打开", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else {
                    contentArea(size: geo.size)
                }
                if showChrome {
                    chromeOverlay
                }
                if let toast {
                    VStack {
                        Spacer()
                        GlassToast(message: toast)
                            .padding(.bottom, 28)
                    }
                }
            }
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
            .onChange(of: prefs.fontSize) { _, _ in rebuildPages(size: contentSize) }
            .onChange(of: prefs.lineHeight) { _, _ in rebuildPages(size: contentSize) }
            .onChange(of: prefs.themeMode) { _, _ in }
            .onChange(of: prefs.followSystemBrightness) { _, _ in applyBrightness() }
            .onChange(of: prefs.brightness) { _, _ in applyBrightness() }
            .onChange(of: prefs.autoReadEnabled) { _, enabled in
                if enabled { startAutoRead() } else { stopAutoRead() }
            }
            .onChange(of: prefs.autoReadSpeed) { _, _ in
                if prefs.autoReadEnabled { startAutoRead() }
            }
            .sheet(isPresented: $showTOC) { tocSheet }
            .sheet(isPresented: $showPrefs) { ReaderPrefsSheet() }
            .toolbar(.hidden, for: .navigationBar)
            .statusBarHidden(!showChrome)
        }
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

    @ViewBuilder
    private func contentArea(size: CGSize) -> some View {
        let pad = EdgeInsets(top: 48, leading: 20, bottom: 36, trailing: 20)
        let pageSize = CGSize(
            width: max(size.width - pad.leading - pad.trailing, 40),
            height: max(size.height - pad.top - pad.bottom, 80)
        )
        Group {
            switch prefs.readMode {
            case .pageFlip:
                pageFlipView(pageSize: pageSize)
            case .verticalScroll:
                verticalScrollView
            }
        }
        .padding(pad)
        .foregroundStyle(palette.fg)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
        }
        .gesture(chapterSwipe)
        .background(
            GeometryReader { g in
                Color.clear.onAppear {
                    contentSize = pageSize
                    rebuildPages(size: pageSize)
                }
                .onChange(of: g.size) { _, _ in
                    contentSize = pageSize
                    rebuildPages(size: pageSize)
                }
            }
        )
    }

    private var chapterSwipe: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                switch prefs.readMode {
                case .pageFlip:
                    if abs(dx) > abs(dy) * 1.2 {
                        if dx < -60 { nextPageOrChapter() }
                        else if dx > 60 { prevPageOrChapter() }
                    }
                case .verticalScroll:
                    if abs(dx) > abs(dy) * 1.4 {
                        if dx < -60 { goChapter(chapterIndex + 1) }
                        else if dx > 60 { goChapter(chapterIndex - 1) }
                    }
                }
            }
    }

    private func pageFlipView(pageSize: CGSize) -> some View {
        TabView(selection: $pageIndex) {
            ForEach(Array(pages.enumerated()), id: \.offset) { idx, page in
                ScrollView {
                    Text(page)
                        .font(.system(size: prefs.fontSize))
                        .lineSpacing(max(0, prefs.fontSize * (prefs.lineHeight - 1)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .tag(idx)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: pageIndex) { old, new in
            if new == pages.count - 1, old == pages.count - 1 {
                // stay
            }
            if new >= pages.count - 1 && old == pages.count - 1 {
                // noop
            }
            // Edge chapter change when swiping past last/first via chrome buttons;
            // TabView won't overscroll — use toolbar / edge taps.
        }
        .overlay {
            HStack {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: 40)
                    .onTapGesture { prevPageOrChapter() }
                Spacer()
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: 40)
                    .onTapGesture { nextPageOrChapter() }
            }
            .allowsHitTesting(showChrome == false)
        }
    }

    private var verticalScrollView: some View {
        ScrollView {
            Text(chapterText)
                .font(.system(size: prefs.fontSize))
                .lineSpacing(max(0, prefs.fontSize * (prefs.lineHeight - 1)))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var chromeOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .padding(10)
                }
                .inkGlassCapsule(interactive: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(book?.title ?? "")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(chapters.indices.contains(chapterIndex) ? chapters[chapterIndex].title : "")
                        .font(.caption2)
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(chapterIndex + 1)/\(max(chapters.count, 1))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .inkGlassCapsule()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .inkGlass(cornerRadius: 0)
            .ignoresSafeArea(edges: .top)

            Spacer()

            InkGlassGroup(spacing: 14) {
                HStack(spacing: 14) {
                    chromeIconButton("chevron.left.2", disabled: chapterIndex <= 0) {
                        goChapter(chapterIndex - 1)
                    }
                    chromeIconButton("list.bullet") { showTOC = true }
                    chromeIconButton(isBookmarked ? "bookmark.fill" : "bookmark") {
                        toggleBookmark()
                    }
                    chromeIconButton(speech.isSpeaking ? "stop.fill" : "speaker.wave.2.fill") {
                        if speech.isSpeaking {
                            speech.stop()
                        } else {
                            prefs.autoReadEnabled = false
                            speech.speak(chapterText)
                        }
                    }
                    chromeIconButton(
                        prefs.autoReadEnabled ? "forward.fill" : "forward",
                        tint: prefs.autoReadEnabled ? InkShelfColors.lamp : nil
                    ) {
                        prefs.autoReadEnabled.toggle()
                    }
                    chromeIconButton("textformat.size") { showPrefs = true }
                    chromeIconButton("chevron.right.2", disabled: chapterIndex >= chapters.count - 1) {
                        goChapter(chapterIndex + 1)
                    }
                }
                .font(.title3)
                .foregroundStyle(palette.fg)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .inkGlass(cornerRadius: 24, tint: InkShelfColors.lamp.opacity(0.12))
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
    }

    private func chromeIconButton(
        _ systemName: String,
        disabled: Bool = false,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundStyle(tint ?? palette.fg)
                .frame(width: 36, height: 36)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
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
                                Text(ch.title)
                                    .foregroundStyle(palette.fg)
                                Spacer()
                                if ch.index == chapterIndex {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(InkShelfColors.lamp)
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
                                    Text("第 \(bm.chapterIndex + 1) 章")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
            if book.isRemote {
                chapterText = try await SourceRepository.loadRemoteChapterText(
                    book: book,
                    chapterIndex: chapterIndex,
                    context: context
                )
            } else {
                chapterText = try LibraryService.loadChapterText(book: book, chapterIndex: chapterIndex)
            }
            if chapterText.isEmpty && book.isRemote {
                errorMessage = "章节内容为空"
            }
            rebuildPages(size: contentSize)
            if resetPage { pageIndex = 0 }
            saveProgress()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rebuildPages(size: CGSize) {
        guard size.width > 20, size.height > 40 else {
            pages = [chapterText]
            return
        }
        let font = UIFont.systemFont(ofSize: prefs.fontSize)
        pages = PagePaginator.paginate(
            text: chapterText,
            size: size,
            font: font,
            lineHeightMultiple: prefs.lineHeight
        )
        pageIndex = min(pageIndex, max(pages.count - 1, 0))
    }

    private func goChapter(_ index: Int) {
        guard index >= 0, index < chapters.count, index != chapterIndex else { return }
        speech.stop()
        chapterIndex = index
        Task { await loadChapter(resetPage: true) }
    }

    private func nextPageOrChapter() {
        if pageIndex < pages.count - 1 {
            pageIndex += 1
        } else {
            goChapter(chapterIndex + 1)
        }
    }

    private func prevPageOrChapter() {
        if pageIndex > 0 {
            pageIndex -= 1
        } else {
            goChapter(chapterIndex - 1)
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
