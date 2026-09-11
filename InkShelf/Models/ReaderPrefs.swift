import Foundation
import Combine

extension Notification.Name {
    static let inkshelfPrefsChanged = Notification.Name("inkshelf.prefs.changed")
}

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
        didSet {
            UserDefaults.standard.set(readMode.rawValue, forKey: Keys.readMode)
            bumpUpdatedAt()
        }
    }
    @Published var fontSize: Double {
        didSet {
            UserDefaults.standard.set(fontSize, forKey: Keys.fontSize)
            bumpUpdatedAt()
        }
    }
    @Published var lineHeight: Double {
        didSet {
            UserDefaults.standard.set(lineHeight, forKey: Keys.lineHeight)
            bumpUpdatedAt()
        }
    }
    @Published var themeMode: ReaderThemeMode {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: Keys.themeMode)
            bumpUpdatedAt()
        }
    }
    @Published var autoReadEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoReadEnabled, forKey: Keys.autoReadEnabled)
            bumpUpdatedAt()
        }
    }
    @Published var autoReadSpeed: Double {
        didSet {
            UserDefaults.standard.set(autoReadSpeed, forKey: Keys.autoReadSpeed)
            bumpUpdatedAt()
        }
    }
    @Published var followSystemBrightness: Bool {
        didSet {
            UserDefaults.standard.set(followSystemBrightness, forKey: Keys.followSystemBrightness)
            bumpUpdatedAt()
        }
    }
    @Published var brightness: Double {
        didSet {
            UserDefaults.standard.set(brightness, forKey: Keys.brightness)
            bumpUpdatedAt()
        }
    }

    /// Used for cloud LWW; not published to avoid update loops.
    var updatedAt: Date {
        get { UserDefaults.standard.object(forKey: Keys.updatedAt) as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: Keys.updatedAt) }
    }

    private var suppressBump = false

    private enum Keys {
        static let readMode = "inkshelf.readMode"
        static let fontSize = "inkshelf.fontSize"
        static let lineHeight = "inkshelf.lineHeight"
        static let themeMode = "inkshelf.themeMode"
        static let autoReadEnabled = "inkshelf.autoReadEnabled"
        static let autoReadSpeed = "inkshelf.autoReadSpeed"
        static let followSystemBrightness = "inkshelf.followSystemBrightness"
        static let brightness = "inkshelf.brightness"
        static let updatedAt = "inkshelf.prefs.updatedAt"
    }

    private init() {
        let defaults = UserDefaults.standard
        suppressBump = true
        readMode = ReadMode(rawValue: defaults.string(forKey: Keys.readMode) ?? "") ?? .pageFlip
        fontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 18
        lineHeight = defaults.object(forKey: Keys.lineHeight) as? Double ?? 1.7
        themeMode = ReaderThemeMode(rawValue: defaults.string(forKey: Keys.themeMode) ?? "") ?? .system
        autoReadEnabled = defaults.bool(forKey: Keys.autoReadEnabled)
        autoReadSpeed = defaults.object(forKey: Keys.autoReadSpeed) as? Double ?? 1.0
        followSystemBrightness = defaults.object(forKey: Keys.followSystemBrightness) as? Bool ?? true
        brightness = defaults.object(forKey: Keys.brightness) as? Double ?? 0.6
        suppressBump = false
    }

    private func bumpUpdatedAt() {
        guard !suppressBump else { return }
        updatedAt = .now
        NotificationCenter.default.post(name: .inkshelfPrefsChanged, object: nil)
    }

    func applyFromCloud(
        readMode: ReadMode,
        fontSize: Double,
        lineHeight: Double,
        themeMode: ReaderThemeMode,
        autoReadEnabled: Bool,
        autoReadSpeed: Double,
        followSystemBrightness: Bool,
        brightness: Double,
        updatedAt: Date
    ) {
        suppressBump = true
        self.readMode = readMode
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.themeMode = themeMode
        self.autoReadEnabled = autoReadEnabled
        self.autoReadSpeed = autoReadSpeed
        self.followSystemBrightness = followSystemBrightness
        self.brightness = brightness
        suppressBump = false
        self.updatedAt = updatedAt
    }
}
