import Foundation

struct DecodedNovelText: Sendable {
    var text: String
    /// UTF-8 bytes ready to write to disk (no need to re-encode when already UTF-8).
    var utf8Data: Data
    var encodingName: String
}

enum NovelTextDecoder {
    static func decode(_ data: Data) -> String {
        decodeDetailed(data).text
    }

    /// Prefer a single full decode. Sample-score alternatives only when UTF-8 looks weak.
    static func decodeDetailed(_ data: Data) -> DecodedNovelText {
        if data.isEmpty {
            return DecodedNovelText(text: "", utf8Data: Data(), encodingName: "empty")
        }

        var bytes = data
        var hadBOM = false
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            bytes = Data(bytes.dropFirst(3))
            hadBOM = true
        }

        if let utf8 = String(data: bytes, encoding: .utf8) {
            let utf8Score = score(utf8)
            // Strong UTF-8 / already looks Chinese — skip full GBK materialization.
            if utf8Score >= 20 || !looksLikeHighByteNoise(bytes) {
                return DecodedNovelText(text: utf8, utf8Data: bytes, encodingName: hadBOM ? "utf8-bom" : "utf8")
            }
            if let gbk = decodeGBK(bytes) {
                if score(gbk) > utf8Score + 8 {
                    let out = gbk.data(using: .utf8) ?? Data(gbk.utf8)
                    return DecodedNovelText(text: gbk, utf8Data: out, encodingName: "gb18030")
                }
            }
            return DecodedNovelText(text: utf8, utf8Data: bytes, encodingName: hadBOM ? "utf8-bom" : "utf8")
        }

        if let gbk = decodeGBK(bytes) {
            let out = gbk.data(using: .utf8) ?? Data(gbk.utf8)
            return DecodedNovelText(text: gbk, utf8Data: out, encodingName: "gb18030")
        }

        let latin1 = String(data: bytes, encoding: .isoLatin1) ?? String(decoding: bytes, as: UTF8.self)
        let out = latin1.data(using: .utf8) ?? Data(latin1.utf8)
        return DecodedNovelText(text: latin1, utf8Data: out, encodingName: "latin1-fallback")
    }

    static func repairIfMojibake(_ text: String) -> String? {
        let markers: Set<Character> = ["\u{00C3}", "\u{00C2}", "\u{FFFD}"]
        let bad = text.filter { markers.contains($0) }.count
        guard bad > 8 || (text.count > 40 && Double(bad) / Double(text.count) > 0.02) else {
            return nil
        }
        guard let data = text.data(using: .isoLatin1) else { return nil }
        let repaired = decode(data)
        return score(repaired) > score(text) + 5 ? repaired : nil
    }

    private static func looksLikeHighByteNoise(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        let sample = data.prefix(4096)
        var high = 0
        for b in sample where b >= 0x80 { high += 1 }
        return Double(high) / Double(sample.count) > 0.35
    }

    private static func decodeGBK(_ data: Data) -> String? {
        let cfEnc = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
        return String(data: data, encoding: String.Encoding(rawValue: nsEnc))
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
