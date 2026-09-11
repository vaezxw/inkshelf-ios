import SwiftUI

/// 墨架色彩：纸感阅读色 + iOS 26 Liquid Glass 环境色。
enum InkShelfColors {
    // MARK: - Reading paper (日间)

    static let paper = Color(red: 0xE8 / 255, green: 0xE4 / 255, blue: 0xDC / 255)
    static let ink = Color(red: 0x1A / 255, green: 0x23 / 255, blue: 0x32 / 255)
    static let inkMuted = Color(red: 0x5C / 255, green: 0x65 / 255, blue: 0x70 / 255)
    static let rule = Color(red: 0xC9 / 255, green: 0xC2 / 255, blue: 0xB6 / 255)
    static let lamp = Color(red: 0xC4 / 255, green: 0x5C / 255, blue: 0x26 / 255)
    static let onLamp = Color(red: 1, green: 0xF8 / 255, blue: 0xF2 / 255)

    // MARK: - Night

    static let nightPaper = Color(red: 0x12 / 255, green: 0x16 / 255, blue: 0x1C / 255)
    static let nightInk = Color(red: 0xD5 / 255, green: 0xD0 / 255, blue: 0xC6 / 255)
    static let nightMuted = Color(red: 0x8A / 255, green: 0x85 / 255, blue: 0x80 / 255)
    static let nightRule = Color(red: 0x2A / 255, green: 0x30 / 255, blue: 0x38 / 255)
    static let nightLamp = Color(red: 0xE0 / 255, green: 0x8A / 255, blue: 0x4D / 255)
    static let onNightLamp = Color(red: 0x1A / 255, green: 0x12 / 255, blue: 0x0C / 255)

    // MARK: - Liquid Glass ambient (供玻璃折射采样)

    static let glassBase = Color(red: 0xF2 / 255, green: 0xEF / 255, blue: 0xE8 / 255)
    static let glassOrbWarm = Color(red: 0xE8 / 255, green: 0xA0 / 255, blue: 0x6B / 255).opacity(0.45)
    static let glassOrbCool = Color(red: 0x7A / 255, green: 0x9B / 255, blue: 0xB8 / 255).opacity(0.38)
    static let glassOrbInk = Color(red: 0x3D / 255, green: 0x4A / 255, blue: 0x5C / 255).opacity(0.22)
    static let glassHighlight = Color.white.opacity(0.55)
}
