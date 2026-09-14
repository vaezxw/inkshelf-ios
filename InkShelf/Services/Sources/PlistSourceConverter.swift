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
            return try convertServerList(map)
        }
        if map["search"] != nil || map["url"] != nil {
            return [try toLegado(map)]
        }
        throw SourceError.format("无法识别该 plist")
    }

    static func xpathToLegadoRule(_ xpath: String) -> String {
        var s = xpath.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        if let range = s.range(of: "@@@regex", options: .caseInsensitive) {
            s = String(s[..<range.lowerBound])
        }
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
        let segments = s.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let css = segments.map(xpathStepToCss).joined(separator: " ")
        return attr.isEmpty ? css : "\(css)@\(attr)"
    }

    private static func convertServerList(_ map: [String: Any]) throws -> [[String: Any]] {
        guard let list = map["serverList"] as? [[String: Any]], !list.isEmpty else {
            throw SourceError.format("serverList 为空或格式无效")
        }
        var converted: [[String: Any]] = []
        var skipped = 0
        for server in list {
            do {
                converted.append(try convertServer(server))
            } catch {
                skipped += 1
            }
        }
        guard !converted.isEmpty else {
            throw SourceError.format("serverList 里没有可搜索书源（需要 searchFirstPageUrl）")
        }
        _ = skipped
        return converted
    }

    private static func convertServer(_ server: [String: Any]) throws -> [String: Any] {
        let name = str(server["serverName"]).isEmpty ? "未命名书源" : str(server["serverName"])
        var host = str(server["serverHostURL"])
        if host.hasSuffix("/") { host = String(host.dropLast()) }
        host = migrateHostString(host)
        guard !host.isEmpty else { throw SourceError.format("书源「\(name)」缺少 serverHostURL") }

        let search = server["searchBook"] as? [String: Any] ?? [:]
        let parser = search["search_parser"] as? [String: Any] ?? [:]
        let detail = server["detailBook"] as? [String: Any] ?? [:]
        let read = server["readBook"] as? [String: Any] ?? [:]

        let searchUrl = try buildSearchUrl(search, sourceName: name)
        let bookList = xpathToLegadoRule(str(search["search_listDivision"]))
        guard !bookList.isEmpty else {
            throw SourceError.format("书源「\(name)」缺少搜索列表规则")
        }

        let nameRule = fieldRule(str(parser["search_bookname"]))
        let authorRule = fieldRule(str(parser["search_author"]))
        let introRule = fieldRule(str(parser["search_desc"]))
        let coverRule = fieldRule(
            str(parser["search_cover"]),
            addString: str(parser["search_coveraddString"])
        )
        let bookUrlRule = fieldRule(
            str(parser["search_detailUrl"]),
            addString: str(parser["search_detailUrladdString"]),
            fenge: str(parser["search_detailUrl_fenge_ids"]),
            fengeIndex: intVal(parser["search_detailUrl_fenge_ids_index_num"])
        )

        var tocUrl = xpathToLegadoRule(str(detail["detail_muLu_Url"]))
        let tocAdd = str(detail["detail_muLuUrladdString"])
        if !tocAdd.isEmpty, tocAdd != "详情网址", !tocUrl.isEmpty {
            tocUrl = prependRule(tocUrl, prefix: tocAdd)
        }

        let chapterList = xpathToLegadoRule(str(detail["mulu_list"]))
        let chapterName = xpathToLegadoRule(str(detail["mulu_title"]))
        var chapterUrl = xpathToLegadoRule(str(detail["mulu_url"]))
        let chapterAdd = str(detail["mulu_url_addString"])
        if !chapterAdd.isEmpty, chapterAdd != "详情网址" {
            chapterUrl = fieldRule(
                str(detail["mulu_url"]),
                addString: chapterAdd,
                fenge: str(detail["mulu_url_fenge_ids"]),
                fengeIndex: intVal(detail["mulu_url_fenge_ids_index_num"])
            )
        }

        var contentRule = xpathToLegadoRule(str(read["chapterContent"]))
        if !contentRule.isEmpty, !contentRule.contains("@") {
            contentRule += "@html"
        }
        if let replaces = replacePairs(read["contentReplaces"]) {
            contentRule += replaces
        }

        var legado: [String: Any] = [
            "bookSourceName": name,
            "bookSourceUrl": host,
            "bookSourceType": 0,
            "enabled": boolVal(server["serverIsEndble"], default: true),
            "bookSourceGroup": str(server["serverInfo"]),
            "searchUrl": searchUrl,
            "ruleSearch": [
                "bookList": bookList,
                "name": nameRule,
                "author": authorRule,
                "intro": introRule,
                "coverUrl": coverRule,
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
        if !tocUrl.isEmpty {
            legado["ruleBookInfo"] = ["tocUrl": tocUrl]
        }
        return legado
    }

    private static func buildSearchUrl(_ search: [String: Any], sourceName: String) throws -> String {
        var url = str(search["searchFirstPageUrl"]).replacingOccurrences(of: "@@@", with: "{{key}}")
        guard !url.isEmpty else {
            throw SourceError.format("书源「\(sourceName)」缺少 searchFirstPageUrl")
        }
        url = migrateHostString(url)
        let type = str(search["searchPageRequestType"])
        let posts = search["searchPostValueAndKey"] as? [[String: Any]] ?? []
        var headers: [String: String] = [:]
        var bodyPairs: [(String, String)] = []
        for item in posts {
            let rawKey = str(item["postKey"])
            guard !rawKey.isEmpty else { continue }
            let loc = str(item["postLocation"]).lowercased()
            let value = str(item["postValue"]).replacingOccurrences(of: "@@@", with: "{{key}}")
            if loc == "header" {
                let lowered = rawKey.lowercased()
                if lowered == "accept-encoding" || lowered == "host" || lowered == "connection" || lowered == "content-length" {
                    continue
                }
                headers[rawKey] = value
            } else if loc == "body" {
                var key = rawKey
                if key.hasPrefix("&") { key = String(key.dropFirst()) }
                bodyPairs.append((key, value))
            }
        }

        let isPost = type == "1"
        var options: [String: Any] = [:]
        if isPost {
            options["method"] = "POST"
            if !bodyPairs.isEmpty {
                options["body"] = bodyPairs.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
            }
        } else if !url.contains("{{key}}"), !bodyPairs.isEmpty {
            let query = bodyPairs.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
            url += url.contains("?") ? "&\(query)" : "?\(query)"
        }
        if !headers.isEmpty {
            options["headers"] = headers
        }
        guard !options.isEmpty else { return url }
        let data = try JSONSerialization.data(withJSONObject: options, options: [.sortedKeys])
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return "\(url),\(json)"
    }

    private static func fieldRule(
        _ raw: String,
        addString: String = "",
        fenge: String = "",
        fengeIndex: Int = 0
    ) -> String {
        var source = raw
        var stripPattern = ""
        if let range = source.range(of: "@@@regex", options: .caseInsensitive) {
            var spec = String(source[range.upperBound...])
            source = String(source[..<range.lowerBound])
            if spec.hasPrefix("<<:") { spec = String(spec.dropFirst(3)) }
            else if spec.hasPrefix("<<") { spec = String(spec.dropFirst(2)) }
            else if spec.hasPrefix(":") { spec = String(spec.dropFirst()) }
            stripPattern = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var rule = xpathToLegadoRule(source)
        if rule.isEmpty { return "" }

        if !fenge.isEmpty, fengeIndex >= 0 {
            let escaped = NSRegularExpression.escapedPattern(for: fenge)
            let capture = fengeIndex <= 0
                ? #"([\s\S]*?)"# + escaped + #"[\s\S]*"#
                : #"[\s\S]*?"# + escaped + #"([\s\S]*)"#
            let prefix = (addString.isEmpty || addString == "详情网址") ? "" : addString
            rule += "##\(capture)##\(prefix)$1"
            return rule
        }
        if !addString.isEmpty, addString != "详情网址" {
            rule = prependRule(rule, prefix: addString)
        }
        if !stripPattern.isEmpty {
            rule += "##\(stripPattern)##"
        }
        return rule
    }

    private static func prependRule(_ rule: String, prefix: String) -> String {
        "\(rule)##^(.*)$##\(prefix)$1"
    }

    private static func replacePairs(_ raw: Any?) -> String? {
        guard let list = raw as? [[String: Any]], !list.isEmpty else { return nil }
        var chunks: [String] = []
        for item in list {
            guard let key = item.keys.first else { continue }
            var replacement = str(item[key])
            if replacement == "=@=" { replacement = "" }
            if replacement == "[@@@$$$]" { replacement = "\n" }
            chunks.append(key)
            chunks.append(replacement)
        }
        guard !chunks.isEmpty else { return nil }
        return "##" + chunks.joined(separator: "##")
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
        var s = step.trimmingCharacters(in: .whitespaces)
        if s == "*" { return "*" }

        if let regex = try? NSRegularExpression(pattern: #"^([a-zA-Z0-9_-]+)\[position\(\s*>\s*1\s*\)\]$"#),
           let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..<s.endIndex, in: s)),
           let tagR = Range(match.range(at: 1), in: s) {
            return "\(s[tagR]):nth-child(n+2)"
        }
        if let regex = try? NSRegularExpression(pattern: #"^([a-zA-Z0-9_-]+)\[@id=['"]([^'"]+)['"]\]$"#),
           let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..<s.endIndex, in: s)),
           let tagR = Range(match.range(at: 1), in: s),
           let idR = Range(match.range(at: 2), in: s) {
            _ = s[tagR]
            return "#\(s[idR])"
        }
        if let regex = try? NSRegularExpression(pattern: #"^([a-zA-Z0-9_-]+)\[@class=['"]([^'"]+)['"]\]$"#),
           let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..<s.endIndex, in: s)),
           let tagR = Range(match.range(at: 1), in: s),
           let classR = Range(match.range(at: 2), in: s) {
            let tag = String(s[tagR])
            let classes = String(s[classR]).split(whereSeparator: \.isWhitespace).map { ".\($0)" }.joined()
            return "\(tag)\(classes)"
        }
        if let regex = try? NSRegularExpression(pattern: #"^([a-zA-Z0-9_-]+)\[(\d+)\]$"#),
           let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..<s.endIndex, in: s)),
           let tagR = Range(match.range(at: 1), in: s),
           let nR = Range(match.range(at: 2), in: s) {
            return "\(s[tagR]):nth-of-type(\(s[nR]))"
        }
        return s
    }

    private static func migrateHostString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "www.xs52.info", with: "www.wx52.info")
            .replacingOccurrences(of: "://xs52.info", with: "://www.wx52.info")
            .replacingOccurrences(of: "www.xs52.la", with: "www.wx52.info")
            .replacingOccurrences(of: "://xs52.la", with: "://www.wx52.info")
    }

    private static func str(_ any: Any?) -> String {
        guard let any else { return "" }
        if any is NSNull { return "" }
        return "\(any)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func intVal(_ any: Any?) -> Int {
        if let n = any as? Int { return n }
        if let n = any as? NSNumber { return n.intValue }
        return Int(str(any)) ?? 0
    }

    private static func boolVal(_ any: Any?, default fallback: Bool) -> Bool {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        let s = str(any).lowercased()
        if s.isEmpty { return fallback }
        return s == "1" || s == "true" || s == "yes"
    }
}
