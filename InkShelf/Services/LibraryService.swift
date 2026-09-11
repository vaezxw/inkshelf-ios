import Foundation
import SwiftData

@MainActor
enum LibraryService {
    static func commitLocalImport(_ prepared: PreparedLocalBook, context: ModelContext) throws -> BookEntity {
        let book = BookEntity(
            id: prepared.bookId,
            title: prepared.title,
            origin: .local,
            contentRelativePath: prepared.contentRelativePath,
            chapterCount: prepared.chapters.count
        )
        let batchSize = 50
        for (offset, item) in prepared.chapters.enumerated() {
            let chapter = ChapterEntity(
                index: item.index,
                title: item.title,
                startOffset: item.startOffset,
                length: item.length,
                book: book
            )
            book.chapters.append(chapter)
            context.insert(chapter)
            if offset > 0, offset % batchSize == 0 {
                try context.save()
            }
        }
        context.insert(book)
        try context.save()
        return book
    }

    static func importTxt(
        data: Data,
        displayName: String,
        context: ModelContext,
        onProgress: (@MainActor (ImportProgress) -> Void)? = nil
    ) async throws -> BookEntity {
        let pipeline = ImportPipeline()
        let prepared = try await pipeline.prepare(data: data, displayName: displayName) { progress in
            Task { @MainActor in
                onProgress?(progress)
            }
        }
        onProgress?(ImportProgress(stage: .saving, fraction: 0.95))
        let book = try commitLocalImport(prepared, context: context)
        onProgress?(ImportProgress(stage: .done, fraction: 1))
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

    /// Prefer chapter file; fall back to content slice and backfill chapter file.
    nonisolated static func loadLocalChapterText(bookId: String, chapterIndex: Int, start: Int, length: Int) throws -> String {
        if let cached = BookFileStore.readChapter(bookId: bookId, index: chapterIndex), !cached.isEmpty {
            return cached
        }
        let slice = try BookFileStore.readContentSlice(bookId: bookId, start: start, length: length)
        if !slice.isEmpty {
            try? BookFileStore.writeChapter(bookId: bookId, index: chapterIndex, text: slice)
        }
        return slice
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

        return try loadLocalChapterText(
            bookId: book.id,
            chapterIndex: chapterIndex,
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
            let decoded = NovelTextDecoder.decodeDetailed(Data(repaired.utf8))
            try BookFileStore.writeContentData(bookId: bookId, data: decoded.utf8Data)
            let ranges = ChapterSplitter.split(decoded.text)
            try BookFileStore.writeChapters(bookId: bookId, text: decoded.text, ranges: ranges)
            return ranges
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
}
