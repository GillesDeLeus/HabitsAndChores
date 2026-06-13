import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Thin wrapper around the system haptic generators, no-op where unavailable.
enum Haptics {
    static func celebrate() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #endif
    }

    static func tap() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
