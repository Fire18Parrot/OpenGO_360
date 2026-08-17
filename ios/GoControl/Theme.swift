import SwiftUI

// ----------------------------------------------------------------- palette
/// Mirrors the `Palette` data class in MainActivity.kt.
struct Palette {
    var bg: Color
    var card: Color
    var sunk: Color
    var raise: Color
    var ink: Color
    var dim: Color
    var muted: Color
    var accent: Color
    var tally: Color
    var good: Color
    var amber: Color

    func withAccent(_ c: Color) -> Palette {
        var copy = self
        copy.accent = c
        return copy
    }

    static let dark = Palette(
        bg: Color(hex: 0x0A0B0D), card: Color(hex: 0x15171B), sunk: Color(hex: 0x1D2026),
        raise: Color(hex: 0x23262D), ink: .white, dim: Color(hex: 0xA2A8B4),
        muted: Color(hex: 0x6E747F), accent: Color(hex: 0x3D7BFF), tally: Color(hex: 0xFF453A),
        good: Color(hex: 0x30D158), amber: Color(hex: 0xFFD426)
    )

    static let light = Palette(
        bg: Color(hex: 0xF2F1EE), card: .white, sunk: Color(hex: 0xF0EFEC),
        raise: Color(hex: 0xE8E7E3), ink: Color(hex: 0x0D0E10), dim: Color(hex: 0x5A5F68),
        muted: Color(hex: 0x8B9099), accent: Color(hex: 0x3D7BFF), tally: Color(hex: 0xE0362B),
        good: Color(hex: 0x1E9E4A), amber: Color(hex: 0xB8860B)
    )

    static let accentChoices: [Color] = [
        Color(hex: 0x3D7BFF), Color(hex: 0x8E5BFF), Color(hex: 0x30D158),
        Color(hex: 0xFF9F0A), Color(hex: 0xFF375F)
    ]
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}

// The SwiftUI stand-in for Compose's `staticCompositionLocalOf { DarkPalette }`.
private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.dark
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Equivalent of the `GoTheme` composable.
struct GoTheme<Content: View>: View {
    let dark: Bool
    let accent: Color
    @ViewBuilder var content: Content

    var body: some View {
        let base = (dark ? Palette.dark : Palette.light).withAccent(accent)
        content
            .environment(\.palette, base)
            .tint(accent)
    }
}

// ----------------------------------------------------------------- helpers
func fmtClock(_ seconds: UInt64) -> String {
    String(format: "%02d:%02d", seconds / 60, seconds % 60)
}
