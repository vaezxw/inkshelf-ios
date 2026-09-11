import Foundation
import SwiftData
import UniformTypeIdentifiers

struct PreparedLocalBook: Sendable {
    var bookId: String
    var title: String
    var contentRelativePath: String
    var chapters: [PreparedChapter]
}

struct PreparedChapter: Sendable {
    var index: Int
    var title: String
    var startOffset: Int
    var length: Int
}

@MainActor
enum LibraryService {
    /// Heavy decode / split / disk write — call off the main actor.
    nonisolated static func prepareLocalImport(data: Data, displayName: String) throws -> PreparedLocalBook {
        let text = NovelTextDecoder.decode(data)
        let bookId = UUID().uuidString
        try BookFileStore.writeContent(bookId: bookId, text: text)
        let ranges = ChapterSplitter.split(text)
        let chapters = ranges.enumerated().map { i, range in
            PreparedChapter(
                index: i,
                title: range.title,
                startOffset: range.start,
                length: range.length
            )
        }
        return PreparedLocalBook(
            bookId: bookId,
            title: cleanTitle(displayName),
            contentRelativePath: BookFileStore.relativeContentPath(bookId: bookId),
            chapters: chapters
        )
    }

    static func commitLocalImport(_ prepared: PreparedLocalBook, context: ModelContext) throws -> BookEntity {
        let book = BookEntity(
            id: prepared.bookId,
            title: prepared.title,
            origin: .local,
            contentRelativePath: prepared.contentRelativePath,
            chapterCount: prepared.chapters.count
        )
        for item in prepared.chapters {
            let chapter = ChapterEntity(
                index: item.index,
                title: item.title,
                startOffset: item.startOffset,
                length: item.length,
                book: book
            )
            book.chapters.append(chapter)
            context.insert(chapter)
        }
        context.insert(book)
        try context.save()
        return book
    }

    static func importTxt(
        data: Data,
        displayName: String,
        context: ModelContext
    ) async throws -> BookEntity {
        let prepared = try await Task.detached(priority: .userInitiated) {
            try prepareLocalImport(data: data, displayName: displayName)
        }.value
        return try commitLocalImport(prepared, context: context)
    }

    static func deleteBook(_ book: BookEntity, context: ModelContext) throws {
        let id = book.id
        context.delete(book)
        try context.save()
        BookFileStore.deleteBook(bookId: id)
    }

    static func updateProgress(
        book: BookEntity,
        chapterIndex: Int,
        scrollOffset: Double,
        context: ModelContext
    ) throws {
        book.lastChapterIndex = chapterIndex
        book.lastScrollOffset = scrollOffset
        book.lastReadAt = .now
        try context.save()
    }

    static func loadChapterText(book: BookEntity, chapterIndex: Int) throws -> String {
        let chapters = book.chapters.sorted { $0.index < $1.index }
        guard chapterIndex >= 0, chapterIndex < chapters.count else { return "" }
        let chapter = chapters[chapterIndex]

        if book.isRemote {
            if let cached = BookFileStore.readCache(bookId: book.id, chapterIndex: chapterIndex),
               !cached.isEmpty {
                return cached
            }
            return ""
        }

        return try BookFileStore.readContentSlice(
            bookId: book.id,
            start: chapter.startOffset,
            length: chapter.length
        )
    }

    static func repairEncodingIfNeeded(book: BookEntity, context: ModelContext) async throws {
        guard !book.isRemote else { return }
        let bookId = book.id
        let text = try BookFileStore.readContent(bookId: bookId)
        guard let repaired = NovelTextDecoder.repairIfMojibake(text) else { return }
        let ranges = try await Task.detached(priority: .utility) {
            try BookFileStore.writeContent(bookId: bookId, text: repaired)
            return ChapterSplitter.split(repaired)
        }.value
        for ch in book.chapters {
            context.delete(ch)
        }
        book.chapters.removeAll()
        for (i, range) in ranges.enumerated() {
            let chapter = ChapterEntity(
                index: i,
                title: range.title,
                startOffset: range.start,
                length: range.length,
                book: book
            )
            book.chapters.append(chapter)
            context.insert(chapter)
        }
        book.chapterCount = ranges.count
        book.lastChapterIndex = min(book.lastChapterIndex, max(ranges.count - 1, 0))
        try context.save()
    }

    static func toggleBookmark(
        book: BookEntity,
        chapterIndex: Int,
        title: String,
        scrollOffset: Double,
        context: ModelContext
    ) throws -> Bool {
        if let existing = book.bookmarks.first(where: { $0.chapterIndex == chapterIndex }) {
            context.delete(existing)
            try context.save()
            return false
        }
        let mark = BookmarkEntity(
            chapterIndex: chapterIndex,
            title: title,
            scrollOffset: scrollOffset,
            book: book
        )
        book.bookmarks.append(mark)
        context.insert(mark)
        try context.save()
        return true
    }

    nonisolated private static func cleanTitle(_ name: String) -> String {
        var t = name
        if t.lowercased().hasSuffix(".txt") {
            t = String(t.dropLast(4))
        }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "未命名" : t
    }
}
