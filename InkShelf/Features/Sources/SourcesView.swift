import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SourcesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BookSourceEntity.name) private var sources: [BookSourceEntity]

    @State private var tab = 0
    @State private var keyword = ""
    @State private var searching = false
    @State private var progressText = ""
    @State private var hits: [SearchBookHit] = []
    @State private var toast: String?
    @State private var showImportSheet = false
    @State private var importText = ""
    @State private var showClearConfirm = false
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var searchTask: Task<Void, Never>?
    @State private var previewHit: SearchBookHit?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("搜索").tag(0)
                    Text("管理").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if tab == 0 {
                    searchPane
                } else {
                    managePane
                }
            }
            .inkShelfScreenBackground()
            .navigationTitle("书源")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("粘贴 / 输入书源") { showImportSheet = true }
                        Button("导出书源 JSON") { exportSources() }
                        Divider()
                        Button("清空全部书源", role: .destructive) { showClearConfirm = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showImportSheet) {
                ImportSourceSheet(text: $importText) { payload in
                    let n: Int
                    switch payload {
                    case .text(let text):
                        n = try await SourceRepository.importSources(text, context: context)
                    case .data(let data):
                        n = try await SourceRepository.importSources(data: data, context: context)
                    }
                    flash("已导入 \(n) 个书源")
                    importText = ""
                    tab = 1
                    return n
                }
            }
            .sheet(item: $previewHit) { hit in
                if let source = sources.first(where: { $0.id == hit.sourceId }) {
                    SearchBookPreviewView(hit: hit, source: source) { book in
                        flash("已加入「\(book.title)」")
                    }
                } else {
                    NavigationStack {
                        ContentUnavailableView("书源不存在", systemImage: "exclamationmark.triangle")
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("关闭") { previewHit = nil }
                                }
                            }
                    }
                }
            }
            .confirmationDialog("清空全部书源？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    do {
                        try SourceRepository.clearAll(context: context)
                        flash("已清空书源")
                    } catch {
                        flash(error.localizedDescription)
                    }
                }
            }
            .sheet(isPresented: $showShare) {
                if let exportURL {
                    ShareSheet(items: [exportURL])
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    GlassToast(message: toast)
                        .padding(.bottom, 12)
                }
            }
            .onDisappear {
                searchTask?.cancel()
            }
        }
    }

    private var searchPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("书名 / 作者关键词", text: $keyword)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .inkGlass(cornerRadius: 14)
                    .disabled(searching)
                    .onSubmit { startSearch() }

                if searching {
                    Button("取消") { cancelSearch() }
                        .tint(InkShelfColors.lamp)
                        .inkGlassProminentButton()
                } else {
                    Button("搜索") { startSearch() }
                        .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty)
                        .tint(InkShelfColors.lamp)
                        .inkGlassProminentButton()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if !progressText.isEmpty {
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(InkShelfColors.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            List {
                ForEach(hits) { hit in
                    Button {
                        previewHit = hit
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(hit.name)
                                .font(.headline)
                                .foregroundStyle(InkShelfColors.ink)
                            HStack {
                                if let author = hit.author {
                                    Text(author)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(hit.sourceName)
                                    .font(.caption)
                                    .foregroundStyle(InkShelfColors.lamp)
                            }
                            if let intro = hit.intro, !intro.isEmpty {
                                Text(intro)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .foregroundStyle(.secondary)
                            }
                            Text("点击预览详情")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(InkShelfColors.lamp)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var managePane: some View {
        List {
            if sources.isEmpty {
                ContentUnavailableView("还没有书源", systemImage: "globe", description: Text("点右上角 + 导入 Legado JSON 或 plist。"))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(sources, id: \.id) { src in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(src.name)
                            Text(src.sourceUrl)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { src.enabled },
                            set: { v in
                                src.enabled = v
                                src.touch()
                                try? context.save()
                                SyncService.shared.schedulePush(context: context)
                            }
                        ))
                        .labelsHidden()
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            context.delete(src)
                            try? context.save()
                            SyncService.shared.schedulePush(context: context)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func startSearch() {
        searchTask?.cancel()
        searchTask = Task { await runSearch() }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        searching = false
        if !hits.isEmpty {
            progressText = "已取消 · 保留 \(hits.count) 条"
        } else {
            progressText = "已取消搜索"
        }
    }

    private func runSearch() async {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        let enabled = sources.filter(\.enabled)
        guard !enabled.isEmpty else {
            flash("请先导入并启用书源")
            return
        }
        searching = true
        hits = []
        progressText = "搜索中…"
        defer {
            if !Task.isCancelled {
                searching = false
            }
        }

        struct Job: Sendable {
            let id: String
            let name: String
            let legadoRaw: String
        }
        let jobs: [Job] = enabled.map { Job(id: $0.id, name: $0.name, legadoRaw: $0.legadoRaw) }

        var collected: [SearchBookHit] = []
        let batchSize = 6
        var done = 0
        for start in stride(from: 0, to: jobs.count, by: batchSize) {
            if Task.isCancelled { break }
            let batch = Array(jobs[start..<min(start + batchSize, jobs.count)])
            await withTaskGroup(of: [SearchBookHit].self) { group in
                for job in batch {
                    group.addTask {
                        if Task.isCancelled { return [] }
                        if SourceEngine.isUnsupportedSearchJSON(job.legadoRaw) { return [] }
                        do {
                            return try await SourceEngine.search(
                                rawSourceJSON: job.legadoRaw,
                                sourceId: job.id,
                                sourceName: job.name,
                                keyword: key
                            )
                        } catch {
                            return []
                        }
                    }
                }
                for await part in group {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    collected.append(contentsOf: part)
                }
            }
            if Task.isCancelled { break }
            done += batch.count
            progressText = "已搜 \(done)/\(jobs.count) · 命中 \(collected.count)"
            hits = collected
        }

        if Task.isCancelled {
            progressText = collected.isEmpty ? "已取消搜索" : "已取消 · 保留 \(collected.count) 条"
            hits = collected
            return
        }
        progressText = collected.isEmpty ? "无结果（部分书源含 JS 已跳过）" : "完成 · \(collected.count) 条"
    }

    private func exportSources() {
        do {
            let json = try SourceRepository.exportJSON(context: context)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("inkshelf-sources.json")
            try json.data(using: .utf8)?.write(to: url, options: .atomic)
            exportURL = url
            showShare = true
        } catch {
            flash(error.localizedDescription)
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

struct ImportSourceSheet: View {
    @Binding var text: String
    var onImport: (SourceImportValue) async throws -> Int
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var errorMessage: String?
    @State private var showFileImporter = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("""
                从网址获取书源，或粘贴 JSON / plist 全文。支持：
                1. Gitee.com 以 .zip 结尾的下载地址
                2. 浏览器可直接下载的 .plist 地址
                3. 自定义 .zip 直链（如阿里云 OSS）
                大文件请用「从文件导入」，不要整份粘贴。
                """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .padding(8)
                    .inkGlass(cornerRadius: 14)
                    .disabled(importing)
                Button("清空内容") {
                    text = ""
                    errorMessage = nil
                }
                .disabled(importing || text.isEmpty)
                Button("从文件导入") { showFileImporter = true }
                    .disabled(importing)
                if importing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在解析书源…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
            .inkShelfScreenBackground()
            .navigationTitle("输入书源网络地址")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(importing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("获取书源") {
                        Task { await runImport() }
                    }
                    .disabled(importing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [
                    .xml, .text, .plainText, .json, .zip,
                    UTType(filenameExtension: "plist") ?? .xml,
                    UTType(filenameExtension: "txt") ?? .plainText,
                ],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .failure(let error):
                    errorMessage = error.localizedDescription
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await loadFile(url) }
                }
            }
        }
    }

    private func loadFile(_ url: URL) async {
        importing = true
        errorMessage = nil
        defer { importing = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: url)
            }.value
            if SourceArchive.isZip(data) || url.pathExtension.lowercased() == "zip" {
                _ = try await onImport(.data(data))
                dismiss()
                return
            }
            let decoded = String(data: data, encoding: .utf8) ?? NovelTextDecoder.decode(data)
            guard !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "文件为空"
                return
            }
            if decoded.count < 40_000 {
                text = decoded
            }
            _ = try await onImport(.text(decoded))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runImport() async {
        importing = true
        errorMessage = nil
        defer { importing = false }
        do {
            _ = try await onImport(.text(text))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
