import SwiftUI
import AppKit

// MARK: - App icon

/// Renders the app's bundled application icon at the requested point size.
struct AppIconView: View {
    var size: CGFloat = 28
    var radius: CGFloat?

    var body: some View {
        Group {
            if let nsImage = NSImage(named: NSImage.applicationIconName)
                ?? NSImage(named: "AppIcon") {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: (radius ?? size * 0.22))
                    .fill(LinearGradient(colors: [Theme.cyan, Theme.purple],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius ?? size * 0.22))
        .shadow(color: Theme.cyan.opacity(0.18), radius: 7, x: 0, y: 4)
        .shadow(color: .black.opacity(0.20), radius: 0.5, x: 0, y: 1)
    }
}

// MARK: - Numbered section card

/// Card matching the design's `DLSection`: white panel with rounded corners,
/// a small numbered badge, and a kicker title.
struct DLSection<Content: View>: View {
    let number: String
    let title: String
    var accent: Color = Theme.cyan
    var accentSoft: Color = Theme.cyanSoft
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(accentSoft)
                        .frame(width: 22, height: 22)
                    Text(number)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(accent)
                }
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.text)
                    .kerning(-0.1)
            }
            content()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.025), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Field caption

struct DLFieldLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundColor(Theme.textDim)
    }
}

// MARK: - Segmented control (custom)

struct DLSegmentedOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: Value { value }
}

struct DLSegmented<Value: Hashable>: View {
    let options: [DLSegmentedOption<Value>]
    @Binding var selection: Value
    var accent: Color = Theme.cyan

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { opt in
                let active = opt.value == selection
                Text(opt.label)
                    .font(.system(size: 12.5, weight: active ? .bold : .medium))
                    .foregroundColor(active ? accent : Theme.textDim)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(active ? Color.white : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(accent.opacity(active ? 0.33 : 0), lineWidth: 1)
                    )
                    .shadow(color: active ? .black.opacity(0.08) : .clear,
                            radius: 1, x: 0, y: 1)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = opt.value }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.panel2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

// MARK: - Path field with Browse button

struct DLPathField: View {
    let value: String
    var placeholder: String = ""
    var onBrowse: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(value.isEmpty ? placeholder : value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(value.isEmpty ? Theme.textFaint : Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.panel2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                )
            Button(action: onBrowse) {
                Text("Browse…")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Theme.borderStrong, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 0.5, x: 0, y: 1)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Compact text field (used for resize numeric inputs)

/// Daylight-styled equivalent of a borderless macOS NSTextField. Matches
/// the panel-2 fill, 9-pt rounded corner, and subtle border used by
/// `DLPathField` so resize/numeric inputs blend with the section card.
struct DLCompactField: View {
    @Binding var text: String
    var width: CGFloat = 70
    var alignment: TextAlignment = .center

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(alignment)
            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
            .foregroundColor(Theme.text)
            .padding(.horizontal, 8)
            .frame(width: width, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.panel2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

// MARK: - Slider

struct DLSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 1...100
    var step: Double = 1
    var accent: Color = Theme.yellow

    var body: some View {
        GeometryReader { geo in
            let pct = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let clamped = max(0, min(1, pct))
            let knob: CGFloat = 18
            let trackInsetX: CGFloat = 0
            let usable = geo.size.width - knob
            let x = trackInsetX + usable * clamped

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.panel2)
                    .frame(height: 4)
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                Capsule()
                    .fill(accent)
                    .frame(width: max(0, x + knob / 2), height: 4)
                Circle()
                    .fill(Color.white)
                    .frame(width: knob, height: knob)
                    .overlay(Circle().stroke(Theme.borderStrong, lineWidth: 1))
                    .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 1)
                    .offset(x: x)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let p = max(0, min(1, (g.location.x - knob / 2) / max(1, usable)))
                        let raw = range.lowerBound + p * (range.upperBound - range.lowerBound)
                        let stepped = (raw / step).rounded() * step
                        value = max(range.lowerBound, min(range.upperBound, stepped))
                    }
            )
        }
        .frame(height: 20)
    }
}

// MARK: - Checkbox

