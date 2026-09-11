import XCTest
import UIKit
@testable import InkShelf

final class CoreLogicTests: XCTestCase {
    func testChapterSplitterFindsHeadings() {
        let text = """
        前言内容略

        第一章 起源
        很久以前有一座山。

        第二章 出海
        他们离开了港口。
        """
        let parts = ChapterSplitter.split(text)
        XCTAssertGreaterThanOrEqual(parts.count, 2)
        XCTAssertTrue(parts.contains(where: { $0.title.contains("第一") }))
    }

    func testDecoderPrefersChinese() {
        let utf8 = "你好世界，这是一段中文小说正文。".data(using: .utf8)!
        let decoded = NovelTextDecoder.decodeDetailed(utf8)
        XCTAssertTrue(decoded.text.contains("你好"))
        XCTAssertFalse(decoded.utf8Data.isEmpty)
        XCTAssertTrue(decoded.encodingName.contains("utf8"))
    }

    func testChapterSplitterFallbackChunksHugeText() {
        let paragraph = String(repeating: "这是一段没有章节标题的长文。", count: 80)
        let text = Array(repeating: paragraph, count: 20).joined(separator: "\n")
        let parts = ChapterSplitter.split(text)
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertEqual(parts.first?.start, 0)
        XCTAssertEqual(parts.last?.end, (text as NSString).length)
    }

    func testPaginatorSplitsLongText() {
        let text = String(repeating: "这是一段用于分页测试的中文句子。\n", count: 80)
        let pages = PagePaginator.paginate(
            text: text,
            size: CGSize(width: 300, height: 400),
            font: .systemFont(ofSize: 18),
            lineHeightMultiple: 1.6
        )
        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertFalse(pages.contains(where: \.isEmpty))
    }

    func testPaginatorRangesCoverFullText() {
        let text = String(repeating: "分页范围覆盖全文。", count: 40)
        let ranges = PagePaginator.paginateRanges(
            text: text,
            size: CGSize(width: 280, height: 360),
            font: .systemFont(ofSize: 17),
            lineHeightMultiple: 1.5
        )
        XCTAssertFalse(ranges.isEmpty)
        XCTAssertEqual(ranges.first?.location, 0)
        let covered = ranges.reduce(0) { $0 + $1.length }
        XCTAssertEqual(covered, (text as NSString).length)
    }

    func testBookFileStoreChapterRoundTrip() throws {
        let bookId = "test-\(UUID().uuidString)"
        defer { BookFileStore.deleteBook(bookId: bookId) }
        let text = "第一章\n内容甲\n\n第二章\n内容乙"
        let ranges = ChapterSplitter.split(text)
        try BookFileStore.writeContent(bookId: bookId, text: text)
        try BookFileStore.writeChapters(bookId: bookId, text: text, ranges: ranges)
        let first = try XCTUnwrap(BookFileStore.readChapter(bookId: bookId, index: 0))
        XCTAssertFalse(first.isEmpty)
    }

    func testImportPipelinePreparesChapters() async throws {
        let text = """
        第一章 测试
        正文一。

        第二章 继续
        正文二。
        """
        let data = Data(text.utf8)
        let pipeline = ImportPipeline()
        let prepared = try await pipeline.prepare(data: data, displayName: "单元测试.txt")
        XCTAssertEqual(prepared.title, "单元测试")
        XCTAssertGreaterThanOrEqual(prepared.chapters.count, 2)
        let first = BookFileStore.readChapter(bookId: prepared.bookId, index: 0)
        XCTAssertNotNil(first)
        BookFileStore.deleteBook(bookId: prepared.bookId)
    }

    func testUnsupportedJsSearchUrl() {
        XCTAssertTrue(SourceEngine.isUnsupportedSearchUrl("<js>foo</js>"))
        XCTAssertFalse(SourceEngine.isUnsupportedSearchUrl("https://example.com/search?q={{key}}"))
    }
}
