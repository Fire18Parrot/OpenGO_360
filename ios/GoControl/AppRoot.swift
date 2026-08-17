import SwiftUI

/// Port of `AppRoot` + `MainScaffold` from Ui.kt.
struct AppRoot: View {
    @ObservedObject var ble: BleClient
    @Binding var dark: Bool
    @Binding var accent: Color
    @Binding var compact: Bool

    @Environment(\.palette) private var p

    @State private var showApp = false

    private var ready: Bool { ble.state.phase == .ready }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()

            if !showApp {
                ConnectScreen(state: ble.state, onRetry: { ble.startScan() })
                    .transition(.opacity)
            } else {
                MainScaffold(
                    ble: ble,
                    dark: $dark,
                    accent: $accent,
                    compact: $compact
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: showApp)
        .onAppear { ble.startScan() }
        .onChange(of: ready) { _, isReady in
            if isReady {
                // hold the connect screen a beat after READY so the animation resolves
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    if ble.state.phase == .ready { showApp = true }
                }
            } else {
                showApp = false
            }
        }
    }
}

struct MainScaffold: View {
    @ObservedObject var ble: BleClient
    @Binding var dark: Bool
    @Binding var accent: Color
    @Binding var compact: Bool

    @Environment(\.palette) private var p

    @State private var tab = 0
    @State private var showSettings = false
    @State private var limitMin = 20

    private var gap: CGFloat { compact ? 9 : 12 }

    private let tabs: [(glyph: String, label: String)] = [
        ("◉", "Control"), ("▤", "Files"), ("≡", "Activity")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            // ---------------- panes ----------------
            ZStack {
                switch tab {
                case 0:
                    ControlPane(ble: ble, state: ble.state, limitMin: $limitMin, gap: gap)
                case 1:
                    FilesPane()
                default:
                    ActivityPane(lines: ble.logLines)
                }
            }
            .frame(maxHeight: .infinity)

            tabBar
        }
        .background(p.bg)
        .sheet(isPresented: $showSettings) {
            SettingsSheet(
                dark: $dark,
                accent: $accent,
                compact: $compact,
                onDisconnect: {
                    showSettings = false
                    ble.disconnect()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(26)
        }
    }

    // ---------------- header ----------------
    private var header: some View {
        HStack(spacing: 0) {
            ZStack {
                Circle().fill(p.raise)
                CameraGlyph().frame(width: 18, height: 27)
            }
            .frame(width: 42, height: 42)

            Spacer().frame(width: 12)

            VStack(alignment: .leading, spacing: 0) {
                Text(ble.state.name ?? "GO")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(p.ink)
                HStack(spacing: 6) {
                    Circle().fill(p.good).frame(width: 6, height: 6)
                    Text("Connected" + (ble.state.battery.map { " · \($0)%" } ?? ""))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(p.muted)
                }
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                ZStack {
                    Circle().fill(p.card)
                    Text("⚙").font(.system(size: 15)).foregroundStyle(p.ink)
                }
                .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    // ---------------- tabs ----------------
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { i, t in
                Button {
                    tab = i
                } label: {
                    VStack(spacing: 3) {
                        Text(t.glyph)
                            .font(.system(size: 18))
                        Text(t.label)
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(tab == i ? p.accent : p.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .background(p.card)
    }
}