struct DLCheckbox: View {
    @Binding var isOn: Bool
    let label: String
    var hint: String?
    var accent: Color = Theme.cyan

    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isOn ? accent : Color.white)
                        .frame(width: 18, height: 18)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(isOn ? accent : Theme.borderStrong, lineWidth: 1)
                        .frame(width: 18, height: 18)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(Theme.text)
                    if let hint {
                        Text(hint)
                            .font(.system(size: 11.5))
                            .foregroundColor(Theme.textDim)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Format tile (radio-style card)

struct DLFormatTile: View {
    let label: String
    let sub: String
    let tint: Color
    let tintSoft: Color
    let active: Bool
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(active ? tint : Theme.text)
                    Text(sub)
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.textDim)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .fill(active ? tint : Color.white)
                        .frame(width: 18, height: 18)
                    Circle()
                        .stroke(active ? tint : Theme.borderStrong, lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    if active {
                        Circle().fill(Color.white).frame(width: 6, height: 6)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(active ? tintSoft : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(active ? tint : Theme.border, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Type pill / badge

struct DLTypePill: View {
    let ext: String
    let count: Int

    var body: some View {
        let c = Theme.extColor(ext)
        HStack(spacing: 8) {
            Circle().fill(c.dot).frame(width: 7, height: 7)
            Text(ext.uppercased())
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundColor(c.fg)
                .kerning(0.8)
            Text("\(count)")
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.text)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(c.bg))
    }
}

// MARK: - File row

struct DLFileRow: View {
    let name: String

    var body: some View {
        let extStr = (name as NSString).pathExtension.lowercased()
        let c = Theme.extColor(extStr)
        HStack(spacing: 12) {
            Text(extStr.prefix(4).uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(c.fg)
                .kerning(0.4)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(c.bg))
            Text(name)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
    }
}

// MARK: - Format chip (used in conversion-flow hero)

struct DLFormatChip: View {
    let label: String
    let tint: Color
    var sub: String?
    var big: Bool = false

    var body: some View {
        VStack(alignment: .leading) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint)
                    .frame(width: 24, height: 24)
                    .shadow(color: tint.opacity(0.5), radius: 5, x: 0, y: 0)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 10, height: 10)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: big ? 24 : 20, weight: .heavy))
                    .foregroundColor(tint)
                    .kerning(0.5)
                if let sub {
                    Text(sub)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Theme.textDim)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: big ? 130 : 104, height: big ? 156 : 132, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(
                    colors: [tint.opacity(0.15), tint.opacity(0.06)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.4), lineWidth: 1.5)
        )
        .shadow(color: tint.opacity(0.13), radius: 12, x: 0, y: 8)
    }
}

// MARK: - Arrow between flow chips

/// Recreates the design's SVG arrow: a 60×14 stroked path with a rounded
/// horizontal shaft and an arrow head — matches the React mock 1:1 instead
/// of approximating with a Capsule + chevron.
struct DLArrow: View {
    var tint: Color = Theme.cyan

    var body: some View {
        Canvas { ctx, size in
            // The SVG was viewBox 0 0 60 14 with d="M2 7h54M50 2l6 5-6 5".
            let scaleX = size.width / 60
            let scaleY = size.height / 14
            let shaft = Path { p in
                p.move(to: CGPoint(x: 2 * scaleX, y: 7 * scaleY))
                p.addLine(to: CGPoint(x: 56 * scaleX, y: 7 * scaleY))
            }
            let head = Path { p in
                p.move(to: CGPoint(x: 50 * scaleX, y: 2 * scaleY))
                p.addLine(to: CGPoint(x: 56 * scaleX, y: 7 * scaleY))
                p.addLine(to: CGPoint(x: 50 * scaleX, y: 12 * scaleY))
            }
            let stroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            ctx.stroke(shaft, with: .color(tint), style: stroke)
            ctx.stroke(head,  with: .color(tint), style: stroke)
        }
        .frame(width: 60, height: 14)
    }
}

// MARK: - Primary CTA button

struct DLPrimaryButton: View {
    let title: String
    var subtitle: String?
    var icon: String = "arrow.right"
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                if let subtitle {
                    Text("·  \(subtitle)")
                        .font(.system(size: 15, weight: .bold))
                        .opacity(0.92)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hex: 0x2CC6DB), Theme.cyan],
                        startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    .blendMode(.overlay)
            )
            .shadow(color: Theme.cyan.opacity(enabled ? 0.33 : 0), radius: 12, x: 0, y: 8)
            .opacity(enabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
