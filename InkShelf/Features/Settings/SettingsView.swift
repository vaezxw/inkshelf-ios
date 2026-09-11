import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var prefs: ReaderPrefs
    @EnvironmentObject private var sync: SyncService
    @Environment(\.modelContext) private var context
    @Query private var books: [BookEntity]
    @Query private var sources: [BookSourceEntity]
    @State private var repairing = false
    @State private var message: String?

    @State private var apiBase = CloudConfig.apiBaseURL
    @State private var email = CloudAuthStore.email ?? ""
    @State private var otp = ""
    @State private var echoHint: String?
    @State private var authBusy = false

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
                    Text("本地优先；可选 Cloudflare 云同步。书源规则不支持完整 Legado JS。")
                }

                cloudSection

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
                    Text("Windows 可编辑源码；需在 macOS / Codemagic 编译。云同步后端见仓库 cloud/ 目录。完整免责声明见 README。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .inkShelfScreenBackground()
            .navigationTitle("设置")
            .onAppear {
                apiBase = CloudConfig.apiBaseURL
                email = CloudAuthStore.email ?? email
            }
        }
    }

    @ViewBuilder
    private var cloudSection: some View {
        Section {
            TextField("API 地址", text: $apiBase)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { CloudConfig.apiBaseURL = apiBase }
            Toggle("启用同步", isOn: Binding(
                get: { CloudConfig.syncEnabled },
                set: { CloudConfig.syncEnabled = $0 }
            ))
            Toggle("同步本地 TXT 到 R2", isOn: Binding(
                get: { CloudConfig.syncLocalTxt },
                set: { CloudConfig.syncLocalTxt = $0 }
            ))

            if CloudAuthStore.isLoggedIn {
                LabeledContent("账号", value: CloudAuthStore.email ?? "")
                if let last = CloudConfig.lastSyncAt {
                    LabeledContent("上次同步", value: last.formatted(date: .abbreviated, time: .shortened))
                }
                Button {
                    Task {
                        CloudConfig.apiBaseURL = apiBase
                        await sync.syncNow(context: context, forceFullPull: false)
                    }
                } label: {
                    if sync.isSyncing {
                        ProgressView()
                    } else {
                        Text("立即同步")
                    }
                }
                .disabled(sync.isSyncing)
                Button("退出登录", role: .destructive) {
                    sync.logout()
                }
            } else {
                TextField("邮箱", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                TextField("验证码", text: $otp)
                    .keyboardType(.numberPad)
                if let echoHint {
                    Text("开发回显验证码：\(echoHint)")
                        .font(.caption)
                        .foregroundStyle(InkShelfColors.lamp)
                }
                HStack {
                    Button("获取验证码") {
                        Task { await requestOTP() }
                    }
                    .disabled(authBusy || email.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("登录") {
                        Task { await login() }
                    }
                    .disabled(authBusy || email.isEmpty || otp.isEmpty)
                }
            }

            if let err = sync.lastError {
                Text(err).font(.footnote).foregroundStyle(.red)
            } else if let msg = sync.lastMessage {
                Text(msg).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("云同步（Cloudflare）")
        } footer: {
            Text("部署 cloud/ Worker 后填写 API 地址。开发模式 OTP_ECHO=true 时会回显验证码。未登录时完全本地运行。")
        }
    }

    private func requestOTP() async {
        authBusy = true
        defer { authBusy = false }
        CloudConfig.apiBaseURL = apiBase
        do {
            echoHint = try await sync.requestOTP(email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            if echoHint == nil {
                sync.lastMessage = "验证码已发送"
            }
        } catch {
            sync.lastError = error.localizedDescription
        }
    }

    private func login() async {
        authBusy = true
        defer { authBusy = false }
        CloudConfig.apiBaseURL = apiBase
        do {
            try await sync.login(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                code: otp.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            otp = ""
            echoHint = nil
            await sync.syncNow(context: context, forceFullPull: true)
        } catch {
            sync.lastError = error.localizedDescription
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
