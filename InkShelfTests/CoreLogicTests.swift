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
        let decoded = NovelTextDecoder.decode(utf8)
        XCTAssertTrue(decoded.contains("你好"))
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

    func testUnsupportedJsSearchUrl() {
        XCTAssertTrue(SourceEngine.isUnsupportedSearchUrl("<js>foo</js>"))
        XCTAssertFalse(SourceEngine.isUnsupportedSearchUrl("https://example.com/search?q={{key}}"))
    }
}
