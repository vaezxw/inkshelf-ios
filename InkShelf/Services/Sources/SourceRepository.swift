import Foundation
import SwiftData

@MainActor
enum SourceRepository {
    static func parseImportPayload(_ text: String) async throws -> [[String: Any]] {
        var payload = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if looksLikeURL(payload) {
            payload = try await fetchRemote(payload)
        }
        if payload.hasPrefix("\u{FEFF}") {
            payload = String(payload.dropFirst())
        }
        if PlistSourceConverter.looksLikePlist(payload) {
            return try PlistSourceConverter.convert(payload)
        }
        guard let data = payload.data(using: .utf8) else {
            throw SourceError.format("书源内容无效")
        }
        let obj = try JSONSerialization.jsonObject(with: data)
        if let list = obj as? [Any] {
            return list.compactMap { $0 as? [String: Any] }
        }
        if let map = obj as? [String: Any] {
            return [map]
        }
        throw SourceError.format("书源 JSON 格式无效")
    }

    static func importSources(_ text: String, context: ModelContext) async throws -> Int {
        let items = try await parseImportPayload(text)
        guard !items.isEmpty else { throw SourceError.format("未解析到书源") }
        let existing = try context.fetch(FetchDescriptor<BookSourceEntity>())
        var byURL: [String: BookSourceEntity] = [:]
        for item in existing {
            byURL[item.sourceUrl] = item
        }
        var count = 0
        for item in items {
            let name = (item["bookSourceName"] as? String)?.trimmingCharacters(in: .whitespaces)
            let url = (item["bookSourceUrl"] as? String) ?? ""
            let rawData = try JSONSerialization.data(withJSONObject: item)
            let raw = String(data: rawData, encoding: .utf8) ?? "{}"
            let display = (name?.isEmpty == false) ? name! : "未命名书源"
            if let old = byURL[url] {
                old.name = display
                old.legadoRaw = raw
                old.groupName = item["bookSourceGroup"] as? String
            } else {
                let entity = BookSourceEntity(
                    name: display,
                    sourceUrl: url,
                    enabled: (item["enabled"] as? Bool) ?? true,
                    legadoRaw: raw,
                    groupName: item["bookSourceGroup"] as? String
                )
                context.insert(entity)
                byURL[url] = entity
            }
            count += 1
        }
        try context.save()
        return count
    }

