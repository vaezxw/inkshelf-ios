import UIKit

struct PageRange: Sendable, Equatable {
    var location: Int
    var length: Int

    var nsRange: NSRange { NSRange(location: location, length: length) }
}

enum PagePaginator {
    /// TextKit / CTFramesetter pagination returning UTF-16 ranges into `text`.
    /// Safe to call off the main actor.
    nonisolated static func paginateRanges(
        text: String,
        size: CGSize,
        font: UIFont,
        lineHeightMultiple: CGFloat
    ) -> [PageRange] {
        var pages: [PageRange] = []
        enumerateRanges(text: text, size: size, font: font, lineHeightMultiple: lineHeightMultiple) { range in
            pages.append(range)
        }
        return pages
    }

    /// Yields ranges as soon as each page is measured so the first page can paint early.
    nonisolated static func paginateRangesStream(
        text: String,
        size: CGSize,
        font: UIFont,
        lineHeightMultiple: CGFloat
    ) -> AsyncStream<PageRange> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                enumerateRanges(text: text, size: size, font: font, lineHeightMultiple: lineHeightMultiple) { range in
                    continuation.yield(range)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    nonisolated private static func enumerateRanges(
        text: String,
        size: CGSize,
        font: UIFont,
        lineHeightMultiple: CGFloat,
        body: (PageRange) -> Void
    ) {
        guard !text.isEmpty, size.width > 20, size.height > 40 else {
            let len = (text as NSString).length
            body(PageRange(location: 0, length: len))
            return
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = lineHeightMultiple
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        let total = attributed.length
        var location = 0
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        var emitted = false

        while location < total {
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: location, length: 0),
                path,
                nil
            )
            let visible = CTFrameGetVisibleStringRange(frame)
            var len = visible.length
            if len <= 0 {
                len = min(1, total - location)
            }
            body(PageRange(location: location, length: len))
            emitted = true
            location += len
        }

        if !emitted {
            body(PageRange(location: 0, length: total))
        }
    }

    /// Compatibility helper used by tests / callers that still want page strings.
    nonisolated static func paginate(
        text: String,
        size: CGSize,
        font: UIFont,
        lineHeightMultiple: CGFloat
    ) -> [String] {
        let ns = text as NSString
        let ranges = paginateRanges(text: text, size: size, font: font, lineHeightMultiple: lineHeightMultiple)
        return ranges.map { ns.substring(with: $0.nsRange) }
    }

    nonisolated static func substring(text: String, range: PageRange) -> String {
        let ns = text as NSString
        let start = min(max(range.location, 0), ns.length)
        let len = min(max(range.length, 0), ns.length - start)
        return ns.substring(with: NSRange(location: start, length: len))
    }
}
