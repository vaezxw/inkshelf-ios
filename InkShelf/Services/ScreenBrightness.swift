import UIKit

@MainActor
enum ScreenBrightness {
    private static var saved: CGFloat?

    static func apply(followSystem: Bool, value: Double) {
        #if canImport(UIKit)
        if followSystem {
            if let saved {
                UIScreen.main.brightness = saved
                self.saved = nil
            }
        } else {
            if saved == nil {
                saved = UIScreen.main.brightness
            }
            UIScreen.main.brightness = CGFloat(min(max(value, 0.05), 1.0))
        }
        #endif
    }

    static func restoreIfNeeded() {
        if let saved {
            UIScreen.main.brightness = saved
            self.saved = nil
        }
    }
}
