import SwiftUI

/// Port of the `ConnectScreen` composable. The scanning ripples run off
/// TimelineView(.animation) rather than rememberInfiniteTransition; the found-pop uses a
/// spring on @State, matching the Animatable pair in the Kotlin original.
struct ConnectScreen: View {
    let state: BleClient.CamState
    let onRetry: () -> Void

    @Environment(\.palette) private var p

    @State private var camIn: Double = 0
    @State private var pop: Double = 1
    @State private var glow: Double = 0

    private var scanning: Bool { state.phase == .scanning }
    private var found: Bool {
        state.phase == .found || state.phase == .connecting || state.phase == .ready
    }
    private var failed: Bool { state.phase == .failed }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    if scanning {
                        ripples
                    }
                    if found {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [p.accent, .clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 75
                                )
                            )
                            .frame(width: 150, height: 150)
                            .opacity(glow * 0.32)
                    }
                    CameraGlyph(lensGlow: glow)
                        .frame(width: 74, height: 112)
                        .opacity(camIn)
                        .scaleEffect((0.94 + 0.06 * camIn) * pop)
                }
                .frame(width: 230, height: 230)

                Spacer().frame(height: 10)

                Text(head)
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundStyle(p.ink)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 6)

                Text(sub)
                    .font(.system(size: 13.5))
                    .foregroundStyle(p.muted)
                    .multilineTextAlignment(.center)

                if failed {
                    Spacer().frame(height: 22)
                    PillButton(title: "Try again", fullWidth: false, onTap: onRetry)
                }
            }
            .padding(.horizontal, 32)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7)) { camIn = 1 }
        }
        .onChange(of: found) { _, isFound in
            guard isFound else { return }
            glow = 1
            withAnimation(.easeInOut(duration: 0.22)) { pop = 1.07 }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.45).delay(0.22)) { pop = 1.0 }
            withAnimation(.easeInOut(duration: 0.9)) { glow = 0.25 }
        }
    }

    // three expanding rings, 2.4 s per cycle, offset by a third each
    private var ripples: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = (t / 2.4).truncatingRemainder(dividingBy: 1)
                let base = min(size.width, size.height) * 0.21
                for k in 0 ..< 3 {
                    let f = (phase + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                    let rad = base * (1 + f * 1.4)
                    let rect = CGRect(
                        x: size.width / 2 - rad,
                        y: size.height / 2 - rad,
                        width: rad * 2,
                        height: rad * 2
                    )
                    ctx.stroke(
                        Path(ellipseIn: rect),
                        with: .color(p.accent.opacity((1 - f) * 0.5)),
                        lineWidth: 1.6
                    )
                }
            }
        }
    }

    private var head: String {
        if failed { return state.message ?? "Not connected" }
        if state.phase == .ready { return "Connected" }
        if found { return state.name ?? "Camera found" }
        return "Looking for your camera"
    }

    private var sub: String {
        if failed { return "Make sure the camera is awake and Bluetooth is on" }
        if state.phase == .ready {
            var s = state.battery.map { "Battery \($0)%" } ?? "Ready"
            if let free = state.freeBytes {
                s += String(format: " · %.1f GB free", Double(free) / 1e9)
            }
            return s
        }
        if found { return "Pairing over Bluetooth" }
        return "Keep it nearby"
    }
}
