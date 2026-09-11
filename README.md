# InkShelf · 墨架（原生 iOS）

SwiftUI + SwiftData 本地小说阅读器，面向 **iOS 26 Liquid Glass（液态玻璃）** 视觉语言适配。仅支持 iOS。

> **重要**：本项目为个人学习 / 技术研究用途的开源示例。使用、编译、分发或侧载安装前，请务必完整阅读下方 [免责声明](#免责声明disclaimer) 与 [DISCLAIMER.md](./DISCLAIMER.md)。

---

## 项目简介

| 项 | 说明 |
|----|------|
| 名称 | InkShelf（墨架） |
| 平台 | iOS（iPhone / iPad） |
| UI | SwiftUI；**iOS 26+** 使用系统 `glassEffect` / `GlassEffectContainer` / `.glass` 按钮样式 |
| 数据 | SwiftData + 本地 Documents |
| 最低部署 | iOS 17.0（更早系统自动回退到 `ultraThinMaterial` 毛玻璃，不崩溃） |
| 推荐设备 | 已升级到 **iOS 26** 的真机（体验完整 Liquid Glass） |

墨架帮助你在手机上管理本地 TXT 小说、分页阅读、听书，并支持导入部分 Legado 风格书源做搜索（**不支持完整 Legado JS 规则**）。

---

## iOS 26 玻璃态适配说明

本仓库按 Apple 在 iOS 26 引入的 **Liquid Glass** 设计语言做了界面适配，而不是简单的「假毛玻璃截图风格」：

1. **系统 API**：在可用时调用 `View.glassEffect`、`GlassEffectContainer`、`ButtonStyle.glass` / `.glassProminent`。
2. **Tab 栏**：iOS 26 使用新的 `Tab { }` API，并启用 `tabBarMinimizeBehavior(.onScrollDown)`。
3. **搜索栏**：书架搜索启用 `searchToolbarBehavior(.minimizable)`（iOS 26）。
4. **环境底色**：`GlassAmbientBackground` 提供柔和光斑，便于玻璃层折射采样。
5. **兼容回退**：所有玻璃相关修饰集中在 `InkShelf/Theme/LiquidGlass.swift`，通过 `#available(iOS 26, *)` 在旧系统回退到材质。

> 声明：Liquid Glass /「玻璃态」效果为 Apple 系统能力与设计语言的一部分。本项目**并非** Apple 官方产品，也**未获得** Apple 背书；API 行为可能随系统版本变化，请以你本机 Xcode SDK 与真机为准。

相关主题代码：

- `InkShelf/Theme/LiquidGlass.swift` — 玻璃修饰与回退
- `InkShelf/Theme/InkShelfColors.swift` — 纸感色 + 玻璃环境色
- `InkShelf/App/RootTabView.swift` — Tab / Liquid Glass Tab 栏
- 书架、书源、设置、阅读器顶栏/底栏等界面均已接入

---

## 功能对照

| 模块 | 能力 |
|------|------|
| 书架 | 导入 TXT（UTF-8/GBK）、分章、网格搜索、详情、进度、删除 |
| 阅读 | 左右翻页 / 上下滚动、边滑切章、目录书签、字号行距、纸面/夜间 |
| 听书等 | `AVSpeechSynthesizer`、自动翻页、屏幕亮度 |
| 书源 | Legado JSON / 简单 plist、启用管理、并行搜索、加入书架、TOC/正文缓存、导出/清空 |
| 设置 | 与阅读偏好对齐；本地书乱码修复 |
| UI | iOS 26 Liquid Glass；旧系统材质回退 |

**明确不做**：完整 Legado JS；iCloud 同步；Android / Web；App Store 上架支持。

---

## 开发环境

- 源码可在 **Windows** 编辑（本仓库即按此工作流维护）
- **编译**需 macOS：本机 Xcode（建议带 **iOS 26 SDK**），或 [Codemagic](https://codemagic.io) 云构建
- 依赖：[XcodeGen](https://github.com/yonaskolb/XcodeGen)、SwiftSoup（SPM）

```bash
# 在 macOS / Codemagic
brew install xcodegen
xcodegen generate
open InkShelf.xcodeproj
```

本地未签名构建：

```bash
chmod +x scripts/build-local.sh
./scripts/build-local.sh
```

---

## Codemagic 出未签名 IPA

1. 将本仓库推到 GitHub，在 Codemagic 添加应用并选用 `codemagic.yaml`
2. 跑 workflow **`iOS Unsigned IPA (Sideloadly)`**（`ios-unsigned-ipa`）
3. 确认产物 `build/ipa/InkShelf-unsigned.ipa` 可下载
4. 用 [Sideloadly](https://sideloadly.io) 等工具装到 iPhone（免费个人签名通常约 7 天；到期需重签）

**侧载风险由你自行承担**，详见免责声明。

---

## 存储

- **SwiftData**：书 / 章节索引 / 书签 / 书源
- **Documents**：`inkshelf/books/{id}/content.txt` 与 `cache/*.txt`
- **UserDefaults**：阅读偏好（字号、模式、主题、自动读、亮度）

---

## 测试

```bash
xcodegen generate
xcodebuild test -project InkShelf.xcodeproj -scheme InkShelf -destination 'platform=iOS Simulator,name=iPhone 16'
```

覆盖分章、解码、分页、书源 JS 跳过启发式（见 `InkShelfTests`）。在 iOS 26 模拟器 / 真机上请额外目视检查玻璃控件与 Tab 栏。

---

## 仓库结构（摘要）

```
InkShelf/
  App/           入口与根 Tab
  Features/      书架 / 阅读 / 书源 / 设置
  Theme/         色彩 + Liquid Glass 适配层
  Services/      导入、分章、书源引擎、朗读等
  Models/        SwiftData 与偏好
InkShelfTests/   核心逻辑单测
scripts/         本地构建脚本
codemagic.yaml   云构建
project.yml      XcodeGen 工程描述
DISCLAIMER.md    完整法律免责声明（请细读）
```

---

## 免责声明（Disclaimer）

**使用本软件即表示你已阅读、理解并同意以下全部条款。若不同意，请立即停止下载、编译、安装或使用。**

更完整、更具约束力的文本见 **[DISCLAIMER.md](./DISCLAIMER.md)**。摘要如下：

1. **非官方**：本项目与 Apple Inc.、App Store、Legado 或其他第三方书源/阅读器**无任何隶属、授权或合作关系**。「Liquid Glass / iOS 26 玻璃态」仅为对公开系统 API 与设计趋势的技术适配描述，不代表商标授权。
2. **按现状提供（AS IS）**：软件不提供任何明示或暗示担保，包括但不限于适销性、特定用途适用性、不侵权、持续可用或与未来 iOS / Xcode 版本兼容。
3. **责任限制**：作者与贡献者不对因使用本软件导致的任何直接、间接、附带、特殊、惩罚性或后果性损害负责，包括但不限于设备变砖、数据丢失、账号封禁、应用无法安装、系统不稳定、法律纠纷等。
4. **版权与内容合规**：你必须自行确保导入的 TXT、通过书源获取的内容已获合法授权或属于你有权使用的材料。本项目**不提供**任何盗版、侵权内容，也不鼓励绕过版权保护或网站服务条款。因内容合规产生的一切法律责任由使用者自行承担。
5. **网络安全与书源**：书源规则可能指向第三方网站。启用 `NSAllowsArbitraryLoads` 等配置仅为兼容部分站点；你应自行评估隐私、钓鱼、恶意脚本与中间人风险。作者不对第三方站点内容或安全性负责。
6. **侧载与签名**：通过 Sideloadly 等工具安装未签名 / 个人签名 IPA 可能违反设备厂商政策、企业规定或当地法规；可能导致系统警告、证书吊销、功能受限。请仅在你拥有完全控制权且合法的前提下操作。
7. **非医疗 / 非关键用途**：朗读、亮度调节等功能不得用于任何安全关键或医疗场景。
8. **开源许可与贡献**：若未另行声明许可证，默认仅供个人学习参考；二次分发前请自行确认合规。提交 PR 即表示你保证拥有贡献代码的权利且内容不侵权。

**再次强调：本 README 与 DISCLAIMER.md 不构成法律意见。如有疑问，请咨询具备资质的专业法律人士。**

---

## License / 许可

若仓库根目录未附带独立 LICENSE 文件，则本代码默认仅供**个人学习与研究**；未经权利人书面许可，请勿将其用于商业产品或公开分发侵权内容。建议在正式对外开源前补充 SPDX 许可证（例如 MIT / Apache-2.0）并与本免责声明一并保留。
