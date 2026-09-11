import Foundation
import SwiftSoup

enum RuleSelector {
    static func splitAllInOne(_ rule: String) -> (base: String, replaces: [(String, String)]) {
        guard let idx = rule.range(of: "##") else {
            return (rule.trimmingCharacters(in: .whitespacesAndNewlines), [])
        }
        let base = String(rule[..<idx.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = rule[idx.upperBound...].split(separator: "##", omittingEmptySubsequences: false).map(String.init)
        var replaces: [(String, String)] = []
        var i = 0
        while i < parts.count {
            let pattern = parts[i]
            if !pattern.isEmpty {
                let replacement = i + 1 < parts.count ? parts[i + 1] : ""
                replaces.append((pattern, replacement))
            }
            i += 2
        }
        return (base, replaces)
    }

    static func applyReplaces(_ input: String, _ replaces: [(String, String)]) -> String {
        var out = input
        for (pattern, replacement) in replaces {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                let range = NSRange(out.startIndex..<out.endIndex, in: out)
                out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: replacement)
            } else {
                out = out.replacingOccurrences(of: pattern, with: replacement)
            }
        }
        return out
    }

    static func normalizeCss(_ rule: String) -> String {
        var r = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.hasPrefix("@css:") { r = String(r.dropFirst(5)) }
        if r.hasPrefix("class.") { r = "." + r.dropFirst(6) }
        if r.hasPrefix("id.") { r = "#" + r.dropFirst(3) }
        if r.hasPrefix("tag.") { r = String(r.dropFirst(4)) }
        return r.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func splitAtChain(_ rule: String) -> [String] {
        let (base, _) = splitAllInOne(rule)
        return base.split(separator: "@").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func splitIndexed(_ part: String) -> (String, Int?) {
        let raw = part.trimmingCharacters(in: .whitespaces)
        guard let regex = try? NSRegularExpression(pattern: #"^(.*)\.(\d+)$"#),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..<raw.endIndex, in: raw)),
              let leftRange = Range(match.range(at: 1), in: raw),
              let idxRange = Range(match.range(at: 2), in: raw) else {
            return (normalizeCss(raw), nil)
        }
        let left = String(raw[leftRange]).trimmingCharacters(in: .whitespaces)
        if left.isEmpty { return (normalizeCss(raw), nil) }
        return (normalizeCss(left), Int(raw[idxRange]))
    }

    private static let attrs: Set<String> = [
        "text", "textnodes", "owntext", "html", "href", "src", "content", "value", "alt", "title"
    ]

    static func selectList(doc: Document, bookListRule: String?) -> [Element] {
        guard let bookListRule, !bookListRule.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let parts = splitAtChain(bookListRule)
        guard let first = parts.first else { return [] }
        let (selector, index) = splitIndexed(first)
        guard !selector.isEmpty else { return [] }
        do {
            let all = Array(try doc.select(selector))
            if let index {
                guard index >= 0, index < all.count else { return [] }
                return [all[index]]
            }
            return all
        } catch {
            return []
        }
    }

    static func readFromElement(_ root: Element, rule: String?) -> String {
        guard let rule, !rule.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
        let (base, replaces) = splitAllInOne(rule)
        var parts = splitAtChain(base)
        guard !parts.isEmpty else { return "" }
        var attr = "text"
        if let last = parts.last?.lowercased(), attrs.contains(last) {
            attr = last
            parts = Array(parts.dropLast())
        }
        var node: Element? = root
        for sel in parts {
            guard let current = node else { return "" }
            node = step(current, sel)
        }
        guard let node else { return "" }
        return applyReplaces(attrValue(node, attr), replaces)
    }

    static func readFromDocument(_ doc: Document, rule: String?) -> String {
        guard let rule, !rule.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
        let (base, replaces) = splitAllInOne(rule)
        var parts = splitAtChain(base)
        guard !parts.isEmpty else { return "" }
        var attr = "text"
        if let last = parts.last?.lowercased(), attrs.contains(last) {
            attr = last
            parts = Array(parts.dropLast())
        }
        guard let first = parts.first else {
            let body = doc.body()
            return body.map { applyReplaces(attrValue($0, attr), replaces) } ?? ""
        }
        let (css, index) = splitIndexed(first)
        var node: Element?
        do {
            if css.isEmpty {
                node = doc.body()
            } else if let index {
                let all = Array(try doc.select(css))
                node = (index >= 0 && index < all.count) ? all[index] : nil
            } else {
                node = try doc.select(css).first()
            }
        } catch {
            node = nil
        }
        for sel in parts.dropFirst() {
            guard let current = node else { return "" }
            node = step(current, sel)
        }
        guard let node else { return "" }
        return applyReplaces(attrValue(node, attr), replaces)
    }

    private static func step(_ root: Element, _ part: String) -> Element? {
        let (selector, index) = splitIndexed(part)
        if selector.isEmpty || selector == "text" { return root }
        do {
            if let index {
                let all = Array(try root.select(selector))
                guard index >= 0, index < all.count else { return nil }
                return all[index]
            }
            return try root.select(selector).first()
        } catch {
            return nil
        }
    }

    private static func attrValue(_ node: Element, _ attr: String) -> String {
        switch attr {
        case "html":
            return (try? node.html()) ?? ""
        case "text", "textnodes":
            return ((try? node.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        case "owntext":
            return node.ownText().trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return (try? node.attr(attr)) ?? ""
        }
    }

    static func isJsonRule(_ rule: String?) -> Bool {
        guard let rule else { return false }
        let (base, _) = splitAllInOne(rule)
        let t = base.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("$") || t.hasPrefix("[")
    }

    static func looksLikeJs(_ rule: String?) -> Bool {
        guard let rule else { return false }
        let t = rule.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t.hasPrefix("@js:") || t.hasPrefix("<js>") || t.contains("java.") ||
            (t.contains("function") && t.contains("return"))
    }

    static func htmlToPlain(_ html: String) -> String {
        guard let doc = try? SwiftSoup.parseBodyFragment(html) else { return html }
        let text = (try? doc.text()) ?? html
        return text
            .replacingOccurrences(of: #" +\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func jsonPath(_ root: Any?, _ rule: String) -> Any? {
        var path = rule.trimmingCharacters(in: .whitespaces)
        if path.hasPrefix("$.") { path = String(path.dropFirst(2)) }
        if path.hasPrefix("$") { path = String(path.dropFirst()) }
        if path.hasPrefix(".") { path = String(path.dropFirst()) }
        if path.isEmpty { return root }
        var current: Any? = root
        for rawPart in path.split(separator: ".") {
            guard let cursor = current else { return nil }
            var part = String(rawPart)
            var wantAll = false
            if part.hasSuffix("[*]") {
                wantAll = true
                part = String(part.dropLast(3))
            }
            if !part.isEmpty {
                if let map = cursor as? [String: Any] {
                    current = map[part]
                } else {
                    return nil
                }
            }
            if wantAll {
                guard current is [Any] else { return nil }
            }
        }
        return current
    }

    static func jsonList(_ root: Any?, _ listRule: String?) -> [Any] {
        guard let listRule, !listRule.trimmingCharacters(in: .whitespaces).isEmpty else {
            return root as? [Any] ?? []
        }
        let (base, _) = splitAllInOne(listRule)
        return jsonPath(root, base) as? [Any] ?? []
    }

    static func jsonField(_ item: Any?, _ rule: String?) -> String {
        guard let rule, !rule.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
        let (base, replaces) = splitAllInOne(rule)
        guard let value = jsonPath(item, base) else { return "" }
        return applyReplaces("\(value)".trimmingCharacters(in: .whitespacesAndNewlines), replaces)
    }

    static func resolveNextUrl(doc: Document, rule: String?) -> String? {
        guard let rule, !rule.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let raw = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextLabel = "\u{4E0B}\u{4E00}\u{9875}"
        let nextChapter = "\u{4E0B}\u{4E00}\u{7AE0}"
        if looksLikeJs(raw) || raw.contains(nextLabel) || raw.contains(nextChapter) {
            let keyword: String = {
                if let m = raw.range(of: #"indexOf\(\s*['"]([^'"]+)['"]\s*\)"#, options: .regularExpression) {
                    let s = String(raw[m])
                    if let inner = s.split(separator: "'").dropFirst().first
                        ?? s.split(separator: "\"").dropFirst().first {
                        return String(inner)
                    }
                }
                return nextLabel
            }()
            if let links = try? doc.select("a") {
                for link in links {
                    let label = (try? link.text()) ?? ""
                    guard label.contains(keyword) else { continue }
                    let href = ((try? link.attr("href")) ?? "")
                        .trimmingCharacters(in: .whitespaces)
                    if !href.isEmpty, href != "#", !href.hasPrefix("javascript:") {
                        return href
                    }
                }
            }
            return nil
        }
        let href = readFromDocument(doc, rule: raw)
        return href.isEmpty ? nil : href
    }

}
