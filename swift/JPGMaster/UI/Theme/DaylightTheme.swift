import SwiftUI

/// Color tokens for the Daylight Mix theme.
enum Theme {
    static let bg          = Color(hex: 0xEEF0F4)
    static let panel       = Color.white
    static let panel2      = Color(hex: 0xF6F7FA)
    static let border      = Color.black.opacity(0.07)
    static let borderStrong = Color.black.opacity(0.12)

    static let text      = Color(hex: 0x1A1D29)
    static let textDim   = Color(hex: 0x6B7180)
    static let textFaint = Color(hex: 0x9AA0B0)

    static let cyan       = Color(hex: 0x1AA9C2)
    static let cyanSoft   = Color(hex: 0x1AA9C2).opacity(0.10)
    static let yellow     = Color(hex: 0xD99A07)
    static let yellowSoft = Color(hex: 0xD99A07).opacity(0.10)
    static let purple     = Color(hex: 0x9762D6)
    static let purpleSoft = Color(hex: 0x9762D6).opacity(0.10)

    static let green = Color(hex: 0x3AA86B)

    /// Per-extension chip palette (PNG/TIFF → purple, JPG/JPEG → yellow, JXL → cyan).
    static func extColor(_ ext: String) -> (bg: Color, fg: Color, dot: Color) {
        switch ext.lowercased() {
        case "png", "tif", "tiff":
            return (Color(hex: 0xC89BF5).opacity(0.18), Color(hex: 0x9762D6), Color(hex: 0xC89BF5))
        case "jpg", "jpeg":
            return (Color(hex: 0xF5C542).opacity(0.20), Color(hex: 0xC79520), Color(hex: 0xF5C542))
        case "jxl":
            return (Color(hex: 0x5DD6E8).opacity(0.20), cyan, Color(hex: 0x5DD6E8))
        default:
            return (Color.black.opacity(0.04), textDim, textDim)
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >>  8) & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

extension Font {
    static let dlMono     = Font.system(.caption, design: .monospaced)
    static let dlMonoSmall = Font.system(size: 11, design: .monospaced)
    static let dlMonoTiny  = Font.system(size: 10.5, design: .monospaced)
}
