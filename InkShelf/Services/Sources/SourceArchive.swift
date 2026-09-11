import Foundation
import ZIPFoundation

enum SourceImportValue: Sendable {
    case text(String)
    case data(Data)
}

enum SourceArchive {
    static func isZip(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data[0] == 0x50 && data[1] == 0x4B
            && (data[2] == 0x03 || data[2] == 0x05 || data[2] == 0x07)
    }

    /// Extract text payloads (.plist / .json / .txt / .xml) from a zip archive.
    static func extractTexts(_ data: Data) throws -> [String] {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("inkshelf-zip-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let zipURL = root.appendingPathComponent("sources.zip")
        try data.write(to: zipURL, options: .atomic)
        let unpack = root.appendingPathComponent("unpacked", isDirectory: true)
        try fm.createDirectory(at: unpack, withIntermediateDirectories: true)
        do {
            try fm.unzipItem(at: zipURL, to: unpack)
        } catch {
            throw SourceError.format("无法解压 zip：\(error.localizedDescription)")
        }

        var files: [URL] = []
        if let enumerator = fm.enumerator(at: unpack, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                let path = url.path.lowercased()
                if path.contains("__macosx") { continue }
                let name = url.lastPathComponent.lowercased()
                if name.hasPrefix(".") { continue }
                let ext = url.pathExtension.lowercased()
                guard ["plist", "json", "txt", "xml"].contains(ext) else { continue }
                files.append(url)
            }
        }
        files.sort { $0.path < $1.path }

        var texts: [String] = []
        for url in files {
            let fileData = try Data(contentsOf: url)
            let text = (String(data: fileData, encoding: .utf8) ?? NovelTextDecoder.decode(fileData))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { texts.append(text) }
        }
        if texts.isEmpty {
            throw SourceError.format("压缩包内没有 plist / JSON 书源文件")
        }
        return texts
    }
}
