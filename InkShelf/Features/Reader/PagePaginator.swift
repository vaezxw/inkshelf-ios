import UIKit

enum PagePaginator {
    /// Paginate chapter text to fit `size` using attributed-string height binary search.
    static func paginate(text: String, size: CGSize, font: UIFont, lineHeightMultiple: CGFloat) -> [String] {
        guard !text.isEmpty, size.width > 20, size.height > 40 else {
            return text.isEmpty ? [""] : [text]
        }
        var remaining = text
        var pages: [String] = []
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = lineHeightMultiple
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
        ]
        while !remaining.isEmpty {
            if fits(remaining, size: size, attrs: attrs) {
                pages.append(remaining)
                break
            }
            var low = 1
            var high = remaining.count
            var best = 1
            while low <= high {
                let mid = (low + high) / 2
                let prefix = String(remaining.prefix(mid))
                if fits(prefix, size: size, attrs: attrs) {
                    best = mid
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            var cut = best
            let window = remaining.prefix(best)
            if let breakIdx = window.lastIndex(where: { $0 == "\n" || $0 == " " || $0 == "　" }),
               remaining.distance(from: remaining.startIndex, to: breakIdx) > best / 3 {
                cut = remaining.distance(from: remaining.startIndex, to: breakIdx) + 1
            }
            cut = max(1, min(cut, remaining.count))
            pages.append(String(remaining.prefix(cut)))
            remaining = String(remaining.dropFirst(cut))
        }
        return pages.isEmpty ? [""] : pages
    }

    private static func fits(_ text: String, size: CGSize, attrs: [NSAttributedString.Key: Any]) -> Bool {
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: size.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        )
        return ceil(rect.height) <= size.height + 0.5
    }
}
