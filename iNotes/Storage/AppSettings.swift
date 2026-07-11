import Foundation
import CoreGraphics

/// Single source of truth for the editor's base font size, persisted in
/// `UserDefaults`. Everything that used to hardcode `13` (body text, heading
/// sizes, the checkbox box) derives from this instead.
enum AppSettings {
    static let fontSizeRange: ClosedRange<CGFloat> = 10...24
    static let defaultFontSize: CGFloat = 13

    private static let fontSizeKey = "editorFontSize"

    /// Clamp `value` into `fontSizeRange`. Pure — used both when reading a
    /// persisted value (in case a future/foreign build wrote something out of
    /// range) and when writing a new one.
    static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }

    /// Read the persisted base font size from `defaults`, or `defaultFontSize`
    /// if nothing's been saved yet. Always clamped.
    static func baseFontSize(in defaults: UserDefaults) -> CGFloat {
        let stored = defaults.object(forKey: fontSizeKey) as? Double
        return clamp(CGFloat(stored ?? Double(defaultFontSize)))
    }

    /// Persist `value` (clamped) as the base font size in `defaults`.
    static func setBaseFontSize(_ value: CGFloat, in defaults: UserDefaults) {
        defaults.set(Double(clamp(value)), forKey: fontSizeKey)
    }

    /// Convenience over `UserDefaults.standard` — the one every call site in
    /// the app actually wants; tests use the `(in:)` variants above with an
    /// isolated `UserDefaults` suite instead.
    static var baseFontSize: CGFloat {
        get { baseFontSize(in: .standard) }
        set { setBaseFontSize(newValue, in: .standard) }
    }
}