    static func exportJSON(context: ModelContext) throws -> String {
        let sources = try context.fetch(FetchDescriptor<BookSourceEntity>(sortBy: [SortDescriptor(\.name)]))
        guard !sources.isEmpty else { throw SourceError.format("没有可导出的书源") }
        let list: [Any] = sources.compactMap { src in
            guard let data = src.legadoRaw.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
            return obj
        }
        let data = try JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    static func clearAll(context: ModelContext) throws {
        let sources = try context.fetch(FetchDescriptor<BookSourceEntity>())
        for s in sources { context.delete(s) }
        try context.save()
    }

    static func rawMap(from entity: BookSourceEntity) -> [String: Any]? {
        guard let data = entity.legadoRaw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    static func addRemoteBook(
        hit: SearchBookHit,
        source: BookSourceEntity,
        context: ModelContext
    ) async throws -> BookEntity {
        guard let raw = rawMap(from: source) else { throw SourceError.format("书源数据损坏") }
        let chapters = try await SourceEngine.fetchToc(rawSource: raw, bookUrl: hit.bookUrl)
        guard !chapters.isEmpty else { throw SourceError.network("目录为空") }
        let bookId = UUID().uuidString
        try BookFileStore.writeContent(bookId: bookId, text: "")
        let book = BookEntity(
            id: bookId,
            title: hit.name,
            author: hit.author,
            origin: .remote,
            sourceId: source.id,
            sourceName: source.name,
            bookUrl: hit.bookUrl,
            coverUrl: hit.coverUrl,
            intro: hit.intro,
            contentRelativePath: BookFileStore.relativeContentPath(bookId: bookId),
            chapterCount: chapters.count
        )
        for (i, ch) in chapters.enumerated() {
            let entity = ChapterEntity(index: i, title: ch.title, remoteUrl: ch.url, book: book)
            book.chapters.append(entity)
            context.insert(entity)
        }
        context.insert(book)
        try context.save()
        return book
    }

    static func refreshToc(book: BookEntity, context: ModelContext) async throws {
        guard book.isRemote,
              let sourceId = book.sourceId,
              let bookUrl = book.bookUrl else { return }
        let sources = try context.fetch(FetchDescriptor<BookSourceEntity>())
        guard let source = sources.first(where: { $0.id == sourceId }),
              let raw = rawMap(from: source) else {
            throw SourceError.format("找不到原书源")
        }
        let chapters = try await SourceEngine.fetchToc(rawSource: raw, bookUrl: bookUrl)
        for ch in book.chapters { context.delete(ch) }
        book.chapters.removeAll()
        for (i, ch) in chapters.enumerated() {
            let entity = ChapterEntity(index: i, title: ch.title, remoteUrl: ch.url, book: book)
            book.chapters.append(entity)
            context.insert(entity)
        }
        book.chapterCount = chapters.count
        book.lastChapterIndex = min(book.lastChapterIndex, max(chapters.count - 1, 0))
        BookFileStore.clearCache(bookId: book.id)
        try context.save()
    }

    static func loadRemoteChapterText(
        book: BookEntity,
        chapterIndex: Int,
        context: ModelContext
    ) async throws -> String {
        if let cached = BookFileStore.readCache(bookId: book.id, chapterIndex: chapterIndex), !cached.isEmpty {
            return cached
        }
        let chapters = book.chapters.sorted { $0.index < $1.index }
        guard chapterIndex >= 0, chapterIndex < chapters.count,
              let url = chapters[chapterIndex].remoteUrl,
              let sourceId = book.sourceId else {
            throw SourceError.network("章节地址无效")
        }
        let sources = try context.fetch(FetchDescriptor<BookSourceEntity>())
        guard let source = sources.first(where: { $0.id == sourceId }),
              let raw = rawMap(from: source) else {
            throw SourceError.format("找不到原书源")
        }
        let text = try await SourceEngine.fetchContent(rawSource: raw, chapterUrl: url)
        try BookFileStore.writeCache(bookId: book.id, chapterIndex: chapterIndex, text: text)
        return text
    }

    private static func looksLikeURL(_ text: String) -> Bool {
        if text.contains("\n") || text.contains("{") || text.contains("[") { return false }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    private static func toRawURL(_ url: String) -> String {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.contains("gitee.com/"), u.contains("/blob/") {
            u = u.replacingOccurrences(of: "/blob/", with: "/raw/")
        }
        if let m = u.range(of: #"^https?://gitee\.com/([^/]+)/([^/]+)/raw/(.+)$"#, options: .regularExpression) {
            let path = String(u[m])
            // Prefer raw.giteeusercontent.com when possible — keep gitee raw if rewrite complex
            _ = path
        }
        if u.contains("github.com/"), u.contains("/blob/") {
            u = u
                .replacingOccurrences(of: "https://github.com/", with: "https://raw.githubusercontent.com/")
                .replacingOccurrences(of: "http://github.com/", with: "https://raw.githubusercontent.com/")
                .replacingOccurrences(of: "/blob/", with: "/")
        }
        return u
    }

    private static func fetchRemote(_ url: String) async throws -> String {
        let raw = toRawURL(url)
        guard let requestURL = URL(string: raw) else { throw SourceError.network("无效链接") }
        var req = URLRequest(url: requestURL)
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw SourceError.network("HTTP \(http.statusCode)")
        }
        let body = (String(data: data, encoding: .utf8) ?? NovelTextDecoder.decode(data))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { throw SourceError.format("远程书源内容为空") }
        if body.hasPrefix("<!") && !body.contains("<plist") {
            throw SourceError.format("拿到的是网页而不是书源文件")
        }
        return body
    }
}
