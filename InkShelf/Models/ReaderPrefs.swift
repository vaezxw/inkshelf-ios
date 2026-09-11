import Foundation
import Combine

enum BookOrigin: String, Codable, CaseIterable {
    case local
    case remote
}

enum ReadMode: String, CaseIterable, Identifiable {
    case pageFlip
    case verticalScroll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pageFlip: "左右翻页（滑到边切章）"
        case .verticalScroll: "上下滚动（左右滑切章）"
        }
    }
}

enum ReaderThemeMode: String, CaseIterable, Identifiable {
    case system
    case paper
    case night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .paper: "纸面"
        case .night: "夜间"
        }
    }
}

@MainActor
final class ReaderPrefs: ObservableObject {
    static let shared = ReaderPrefs()

    @Published var readMode: ReadMode {
        didSet { UserDefaults.standard.set(readMode.rawValue, forKey: Keys.readMode) }
    }
    @Published var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: Keys.fontSize) }
    }
    @Published var lineHeight: Double {
        didSet { UserDefaults.standard.set(lineHeight, forKey: Keys.lineHeight) }
    }
    @Published var themeMode: ReaderThemeMode {
        didSet { UserDefaults.standard.set(themeMode.rawValue, forKey: Keys.themeMode) }
    }
    @Published var autoReadEnabled: Bool {
        didSet { UserDefaults.standard.set(autoReadEnabled, forKey: Keys.autoReadEnabled) }
    }
    @Published var autoReadSpeed: Double {
        didSet { UserDefaults.standard.set(autoReadSpeed, forKey: Keys.autoReadSpeed) }
    }
    @Published var followSystemBrightness: Bool {
        didSet { UserDefaults.standard.set(followSystemBrightness, forKey: Keys.followSystemBrightness) }
    }
    @Published var brightness: Double {
        didSet { UserDefaults.standard.set(brightness, forKey: Keys.brightness) }
    }

    private enum Keys {
        static let readMode = "inkshelf.readMode"
        static let fontSize = "inkshelf.fontSize"
        static let lineHeight = "inkshelf.lineHeight"
        static let themeMode = "inkshelf.themeMode"
        static let autoReadEnabled = "inkshelf.autoReadEnabled"
        static let autoReadSpeed = "inkshelf.autoReadSpeed"
        static let followSystemBrightness = "inkshelf.followSystemBrightness"
        static let brightness = "inkshelf.brightness"
    }

    private init() {
        let defaults = UserDefaults.standard
        readMode = ReadMode(rawValue: defaults.string(forKey: Keys.readMode) ?? "") ?? .pageFlip
        fontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 18
        lineHeight = defaults.object(forKey: Keys.lineHeight) as? Double ?? 1.7
        themeMode = ReaderThemeMode(rawValue: defaults.string(forKey: Keys.themeMode) ?? "") ?? .system
        autoReadEnabled = defaults.bool(forKey: Keys.autoReadEnabled)
        autoReadSpeed = defaults.object(forKey: Keys.autoReadSpeed) as? Double ?? 1.0
        followSystemBrightness = defaults.object(forKey: Keys.followSystemBrightness) as? Bool ?? true
        brightness = defaults.object(forKey: Keys.brightness) as? Double ?? 0.6
    }
}
