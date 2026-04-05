import CoreGraphics
import Foundation
import CoreText

#if canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
#elseif canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
#endif

enum PlatformDrawing {
    nonisolated static func textColor(gray: CGFloat, alpha: CGFloat = 1) -> CGColor {
        PlatformColor(white: gray, alpha: alpha).cgColor
    }

    nonisolated static func monospacedFont(ofSize size: CGFloat) -> PlatformFont {
        #if canImport(AppKit)
        return PlatformFont.monospacedSystemFont(ofSize: size, weight: .medium)
        #else
        return PlatformFont.monospacedSystemFont(ofSize: size, weight: .medium)
        #endif
    }
}
