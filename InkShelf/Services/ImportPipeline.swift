import Foundation

enum ImportStage: String, Sendable {
    case reading = "读取文件"
    case decoding = "识别编码"
    case splitting = "智能分章"
    case writing = "写入缓存"
    case saving = "保存书架"
    case done = "完成"
}

struct ImportProgress: Sendable {
    var stage: ImportStage
    var fraction: Double
}

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

/// Background import pipeline — never touches UI / SwiftData.
actor ImportPipeline {
    func prepare(
        data: Data,
        displayName: String,
        progress: (@Sendable (ImportProgress) -> Void)? = nil
    ) throws -> PreparedLocalBook {
        progress?(ImportProgress(stage: .reading, fraction: 0.05))
        progress?(ImportProgress(stage: .decoding, fraction: 0.15))

        let decoded = NovelTextDecoder.decodeDetailed(data)
        let bookId = UUID().uuidString

        progress?(ImportProgress(stage: .writing, fraction: 0.35))
        try BookFileStore.writeContentData(bookId: bookId, data: decoded.utf8Data)

        progress?(ImportProgress(stage: .splitting, fraction: 0.55))
        let ranges = ChapterSplitter.split(decoded.text)
        let chapters = ranges.enumerated().map { i, range in
            PreparedChapter(
                index: i,
                title: range.title,
                startOffset: range.start,
                length: range.length
            )
        }

        progress?(ImportProgress(stage: .writing, fraction: 0.75))
        try BookFileStore.writeChapters(bookId: bookId, text: decoded.text, ranges: ranges)

        progress?(ImportProgress(stage: .saving, fraction: 0.9))
        return PreparedLocalBook(
            bookId: bookId,
            title: Self.cleanTitle(displayName),
            contentRelativePath: BookFileStore.relativeContentPath(bookId: bookId),
            chapters: chapters
        )
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
