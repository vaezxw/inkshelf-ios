import Foundation

struct ChapterRange: Equatable {
    var title: String
    var start: Int
    var end: Int
    var length: Int { max(0, end - start) }
}

enum ChapterSplitter {
    static let heading = try! NSRegularExpression(
        pattern: #"(?m)^[ \t　]*(第[0-9零一二三四五六七八九十百千万〇两]+[章节回卷部集话][^\n]{0,48}|[Cc]hapter[\s\u3000]*[0-9]+[^\n]{0,48}|楔子|序章|序言|引子|前言|终章|尾声|后记|番外[^\n]{0,24})\s*$"#
    )

    static func split(_ text: String) -> [ChapterRange] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return [ChapterRange(title: "全文", start: 0, end: 0)]
        }

        let ns = text as NSString
        let matches = heading.matches(in: text, range: NSRange(location: 0, length: ns.length))
        if matches.count < 2 {
            return [ChapterRange(title: "全文", start: 0, end: text.count)]
        }

        var chapters: [ChapterRange] = []
        let first = matches[0]
        if first.range.location > 80 {
            chapters.append(ChapterRange(title: "前言", start: 0, end: utf16ToStringIndex(text, first.range.location)))
        }

        for (i, match) in matches.enumerated() {
            let titleRange = match.range(at: 1)
            let title = titleRange.location != NSNotFound
                ? ns.substring(with: titleRange).trimmingCharacters(in: .whitespacesAndNewlines)
                : "章节 \(i + 1)"
            let start = utf16ToStringIndex(text, match.range.location)
            let endUTF16 = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            let end = utf16ToStringIndex(text, endUTF16)
            if end > start {
                chapters.append(ChapterRange(title: title, start: start, end: end))
            }
        }

        return chapters.isEmpty
            ? [ChapterRange(title: "全文", start: 0, end: text.count)]
            : chapters
    }

    private static func utf16ToStringIndex(_ text: String, _ utf16: Int) -> Int {
        let idx = String.Index(utf16Offset: min(max(utf16, 0), text.utf16.count), in: text)
        return text.distance(from: text.startIndex, to: idx)
    }
}
