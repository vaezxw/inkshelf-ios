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

    static func cacheURL(bookId: String, chapterIndex: Int) -> URL {
        let cache = bookDirectory(bookId: bookId).appendingPathComponent("cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        return cache.appendingPathComponent("\(chapterIndex).txt")
    }

    static func writeContent(bookId: String, text: String) throws {
        let url = contentURL(bookId: bookId)
        try text.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    static func readContent(bookId: String) throws -> String {
        let data = try Data(contentsOf: contentURL(bookId: bookId))
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func readContentSlice(bookId: String, start: Int, length: Int) throws -> String {
        let full = try readContent(bookId: bookId)
        guard start >= 0, length >= 0, start <= full.count else { return "" }
        let s = full.index(full.startIndex, offsetBy: start)
        let e = full.index(s, offsetBy: min(length, full.count - start))
        return String(full[s..<e])
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
