import Foundation

enum PlistSourceConverter {
    static func looksLikePlist(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("<plist") || (t.hasPrefix("<?xml") && t.contains("<plist"))
    }

    static func convert(_ plistXML: String) throws -> [[String: Any]] {
        guard let data = plistXML.data(using: .utf8) else {
            throw SourceError.format("plist 无效")
        }
        var format = PropertyListSerialization.PropertyListFormat.xml
        let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        guard let map = obj as? [String: Any] else {
            throw SourceError.format("plist 缺少根 dict")
        }
        if map["serverList"] != nil {
            throw SourceError.format("这是书单/服务器列表 plist，不是可搜索书源。请导入 Legado JSON 或带 search/chapters/content 的站点 plist。")
        }
        if map["search"] != nil || map["url"] != nil {
            return [try toLegado(map)]
        }
        throw SourceError.format("无法识别该 plist")
    }

    static func xpathToLegadoRule(_ xpath: String) -> String {
        var s = xpath.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        var attr = ""
        if s.hasSuffix("/text()") {
            attr = "text"
            s = String(s.dropLast("/text()".count))
        } else if let range = s.range(of: #"/@([A-Za-z0-9_-]+)$"#, options: .regularExpression) {
            attr = String(s[range].dropFirst(2))
            s = String(s[..<range.lowerBound])
        }
        if s.hasPrefix(".//") { s = String(s.dropFirst(3)) }
        else if s.hasPrefix("//") { s = String(s.dropFirst(2)) }
        else if s.hasPrefix("./") { s = String(s.dropFirst(2)) }
        if s == "." || s.isEmpty {
            return attr.isEmpty ? "" : "@\(attr)"
        }
        let segments = s.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        let css = segments.map(xpathStepToCss).joined(separator: " ")
        return attr.isEmpty ? css : "\(css)@\(attr)"
    }

    private static func toLegado(_ src: [String: Any]) throws -> [String: Any] {
        let name = "\(src["name"] ?? "未命名书源")".trimmingCharacters(in: .whitespaces)
        var base = "\(src["baseUrl"] ?? src["url"] ?? "")".trimmingCharacters(in: .whitespaces)
        if base.hasSuffix("/") { base = String(base.dropLast()) }
        guard !base.isEmpty else { throw SourceError.format("书源「\(name)」缺少 url/baseUrl") }
        let search = src["search"] as? [String: Any] ?? [:]
        let chapters = src["chapters"] as? [String: Any] ?? [:]
        let content = src["content"] as? [String: Any] ?? [:]
        var searchUrl = "\(search["url"] ?? "")".trimmingCharacters(in: .whitespaces)
        guard !searchUrl.isEmpty else { throw SourceError.format("书源「\(name)」缺少 search.url") }
        searchUrl = searchUrl.replacingOccurrences(of: "{key}", with: "{{key}}")
            .replacingOccurrences(of: "{page}", with: "{{page}}")
        let bookList = xpathToLegadoRule("\(search["list"] ?? "")")
        let nameRule = xpathToLegadoRule("\(search["title"] ?? "")")
        let authorRule = xpathToLegadoRule("\(search["author"] ?? "")")
        let bookUrlRule = xpathToLegadoRule("\(search["link"] ?? "")")
        let chapterList = xpathToLegadoRule("\(chapters["list"] ?? "")")
        let chapterName = xpathToLegadoRule("\(chapters["title"] ?? "./text()")")
        let chapterUrl = xpathToLegadoRule("\(chapters["link"] ?? "./@href")")
        var contentRule = xpathToLegadoRule("\(content["content"] ?? "")")
        if !contentRule.isEmpty, !contentRule.contains("@") {
            contentRule = "\(contentRule)@html"
        }
        return [
            "bookSourceName": name,
            "bookSourceUrl": base,
            "bookSourceType": 0,
            "enabled": true,
            "searchUrl": searchUrl,
            "ruleSearch": [
                "bookList": bookList,
                "name": nameRule,
                "author": authorRule,
                "bookUrl": bookUrlRule,
            ].filter { !("\($0.value)".isEmpty) },
            "ruleToc": [
                "chapterList": chapterList,
                "chapterName": chapterName,
                "chapterUrl": chapterUrl,
            ].filter { !("\($0.value)".isEmpty) },
            "ruleContent": [
                "content": contentRule,
            ].filter { !("\($0.value)".isEmpty) },
        ]
    }

    private static func xpathStepToCss(_ step: String) -> String {
        if let m = step.range(of: #"^([a-zA-Z0-9_-]+)\[@id=['"]([^'"]+)['"]\]$"#, options: .regularExpression) {
            let s = String(step[m])
            if let id = s.split(separator: "'").dropFirst().first ?? s.split(separator: "\"").dropFirst().first {
                return "#\(id)"
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"^([a-zA-Z0-9_-]+)\[@class=['"]([^'"]+)['"]\]$"#),
           let match = regex.firstMatch(in: step, range: NSRange(step.startIndex..<step.endIndex, in: step)),
           let tagR = Range(match.range(at: 1), in: step),
           let classR = Range(match.range(at: 2), in: step) {
            let tag = String(step[tagR])
            let classes = String(step[classR]).split(whereSeparator: \.isWhitespace).map { ".\($0)" }.joined()
            return "\(tag)\(classes)"
        }
        if let regex = try? NSRegularExpression(pattern: #"^([a-zA-Z0-9_-]+)\[(\d+)\]$"#),
           let match = regex.firstMatch(in: step, range: NSRange(step.startIndex..<step.endIndex, in: step)),
           let tagR = Range(match.range(at: 1), in: step),
           let nR = Range(match.range(at: 2), in: step) {
            return "\(step[tagR]):nth-child(\(step[nR]))"
        }
        return step
    }
}
