import Foundation

enum BookFileStore {
    static var rootURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let root = docs.appendingPathComponent("inkshelf/books", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func bookDirectory(bookId: String) -> URL {
        let dir = rootURL.appendingPathComponent(bookId, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func contentURL(bookId: String) -> URL {
        bookDirectory(bookId: bookId).appendingPathComponent("content.txt")
    }

    static func chaptersDirectory(bookId: String) -> URL {
        let dir = bookDirectory(bookId: bookId).appendingPathComponent("chapters", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func chapterURL(bookId: String, index: Int) -> URL {
        chaptersDirectory(bookId: bookId).appendingPathComponent("\(index).txt")
    }

    static func cacheURL(bookId: String, chapterIndex: Int) -> URL {
        let cache = bookDirectory(bookId: bookId).appendingPathComponent("cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        return cache.appendingPathComponent("\(chapterIndex).txt")
    }

    static func writeContent(bookId: String, text: String) throws {
        let url = contentURL(bookId: bookId)
        try text.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    static func writeContentData(bookId: String, data: Data) throws {
        try data.write(to: contentURL(bookId: bookId), options: .atomic)
    }

    static func readContent(bookId: String) throws -> String {
        let data = try Data(contentsOf: contentURL(bookId: bookId))
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func readContentSlice(bookId: String, start: Int, length: Int) throws -> String {
        let full = try readContent(bookId: bookId)
        let ns = full as NSString
        let safeStart = min(max(start, 0), ns.length)
        let safeLen = min(max(length, 0), ns.length - safeStart)
        guard safeLen > 0 else { return "" }
        return ns.substring(with: NSRange(location: safeStart, length: safeLen))
    }

    static func writeChapter(bookId: String, index: Int, text: String) throws {
        try text.data(using: .utf8)?.write(to: chapterURL(bookId: bookId, index: index), options: .atomic)
    }

    static func readChapter(bookId: String, index: Int) -> String? {
        let url = chapterURL(bookId: bookId, index: index)
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    static func writeChapters(bookId: String, text: String, ranges: [ChapterRange]) throws {
        let ns = text as NSString
        for (i, range) in ranges.enumerated() {
            let start = min(max(range.start, 0), ns.length)
            let end = min(max(range.end, start), ns.length)
            let slice = ns.substring(with: NSRange(location: start, length: end - start))
            try writeChapter(bookId: bookId, index: i, text: slice)
        }
    }

    static func writeCache(bookId: String, chapterIndex: Int, text: String) throws {
        try text.data(using: .utf8)?.write(to: cacheURL(bookId: bookId, chapterIndex: chapterIndex), options: .atomic)
    }

    static func readCache(bookId: String, chapterIndex: Int) -> String? {
        let url = cacheURL(bookId: bookId, chapterIndex: chapterIndex)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clearCache(bookId: String) {
        let cache = bookDirectory(bookId: bookId).appendingPathComponent("cache", isDirectory: true)
        try? FileManager.default.removeItem(at: cache)
    }

    static func deleteBook(bookId: String) {
        try? FileManager.default.removeItem(at: bookDirectory(bookId: bookId))
    }

    static func relativeContentPath(bookId: String) -> String {
        "inkshelf/books/\(bookId)/content.txt"
    }
}
