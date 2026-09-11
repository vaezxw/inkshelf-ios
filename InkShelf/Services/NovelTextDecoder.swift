import Foundation

enum NovelTextDecoder {
    static func decode(_ data: Data) -> String {
        if data.isEmpty { return "" }
        var bytes = data
        // UTF-8 BOM
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            bytes = bytes.dropFirst(3)
        }

        var candidates: [String] = []
        if let utf8 = String(data: bytes, encoding: .utf8) {
            candidates.append(utf8)
        }
        if let gbk = decodeGBK(bytes) {
            candidates.append(gbk)
        }
        if let latin1 = String(data: bytes, encoding: .isoLatin1) {
            candidates.append(latin1)
        }
        return pickBest(candidates) ?? String(decoding: bytes, as: UTF8.self)
    }

    static func repairIfMojibake(_ text: String) -> String? {
        // Heuristic: many mojibake markers from UTF-8 misread as Latin-1.
        let markers: Set<Character> = ["\u{00C3}", "\u{00C2}", "\u{FFFD}"]
        let bad = text.filter { markers.contains($0) }.count
        guard bad > 8 || (text.count > 40 && Double(bad) / Double(text.count) > 0.02) else {
            return nil
        }
        guard let data = text.data(using: .isoLatin1) else { return nil }
        let repaired = decode(data)
        return score(repaired) > score(text) + 5 ? repaired : nil
    }

    private static func decodeGBK(_ data: Data) -> String? {
        let cfEnc = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
        return String(data: data, encoding: String.Encoding(rawValue: nsEnc))
    }

    private static func pickBest(_ candidates: [String]) -> String? {
        candidates.max(by: { score($0) < score($1) })
    }

    private static func score(_ text: String) -> Int {
        var s = 0
        let punct = CharacterSet(charactersIn: "\u{FF0C}\u{3002}\u{FF01}\u{FF1F}\u{3001}\u{FF1B}\u{FF1A}\u{201C}\u{201D}\u{2018}\u{2019}\u{FF08}\u{FF09}\u{300A}\u{300B}\u{2014}\u{2026}")
        for ch in text.prefix(8000) {
            if ch == "\u{FFFD}" { s -= 8; continue }
            let v = ch.unicodeScalars.first?.value ?? 0
            if (0x4E00...0x9FFF).contains(v) { s += 2 }
            else if ch.isLetter || ch.isNumber || ch.isWhitespace || ch.unicodeScalars.allSatisfy({ punct.contains($0) }) {
                s += 1
            } else if v < 32 && ch != "\n" && ch != "\t" && ch != "\r" {
                s -= 3
            }
        }
        return s
    }
}
