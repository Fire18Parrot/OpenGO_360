import SwiftUI

// ----------------------------------------------------------------- card / label
/// The `Card` composable from MainActivity.kt. Named CardBox to avoid colliding with
/// SwiftUI's own `Card`-ish containers and to keep the call sites obvious.
struct CardBox<Content: View>: View {
    @Environment(\.palette) private var p
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(p.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct LabelText: View {
    let text: String
    @Environment(\.palette) private var p

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(p.muted)
    }
}

// ----------------------------------------------------------------- camera glyph
struct CameraGlyph: View {
    var lensGlow: Double = 0
    @Environment(\.palette) private var p

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let bodyW = w * 0.76
            let bodyH = h * 0.93
            let left = (w - bodyW) / 2
            let top = (h - bodyH) / 2

            let body = Path(
                roundedRect: CGRect(x: left, y: top, width: bodyW, height: bodyH),
                cornerRadius: bodyW / 2,
                style: .continuous
            )
            ctx.fill(body, with: .color(p.raise))

            let cx = w / 2
            let cy = top + bodyH * 0.28
            ctx.fill(circle(cx, cy, bodyW * 0.30), with: .color(Color(hex: 0x0C0D0F)))
            ctx.fill(circle(cx, cy, bodyW * 0.19), with: .color(Color(hex: 0x1A1D22)))
            if lensGlow > 0 {
                ctx.fill(
                    circle(cx, cy, bodyW * 0.19),
                    with: .color(p.accent.opacity(0.9 * lensGlow))
                )
            }
        }
    }

    private func circle(_ cx: Double, _ cy: Double, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }
}

// ----------------------------------------------------------------- action circle
struct ActionCircle: View {
    let glyph: String
    let label: String
    var tint: Color? = nil
    var enabled: Bool = true
    let onTap: () -> Void

    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onTap) {
                ZStack {
                    Circle().fill(tint ?? p.sunk)
                    Text(glyph)
                        .font(.system(size: 18))
                        .foregroundStyle(tint != nil ? Color.white : p.ink)
                }
                .frame(width: 62, height: 62)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)

            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(p.dim)
        }
        .frame(width: 74)
        .opacity(enabled ? 1 : 0.4)
    }
}

// ----------------------------------------------------------------- telemetry tile
struct TeleTile: View {
    let key: String
    let value: String
    let unit: String
    let frac: Double
    let barColor: Color
    let warn: Bool

    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(key)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(p.muted)
            Spacer().frame(height: 2)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(warn ? p.amber : p.ink)
                Text(unit)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(p.muted)
            }
            Spacer().frame(height: 8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.raise)
                    Capsule()
                        .fill(barColor)
                        .frame(width: geo.size.width * min(max(frac, 0), 1))
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(p.sunk)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// ----------------------------------------------------------------- round button
struct RoundBtn: View {
    let glyph: String
    let onTap: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle().fill(p.sunk)
                Text(glyph)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(p.ink)
            }
            .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
    }
}

// ----------------------------------------------------------------- segmented
struct Seg: View {
    let options: [String]
    let selected: Int
    let onPick: (Int) -> Void
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                Button {
                    onPick(i)
                } label: {
                    Text(o)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(i == selected ? p.ink : p.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(i == selected ? p.raise : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(p.sunk)
        .clipShape(Capsule())
    }
}

// ----------------------------------------------------------------- pill button
/// The full-width accent button used for "Apply to camera" / "Try again".
struct PillButton: View {
    let title: String
    var background: Color? = nil
    var foreground: Color? = nil
    var fullWidth: Bool = true
    let onTap: () -> Void

    @Environment(\.palette) private var p

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.system(size: 14.5, weight: .bold))
                .foregroundStyle(foreground ?? .white)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.vertical, 13)
                .padding(.horizontal, fullWidth ? 0 : 22)
                .background(background ?? p.accent)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
