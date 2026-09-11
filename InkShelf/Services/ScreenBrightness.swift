import UIKit

enum ScreenBrightness {
    private static var saved: CGFloat?

    static func apply(followSystem: Bool, value: Double) {
        #if canImport(UIKit)
        DispatchQueue.main.async {
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
        }
        #endif
    }

    static func restoreIfNeeded() {
        DispatchQueue.main.async {
            if let saved {
                UIScreen.main.brightness = saved
                self.saved = nil
            }
        }
    }
}
