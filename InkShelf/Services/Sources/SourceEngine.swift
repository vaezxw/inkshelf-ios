import Foundation
import SwiftSoup

enum SourceError: LocalizedError {
    case format(String)
    case network(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .format(let s), .network(let s), .unsupported(let s): return s
        }
    }
}

struct SearchBookHit: Identifiable, Hashable {
    var id: String { "\(sourceId)|\(bookUrl)|\(name)" }
    var sourceId: String
    var sourceName: String
    var name: String
    var author: String?
    var intro: String?
    var coverUrl: String?
    var bookUrl: String
}

struct RemoteChapter: Hashable {
    var title: String
    var url: String
}

struct SearchRequestSpec {
    var url: String
    var method: String
    var body: String?
    var headers: [String: String]
}

enum SourceEngine {
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 12
        cfg.timeoutIntervalForResource = 25
        cfg.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
        ]
        return URLSession(configuration: cfg)
    }()

    /// Parse Legado JSON on the calling isolation; returns a value-typed map used only locally.
    private static func parseRawSource(_ json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SourceError.format("书源数据损坏")
        }
        return obj
    }

    static func isUnsupportedSearchUrl(_ searchUrl: String?) -> Bool {
        guard let searchUrl else { return true }
        let t = searchUrl.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return true }
        return t.contains("@js") || t.contains("<js>") || t.contains("{{url()") || t.contains("java.")
    }

    static func isUnsupportedSearchJSON(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return true
        }
        return isUnsupportedSearchUrl(raw["searchUrl"] as? String)
    }

    static func parseSearchTemplate(base: String, template: String, key: String, page: Int) -> SearchRequestSpec {
        var tpl = template.trimmingCharacters(in: .whitespacesAndNewlines)
        var options: [String: Any] = [:]
        if let regex = try? NSRegularExpression(pattern: #",(\{[\s\S]*\})\s*$"#),
           let match = regex.firstMatch(in: tpl, range: NSRange(tpl.startIndex..<tpl.endIndex, in: tpl)),
           let optRange = Range(match.range(at: 1), in: tpl) {
            let optRaw = String(tpl[optRange])
            if let full = Range(match.range, in: tpl) {
                tpl = String(tpl[..<full.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let data = optRaw.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                options = obj
            }
        }
        func replaceVars(_ input: String) -> String {
            input
                .replacingOccurrences(of: "{{key}}", with: key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key)
                .replacingOccurrences(of: "{{page}}", with: "\(page)")
        }
        tpl = replaceVars(tpl)
        let abs = absURL(base: base, maybe: tpl) ?? tpl
        let method = "\(options["method"] ?? "GET")".uppercased()
        var headers: [String: String] = [:]
        if let rawHeaders = options["headers"] as? String,
           let data = rawHeaders.data(using: .utf8),
           let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            map.forEach { headers[$0.key] = "\($0.value)" }
        } else if let map = options["headers"] as? [String: Any] {
            map.forEach { headers[$0.key] = "\($0.value)" }
        }
        var body: String?
        if let rawBody = options["body"] {
            body = replaceVars("\(rawBody)")
        }
        return SearchRequestSpec(
            url: abs,
            method: method == "POST" ? "POST" : "GET",
            body: body,
            headers: headers
        )
    }

    static func search(rawSourceJSON: String, sourceId: String, sourceName: String, keyword: String, page: Int = 1) async throws -> [SearchBookHit] {
        let rawSource = try parseRawSource(rawSourceJSON)
        let searchUrl = rawSource["searchUrl"] as? String
        guard let searchUrl, !searchUrl.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SourceError.unsupported("书源未配置 searchUrl")
        }
        if isUnsupportedSearchUrl(searchUrl) {
            throw SourceError.unsupported("书源搜索含 JS，暂不支持")
        }
        guard let rule = rawSource["ruleSearch"] as? [String: Any] else {
            throw SourceError.unsupported("书源未配置 ruleSearch")
        }
        let base = rawSource["bookSourceUrl"] as? String ?? ""
        let spec = parseSearchTemplate(base: base, template: searchUrl, key: keyword, page: page)
        let body = try await requestBody(spec: spec, headerJson: rawSource["header"])
        let bookListRule = rule["bookList"] as? String

        if RuleSelector.isJsonRule(bookListRule) || body.trimmingCharacters(in: .whitespaces).hasPrefix("{") || body.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
            guard let data = body.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
            let items = RuleSelector.jsonList(root, bookListRule)
            return items.compactMap { item -> SearchBookHit? in
                guard let map = item as? [String: Any] else { return nil }
                let name = RuleSelector.jsonField(map, rule["name"] as? String)
                let bookUrl = absURL(base: base, maybe: RuleSelector.jsonField(map, rule["bookUrl"] as? String)) ?? ""
                guard !name.isEmpty, !bookUrl.isEmpty else { return nil }
                return SearchBookHit(
                    sourceId: sourceId,
                    sourceName: sourceName,
                    name: name,
                    author: emptyToNil(RuleSelector.jsonField(map, rule["author"] as? String)),
                    intro: emptyToNil(RuleSelector.jsonField(map, rule["intro"] as? String)),
                    coverUrl: absURL(base: base, maybe: RuleSelector.jsonField(map, rule["coverUrl"] as? String)),
                    bookUrl: bookUrl
                )
            }
        }

        let doc = try SwiftSoup.parse(body)
        let nodes = RuleSelector.selectList(doc: doc, bookListRule: bookListRule)
        return nodes.compactMap { node -> SearchBookHit? in
            let name = RuleSelector.readFromElement(node, rule: rule["name"] as? String)
            let bookUrl = absURL(base: spec.url, maybe: RuleSelector.readFromElement(node, rule: rule["bookUrl"] as? String)) ?? ""
            guard !name.isEmpty, !bookUrl.isEmpty else { return nil }
            return SearchBookHit(
                sourceId: sourceId,
                sourceName: sourceName,
                name: name,
                author: emptyToNil(RuleSelector.readFromElement(node, rule: rule["author"] as? String)),
                intro: emptyToNil(RuleSelector.readFromElement(node, rule: rule["intro"] as? String)),
                coverUrl: absURL(base: base, maybe: RuleSelector.readFromElement(node, rule: rule["coverUrl"] as? String)),
                bookUrl: bookUrl
            )
        }
    }

    static func fetchToc(rawSourceJSON: String, bookUrl: String) async throws -> [RemoteChapter] {
        let rawSource = try parseRawSource(rawSourceJSON)
        var tocUrl = bookUrl
        if let info = rawSource["ruleBookInfo"] as? [String: Any],
           let nextRule = info["tocUrl"] as? String,
           !nextRule.trimmingCharacters(in: .whitespaces).isEmpty {
            let body = try await getBody(url: bookUrl, headerJson: rawSource["header"])
            if RuleSelector.isJsonRule(nextRule) || body.trimmingCharacters(in: .whitespaces).hasPrefix("{") {
                if let data = body.data(using: .utf8),
                   let root = try? JSONSerialization.jsonObject(with: data) {
                    tocUrl = absURL(base: bookUrl, maybe: RuleSelector.jsonField(root, nextRule)) ?? bookUrl
                }
            } else {
                let doc = try SwiftSoup.parse(body)
                tocUrl = absURL(base: bookUrl, maybe: RuleSelector.readFromDocument(doc, rule: nextRule)) ?? bookUrl
            }
        }
        guard let rule = rawSource["ruleToc"] as? [String: Any] else {
            throw SourceError.unsupported("书源未配置 ruleToc")
        }
        let body = try await getBody(url: tocUrl, headerJson: rawSource["header"])
        let listRule = rule["chapterList"] as? String
        if RuleSelector.isJsonRule(listRule) || body.trimmingCharacters(in: .whitespaces).hasPrefix("{") || body.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
            guard let data = body.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
            return RuleSelector.jsonList(root, listRule).compactMap { item -> RemoteChapter? in
                guard let map = item as? [String: Any] else { return nil }
                let title = RuleSelector.jsonField(map, rule["chapterName"] as? String)
                let url = absURL(base: tocUrl, maybe: RuleSelector.jsonField(map, rule["chapterUrl"] as? String)) ?? ""
                guard !title.isEmpty, !url.isEmpty else { return nil }
                return RemoteChapter(title: title, url: url)
            }
        }
        let doc = try SwiftSoup.parse(body)
        return RuleSelector.selectList(doc: doc, bookListRule: listRule).compactMap { node -> RemoteChapter? in
            let title = RuleSelector.readFromElement(node, rule: rule["chapterName"] as? String)
            let url = absURL(base: tocUrl, maybe: RuleSelector.readFromElement(node, rule: rule["chapterUrl"] as? String)) ?? ""
            guard !title.isEmpty, !url.isEmpty else { return nil }
            return RemoteChapter(title: title, url: url)
        }
    }

    static func fetchContent(rawSourceJSON: String, chapterUrl: String) async throws -> String {
        let rawSource = try parseRawSource(rawSourceJSON)
        guard let rule = rawSource["ruleContent"] as? [String: Any] else {
            throw SourceError.unsupported("书源未配置 ruleContent")
        }
        var buffer = ""
        var visited = Set<String>()
        var url = chapterUrl
        var pages = 0
        while !url.isEmpty, pages < 30, visited.insert(url).inserted {
            pages += 1
            let body = try await getBody(url: url, headerJson: rawSource["header"])
            let pageText = extractContent(body: body, contentRule: rule["content"] as? String)
            if !pageText.isEmpty {
                if !buffer.isEmpty { buffer += "\n" }
                buffer += pageText
            }
            guard let nextRule = rule["nextContentUrl"] as? String,
                  !nextRule.trimmingCharacters(in: .whitespaces).isEmpty else { break }
            let next: String?
            if RuleSelector.isJsonRule(nextRule) || body.trimmingCharacters(in: .whitespaces).hasPrefix("{") {
                if let data = body.data(using: .utf8),
                   let root = try? JSONSerialization.jsonObject(with: data) {
                    next = RuleSelector.jsonField(root, nextRule)
                } else { next = nil }
            } else {
                let doc = try SwiftSoup.parse(body)
                next = RuleSelector.resolveNextUrl(doc: doc, rule: nextRule)
            }
            guard let abs = absURL(base: url, maybe: next), abs != url else { break }
            url = abs
        }
        var content = buffer
        if let replace = rule["replaceRegex"] as? String, !replace.isEmpty {
            if replace.contains("##") {
                let normalized = replace.hasPrefix("##") ? "x\(replace)" : "x##\(replace)"
                let (_, replaces) = RuleSelector.splitAllInOne(normalized)
                content = RuleSelector.applyReplaces(content, replaces)
            } else if let regex = try? NSRegularExpression(pattern: replace, options: [.dotMatchesLineSeparators]) {
                let range = NSRange(content.startIndex..<content.endIndex, in: content)
                content = regex.stringByReplacingMatches(in: content, range: range, withTemplate: "")
            }
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractContent(body: String, contentRule: String?) -> String {
        guard let contentRule, !contentRule.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
        if RuleSelector.isJsonRule(contentRule) || body.trimmingCharacters(in: .whitespaces).hasPrefix("{") {
            guard let data = body.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) else { return "" }
            var content = RuleSelector.jsonField(root, contentRule)
            if content.contains("<"), content.contains(">") {
                content = RuleSelector.htmlToPlain(content)
            }
            return content
        }
        guard let doc = try? SwiftSoup.parse(body) else { return "" }
        let (base, replaces) = RuleSelector.splitAllInOne(contentRule)
        let parts = RuleSelector.splitAtChain(base)
        let attr = parts.last?.lowercased() == "html" ? "html" : "text"
        if attr == "html" {
            let selectorParts = parts.dropLast()
            let selector = selectorParts.first.map { RuleSelector.splitIndexed($0).0 } ?? ""
            let html: String
            if selector.isEmpty {
                html = (try? doc.body()?.html()) ?? ""
            } else {
                html = (try? doc.select(selector).first()?.html()) ?? ""
            }
            return RuleSelector.applyReplaces(RuleSelector.htmlToPlain(html), replaces)
        }
        return RuleSelector.applyReplaces(RuleSelector.readFromDocument(doc, rule: base), replaces)
    }

    private static func getBody(url: String, headerJson: Any?) async throws -> String {
        try await requestBody(spec: SearchRequestSpec(url: url, method: "GET", body: nil, headers: [:]), headerJson: headerJson)
    }

    private static func requestBody(spec: SearchRequestSpec, headerJson: Any?) async throws -> String {
        guard let url = URL(string: spec.url) else { throw SourceError.network("无效 URL") }
        var req = URLRequest(url: url)
        req.httpMethod = spec.method
        var headers = spec.headers
        if let headerJson {
            if let s = headerJson as? String, let data = s.data(using: .utf8),
               let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                map.forEach { headers[$0.key] = "\($0.value)" }
            } else if let map = headerJson as? [String: Any] {
                map.forEach { headers[$0.key] = "\($0.value)" }
            }
        }
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        if spec.method == "POST" {
            req.httpBody = spec.body?.data(using: .utf8)
            if req.value(forHTTPHeaderField: "Content-Type") == nil {
                req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            }
        }
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw SourceError.network("HTTP \(http.statusCode)")
        }
        return NovelTextDecoder.decode(data)
    }

    static func absURL(base: String, maybe: String?) -> String? {
        guard let maybe else { return nil }
        let value = maybe.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        if let u = URL(string: value), u.scheme != nil { return value }
        guard let baseURL = URL(string: base) else { return value }
        return URL(string: value, relativeTo: baseURL)?.absoluteString
    }

    private static func emptyToNil(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
