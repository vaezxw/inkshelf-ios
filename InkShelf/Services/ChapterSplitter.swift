import Foundation

struct ChapterRange: Equatable, Sendable {
    var title: String
    /// UTF-16 offsets into the stored content (NSString indices).
    var start: Int
    var end: Int
    var length: Int { max(0, end - start) }
}

enum ChapterSplitter {
    static let heading = try! NSRegularExpression(
        pattern: #"(?m)^[ \t　]*(第[0-9零一二三四五六七八九十百千万〇两]+[章节回卷部集话][^\n]{0,48}|[Cc]hapter[\s\u3000]*[0-9]+[^\n]{0,48}|楔子|序章|序言|引子|前言|终章|尾声|后记|番外[^\n]{0,24})\s*$"#
    )

    /// Soft chunk size (UTF-16) when the file has almost no chapter headings.
    private static let fallbackChunkUTF16 = 10_000

    static func split(_ text: String) -> [ChapterRange] {
        let ns = text as NSString
        let length = ns.length
        if length == 0 {
            return [ChapterRange(title: "全文", start: 0, end: 0)]
        }

        let matches = heading.matches(in: text, range: NSRange(location: 0, length: length))
        if matches.count < 2 {
            return splitBySize(ns, chunkUTF16: fallbackChunkUTF16)
        }

        var chapters: [ChapterRange] = []
        let first = matches[0]
        if first.range.location > 80 {
            chapters.append(ChapterRange(title: "前言", start: 0, end: first.range.location))
        }

        for (i, match) in matches.enumerated() {
            let titleRange = match.range(at: 1)
            let title = titleRange.location != NSNotFound
                ? ns.substring(with: titleRange).trimmingCharacters(in: .whitespacesAndNewlines)
                : "章节 \(i + 1)"
            let start = match.range.location
            let end = i + 1 < matches.count ? matches[i + 1].range.location : length
            if end > start {
                chapters.append(ChapterRange(title: title, start: start, end: end))
            }
        }

        return chapters.isEmpty
            ? [ChapterRange(title: "全文", start: 0, end: length)]
            : chapters
    }

    private static func splitBySize(_ ns: NSString, chunkUTF16: Int) -> [ChapterRange] {
        let length = ns.length
        if length <= chunkUTF16 {
            return [ChapterRange(title: "全文", start: 0, end: length)]
        }

        var chapters: [ChapterRange] = []
        var start = 0
        var index = 1
        while start < length {
            var end = min(start + chunkUTF16, length)
            if end < length {
                let lookBack = min(1_200, end - start)
                let probeLoc = end - lookBack
                let probe = ns.substring(with: NSRange(location: probeLoc, length: lookBack)) as NSString
                let br = probe.range(of: "\n", options: .backwards)
                if br.location != NSNotFound {
                    end = probeLoc + br.location + 1
                }
            }
            if end <= start { end = min(start + chunkUTF16, length) }
            chapters.append(ChapterRange(title: "第 \(index) 部分", start: start, end: end))
            start = end
            index += 1
        }
        return chapters
    }
}
