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
    @State private var addingId: String?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("搜索").tag(0)
                    Text("管理").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    Color.clear
                }

                if tab == 0 {
                    searchPane
                } else {
                    managePane
                }
            }
            .inkShelfScreenBackground()
            .navigationTitle("书源")
            .navigationDestination(for: String.self) { bookId in
                ReaderView(bookID: bookId)
            }
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
                ImportSourceSheet(text: $importText) { text in
                    Task { await importSources(text) }
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
        }
    }

    private var searchPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("书名 / 作者关键词", text: $keyword)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .inkGlass(cornerRadius: 14)
                    .onSubmit { Task { await runSearch() } }
                Button {
                    Task { await runSearch() }
                } label: {
                    if searching {
                        ProgressView()
                    } else {
                        Text("搜索")
                    }
                }
                .disabled(searching || keyword.trimmingCharacters(in: .whitespaces).isEmpty)
                .tint(InkShelfColors.lamp)
                .inkGlassProminentButton()
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text(hit.name).font(.headline)
                        HStack {
                            if let author = hit.author {
                                Text(author).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(hit.sourceName)
                                .font(.caption)
                                .foregroundStyle(InkShelfColors.lamp)
                        }
                        if let intro = hit.intro, !intro.isEmpty {
                            Text(intro).font(.caption).lineLimit(2).foregroundStyle(.secondary)
                        }
                        Button {
                            Task { await addHit(hit) }
                        } label: {
                            if addingId == hit.id {
                                ProgressView()
                            } else {
                                Text("加入书架")
                            }
                        }
                        .inkGlassButton()
                        .disabled(addingId != nil)
                    }
                    .padding(.vertical, 4)
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
                                try? context.save()
                            }
                        ))
                        .labelsHidden()
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            context.delete(src)
                            try? context.save()
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
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
        defer { searching = false }

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
            let batch = Array(jobs[start..<min(start + batchSize, jobs.count)])
            await withTaskGroup(of: [SearchBookHit].self) { group in
                for job in batch {
                    group.addTask {
                        guard let data = job.legadoRaw.data(using: .utf8),
                              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            return []
                        }
                        if SourceEngine.isUnsupportedSearchUrl(raw["searchUrl"] as? String) { return [] }
                        do {
                            return try await SourceEngine.search(
                                rawSource: raw,
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
                    collected.append(contentsOf: part)
                }
            }
            done += batch.count
            progressText = "已搜 \(done)/\(jobs.count) · 命中 \(collected.count)"
            hits = collected
        }
        progressText = collected.isEmpty ? "无结果（部分书源含 JS 已跳过）" : "完成 · \(collected.count) 条"
    }

    private func addHit(_ hit: SearchBookHit) async {
        guard let source = sources.first(where: { $0.id == hit.sourceId }) else { return }
        addingId = hit.id
        defer { addingId = nil }
        do {
            let book = try await SourceRepository.addRemoteBook(hit: hit, source: source, context: context)
            flash("已加入「\(book.title)」")
            path.append(book.id)
        } catch {
            flash("加入失败：\(error.localizedDescription)")
        }
    }

    private func importSources(_ text: String) async {
        do {
            let n = try await SourceRepository.importSources(text, context: context)
            flash("已导入 \(n) 个书源")
            showImportSheet = false
            importText = ""
            tab = 1
        } catch {
            flash(error.localizedDescription)
        }
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
    var onImport: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("粘贴 Legado JSON、plist 全文，或填写可直链下载的 URL。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .padding(8)
                    .inkGlass(cornerRadius: 14)
            }
            .padding()
            .inkShelfScreenBackground()
            .navigationTitle("导入书源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        onImport(text)
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
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
