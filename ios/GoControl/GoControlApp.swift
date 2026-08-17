import SwiftUI

@main
struct GoControlApp: App {
    @StateObject private var ble = BleClient()

    @State private var dark = true                              // dark by default
    @State private var accent = Palette.accentChoices[0]
    @State private var compact = false

    var body: some Scene {
        WindowGroup {
            GoTheme(dark: dark, accent: accent) {
                AppRoot(
                    ble: ble,
                    dark: $dark,
                    accent: $accent,
                    compact: $compact
                )
            }
            .preferredColorScheme(dark ? .dark : .light)
        }
    }
}
