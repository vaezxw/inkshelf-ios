import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var prefs: ReaderPrefs
    @Environment(\.modelContext) private var context
    @Query private var books: [BookEntity]
    @Query private var sources: [BookSourceEntity]
    @State private var repairing = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("版本", value: "1.0.0")
                    LabeledContent("系统适配", value: "iOS 26 Liquid Glass")
                    LabeledContent("书架", value: "\(books.count) 本")
                    LabeledContent("书源", value: "\(sources.count) 个")
                } header: {
                    Text("墨架 · InkShelf")
                } footer: {
                    Text("本地阅读为主；书源规则不支持完整 Legado JS。界面在 iOS 26 上启用系统 Liquid Glass，更早系统回退到材质毛玻璃。")
                }

                Section("阅读默认") {
                    Picker("模式", selection: $prefs.readMode) {
                        ForEach(ReadMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    HStack {
                        Text("字号 \(Int(prefs.fontSize))")
                        Slider(value: $prefs.fontSize, in: 14...28, step: 1)
                    }
                    HStack {
                        Text("行距 \(String(format: "%.1f", prefs.lineHeight))")
                        Slider(value: $prefs.lineHeight, in: 1.2...2.2, step: 0.1)
                    }
                    Picker("主题", selection: $prefs.themeMode) {
                        ForEach(ReaderThemeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }

                Section("自动阅读 / 亮度") {
                    Toggle("自动翻页", isOn: $prefs.autoReadEnabled)
                    if prefs.autoReadEnabled {
                        HStack {
                            Text("速度 \(String(format: "%.1f", prefs.autoReadSpeed))x")
                            Slider(value: $prefs.autoReadSpeed, in: 0.4...3.0, step: 0.1)
                        }
                    }
                    Toggle("亮度跟随系统", isOn: $prefs.followSystemBrightness)
                    if !prefs.followSystemBrightness {
                        HStack {
                            Text("\(Int(prefs.brightness * 100))%")
                            Slider(value: $prefs.brightness, in: 0.05...1.0)
                        }
                    }
                }

                Section("维护") {
                    Button {
                        Task { await repairEncodings() }
                    } label: {
                        if repairing {
                            ProgressView()
                        } else {
                            Text("修复本地书乱码（GBK）")
                        }
                    }
                    .disabled(repairing)
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("关于与声明") {
                    Text("Windows 可编辑源码；需在 macOS / Codemagic 编译。未签名 IPA 仅供个人学习与测试，请遵守当地法律与版权规定。完整免责声明见仓库 README。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .inkShelfScreenBackground()
            .navigationTitle("设置")
        }
    }

    private func repairEncodings() async {
        repairing = true
        defer { repairing = false }
        var n = 0
        for book in books where !book.isRemote {
            do {
                try await LibraryService.repairEncodingIfNeeded(book: book, context: context)
                n += 1
            } catch {
                // continue
            }
        }
        message = "已检查 \(n) 本本地书"
    }
}
