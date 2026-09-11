import XCTest
import UIKit
import ZIPFoundation
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

    func testXPathConvertsCommonServerListRules() {
        XCTAssertEqual(
            PlistSourceConverter.xpathToLegadoRule(".//div[@id='content']/table//tr[position()>1]"),
            "#content table tr:nth-child(n+2)"
        )
        XCTAssertEqual(
            PlistSourceConverter.xpathToLegadoRule(".//td[1]/a[2]/@href"),
            "td:nth-of-type(1) a:nth-of-type(2)@href"
        )
        XCTAssertEqual(
            PlistSourceConverter.xpathToLegadoRule(".//div[@id='text_c']"),
            "#text_c"
        )
    }

    func testServerListPlistConvertsSearchableSource() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>serverList</key>
            <array>
                <dict>
                    <key>serverName</key>
                    <string>单元测试源</string>
                    <key>serverHostURL</key>
                    <string>http://www.example.com</string>
                    <key>serverIsEndble</key>
                    <true/>
                    <key>detailBook</key>
                    <dict>
                        <key>mulu_list</key>
                        <string>.//div[@class='chapter_list']</string>
                        <key>mulu_title</key>
                        <string>.//a</string>
                        <key>mulu_url</key>
                        <string>.//a/@href</string>
                    </dict>
                    <key>readBook</key>
                    <dict>
                        <key>chapterContent</key>
                        <string>.//div[@id='text_c']</string>
                    </dict>
                    <key>searchBook</key>
                    <dict>
                        <key>searchFirstPageUrl</key>
                        <string>http://www.example.com/search.php?searchkey=@@@</string>
                        <key>searchPageRequestType</key>
                        <string>0</string>
                        <key>search_listDivision</key>
                        <string>.//div[@id='content']//tr[position()&gt;1]</string>
                        <key>search_parser</key>
                        <dict>
                            <key>search_bookname</key>
                            <string>.//td[1]/a</string>
                            <key>search_author</key>
                            <string>.//td[3]</string>
                            <key>search_detailUrl</key>
                            <string>.//td[1]/a/@href</string>
                        </dict>
                    </dict>
                </dict>
            </array>
        </dict>
        </plist>
        """
        let items = try PlistSourceConverter.convert(plist)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0]["bookSourceName"] as? String, "单元测试源")
        XCTAssertEqual(items[0]["searchUrl"] as? String, "http://www.example.com/search.php?searchkey={{key}}")
        let search = try XCTUnwrap(items[0]["ruleSearch"] as? [String: String])
        XCTAssertEqual(search["bookList"], "#content tr:nth-child(n+2)")
        XCTAssertEqual(search["name"], "td:nth-of-type(1) a")
        let toc = try XCTUnwrap(items[0]["ruleToc"] as? [String: String])
        XCTAssertEqual(toc["chapterList"], "div.chapter_list")
        let content = try XCTUnwrap(items[0]["ruleContent"] as? [String: String])
        XCTAssertEqual(content["content"], "#text_c@html")
    }

    func testZipArchiveExtractsPlist() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
            <key>name</key><string>压缩包源</string>
            <key>url</key><string>http://zip.example.com</string>
            <key>search</key>
            <dict>
                <key>url</key><string>http://zip.example.com/s?q={key}</string>
                <key>list</key><string>//div</string>
                <key>title</key><string>.//a</string>
                <key>link</key><string>.//a/@href</string>
            </dict>
        </dict>
        </plist>
        """
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("inkshelf-zip-test-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let plistURL = dir.appendingPathComponent("booksource.plist")
        try Data(plist.utf8).write(to: plistURL)
        let zipURL = dir.appendingPathComponent("booksource.zip")
        try fm.zipItem(at: plistURL, to: zipURL)
        let zipData = try Data(contentsOf: zipURL)
        XCTAssertTrue(SourceArchive.isZip(zipData))
        let texts = try SourceArchive.extractTexts(zipData)
        XCTAssertEqual(texts.count, 1)
        let items = try PlistSourceConverter.convert(texts[0])
        XCTAssertEqual(items.first?["bookSourceName"] as? String, "压缩包源")
    }
}
