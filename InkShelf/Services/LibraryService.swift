import Foundation
import SwiftData
import UniformTypeIdentifiers

@MainActor
enum LibraryService {
    static func importTxt(
        data: Data,
        displayName: String,
        context: ModelContext
    ) throws -> BookEntity {
        let text = NovelTextDecoder.decode(data)
        let bookId = UUID().uuidString
        try BookFileStore.writeContent(bookId: bookId, text: text)
        let ranges = ChapterSplitter.split(text)
        let book = BookEntity(
            id: bookId,
            title: cleanTitle(displayName),
            origin: .local,
            contentRelativePath: BookFileStore.relativeContentPath(bookId: bookId),
            chapterCount: ranges.count
        )
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
        context.insert(book)
        try context.save()
        return book
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

    static func repairEncodingIfNeeded(book: BookEntity, context: ModelContext) throws {
        guard !book.isRemote else { return }
        let text = try BookFileStore.readContent(bookId: book.id)
        guard let repaired = NovelTextDecoder.repairIfMojibake(text) else { return }
        try BookFileStore.writeContent(bookId: book.id, text: repaired)
        let ranges = ChapterSplitter.split(repaired)
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

    private static func cleanTitle(_ name: String) -> String {
        var t = name
        if t.lowercased().hasSuffix(".txt") {
            t = String(t.dropLast(4))
        }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "未命名" : t
    }
}
