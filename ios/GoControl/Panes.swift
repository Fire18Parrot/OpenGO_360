import SwiftUI

// ------------------------------------------------------------------ control
struct ControlPane: View {
    let ble: BleClient
    let state: BleClient.CamState
    @Binding var limitMin: Int
    let gap: CGFloat

    @Environment(\.palette) private var p

    private var recording: Bool { state.captureState != "idle" }
    private var elapsed: UInt64 { state.captureTime ?? 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: gap) {
                hero
                telemetry
                clipLength
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 20)
        }
    }

    // ---- hero ----
    private var hero: some View {
        CardBox {
            HStack(spacing: 0) {
                Circle()
                    .fill(recording ? p.tally : p.raise)
                    .frame(width: 10, height: 10)
                Spacer().frame(width: 13)
                Text(fmtClock(elapsed))
                    .font(.system(size: 48, weight: .heavy))
                    .foregroundStyle(p.ink)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    LabelText("Stops at")
                    Text(String(format: "%02d:00", limitMin))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(p.ink)
                }
            }

            Spacer().frame(height: 20)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.sunk)
                    Capsule()
                        .fill(recording ? p.tally : p.accent)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 8)

            Spacer().frame(height: 9)

            HStack {
                Text("0:00").font(.system(size: 11.5)).foregroundStyle(p.muted)
                Spacer()
                Text(String(format: "%02d:00", limitMin))
                    .font(.system(size: 11.5)).foregroundStyle(p.muted)
            }

            Spacer().frame(height: 20)

            HStack {
                ActionCircle(
                    glyph: recording ? "■" : "●",
                    label: recording ? "Stop" : "Record",
                    tint: p.tally
                ) {
                    ble.send(recording ? GoCore.cmdStopCapture() : GoCore.cmdStartCapture())
                }
                Spacer()
                ActionCircle(glyph: "◉", label: "Photo", enabled: !recording) {
                    ble.send(GoCore.cmdTakePicture())
                }
                Spacer()
                ActionCircle(glyph: "◔", label: "Timelapse", enabled: !recording) {
                    ble.send(GoCore.cmdStartTimelapse())
                }
                Spacer()
                ActionCircle(glyph: "◍", label: "Bullet", enabled: !recording) {
                    ble.send(GoCore.cmdStartBulletTime())
                }
            }
        }
    }

    private var progress: Double {
        guard limitMin > 0 else { return 0 }
        return min(max(Double(elapsed) / (Double(limitMin) * 60), 0), 1)
    }

    // ---- telemetry ----
    private var telemetry: some View {
        CardBox {
            LabelText("Camera")
            Spacer().frame(height: 14)
            HStack(spacing: 9) {
                TeleTile(
                    key: "Battery",
                    value: String(state.battery ?? 0),
                    unit: "%",
                    frac: Double(state.battery ?? 0) / 100,
                    barColor: p.good,
                    warn: (state.battery ?? 100) <= 15
                )
                TeleTile(
                    key: "Free",
                    value: String(format: "%.1f", freeGb),
                    unit: "GB",
                    frac: freeGb / max(totalGb, 0.001),
                    barColor: p.accent,
                    warn: false
                )
                // TemperatureState (Normal/Alert/Warm/Hot), not degrees — the camera
                // never reports a °C figure.
                TeleTile(
                    key: "Temp",
                    value: state.tempState ?? "—",
                    unit: "",
                    frac: Double(state.tempLevel ?? 0) / 3,
                    barColor: p.amber,
                    warn: (state.tempLevel ?? 0) >= 2
                )
            }
        }
    }

    private var freeGb: Double { Double(state.freeBytes ?? 0) / 1e9 }
    private var totalGb: Double { Double(state.totalBytes ?? 0) / 1e9 }

    // ---- clip length ----
    private var clipLength: some View {
        CardBox {
            LabelText("Clip length")
            Spacer().frame(height: 14)

            HStack(spacing: 11) {
                RoundBtn(glyph: "−") {
                    limitMin = max(limitMin - (limitMin <= 5 ? 1 : 5), 1)
                }
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    Text("\(limitMin)")
                        .font(.system(size: 25, weight: .heavy))
                        .foregroundStyle(p.ink)
                    Text("min")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(p.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(p.sunk)
                .clipShape(Capsule())

                RoundBtn(glyph: "+") {
                    limitMin = min(limitMin + (limitMin < 5 ? 1 : 5), 180)
                }
            }

            Spacer().frame(height: 11)

            HStack(spacing: 8) {
                ForEach([1, 5, 10, 20], id: \.self) { m in
                    let on = m == limitMin
                    Button {
                        limitMin = m
                    } label: {
                        Text(String(format: "%d:00", m))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(on ? Color.white : p.dim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(on ? p.accent : p.sunk)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer().frame(height: 13)

            PillButton(title: "Apply to camera") {
                ble.send(GoCore.cmdSetRecordDuration(ms: UInt64(limitMin) * 60_000))
            }

            Spacer().frame(height: 10)

            Text("About 22 min of footage fits on the 8 GB.")
                .font(.system(size: 12.5))
                .foregroundStyle(p.muted)
        }
    }
}

// ------------------------------------------------------------------ files
struct FilesPane: View {
    @Environment(\.palette) private var p

    var body: some View {
        ScrollView {
            CardBox {
                LabelText("On the camera")
                Spacer().frame(height: 10)
                Text(
                    "File listing over Bluetooth is not wired up yet. Copy clips off with a "
                    + "USB cable — the camera mounts as a drive."
                )
                .font(.system(size: 13.5))
                .foregroundStyle(p.dim)
            }
            .padding(.horizontal, 14)
        }
    }
}

// ------------------------------------------------------------------ activity
struct ActivityPane: View {
    let lines: [String]
    @Environment(\.palette) private var p

    var body: some View {
        ScrollView {
            CardBox {
                LabelText("Activity")
                Spacer().frame(height: 10)
                if lines.isEmpty {
                    Text("Nothing yet.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(p.muted)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                        Text(l)
                            .font(.system(size: 13.5))
                            .foregroundStyle(p.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 5)
                    }
                }
            }
            .padding(.horizontal, 14)
        }
    }
}

// ------------------------------------------------------------------ settings
struct SettingsSheet: View {
    @Binding var dark: Bool
    @Binding var accent: Color
    @Binding var compact: Bool
    let onDisconnect: () -> Void

    @Environment(\.palette) private var p

    var body: some View {
        ScrollView {
            // Kept as a handful of sections rather than one flat list: ViewBuilder only
            // accepts 10 direct children.
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(p.ink)
                    .padding(.bottom, 20)

                accentSection
                themeSection
                spacingSection

                PillButton(title: "Disconnect", background: p.sunk, foreground: p.ink) {
                    onDisconnect()
                }
                .padding(.top, 26)
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 30)
        }
        .background(p.card)
    }

    private var accentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabelText("Accent")
            HStack(spacing: 11) {
                ForEach(Array(Palette.accentChoices.enumerated()), id: \.offset) { _, c in
                    Button {
                        accent = c
                    } label: {
                        ZStack {
                            Circle().fill(c)
                            if c == accent {
                                Text("✓")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabelText("Theme")
            Seg(options: ["Dark", "Light"], selected: dark ? 0 : 1) { dark = ($0 == 0) }
        }
        .padding(.top, 22)
    }

    private var spacingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabelText("Spacing")
            Seg(options: ["Cosy", "Compact"], selected: compact ? 1 : 0) { compact = ($0 == 1) }
        }
        .padding(.top, 22)
    }
}
