import SwiftUI

enum MurzikPalette {
    // Fur: lifted a touch above pure black so the silhouette reads on the black island.
    static let furTop = Color(red: 0.20, green: 0.20, blue: 0.23)
    static let furMid = Color(red: 0.09, green: 0.09, blue: 0.10)
    static let furBottom = Color(red: 0.04, green: 0.04, blue: 0.05)
    /// Soft gray rim light that separates Murzik from dark backgrounds.
    static let rim = Color(red: 0.50, green: 0.50, blue: 0.56)
    /// Brighter rim for tiny Dynamic Island sizes on a pure-black background.
    static let rimBright = Color(red: 0.66, green: 0.66, blue: 0.72)
    static let innerEar = Color(red: 0.42, green: 0.25, blue: 0.31)

    // Eyes: classic black-cat amber center fading to yellow-green.
    static let eyeCenter = Color(red: 1.00, green: 0.80, blue: 0.25)
    static let eyeEdge = Color(red: 0.70, green: 0.88, blue: 0.22)
    static let closedEye = Color(red: 1.00, green: 0.78, blue: 0.30)

    static let nose = Color(red: 0.96, green: 0.56, blue: 0.64)
    static let mouth = Color(red: 0.72, green: 0.72, blue: 0.78)
    static let mouthInside = Color(red: 0.86, green: 0.36, blue: 0.47)
    static let tongue = Color(red: 1.00, green: 0.55, blue: 0.64)
    static let whisker = Color.white.opacity(0.6)
    static let blush = Color(red: 1.00, green: 0.45, blue: 0.58)
    static let heart = Color(red: 1.00, green: 0.36, blue: 0.52)

    // App chrome
    static let cream = Color(red: 0.98, green: 0.95, blue: 0.91)
    static let sand = Color(red: 0.94, green: 0.88, blue: 0.81)
    static let ink = Color(red: 0.14, green: 0.12, blue: 0.12)
    static let inkSoft = Color(red: 0.42, green: 0.38, blue: 0.36)
    static let amber = Color(red: 0.95, green: 0.64, blue: 0.20)
    static let mint = Color(red: 0.35, green: 0.75, blue: 0.55)
    static let sky = Color(red: 0.38, green: 0.56, blue: 0.95)

    static func accent(for mood: MurzikMood) -> Color {
        switch mood {
        case .loving: return heart
        case .hungry: return amber
        case .sleepy, .sleeping: return sky
        case .playful, .excited: return Color(red: 0.98, green: 0.78, blue: 0.20)
        case .happy: return Color(red: 1.0, green: 0.82, blue: 0.30)
        case .surprised: return Color(red: 1.0, green: 0.62, blue: 0.35)
        case .idle, .blinking: return eyeCenter
        }
    }
}
