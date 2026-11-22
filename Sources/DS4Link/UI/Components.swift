import DS4LinkCore
import SwiftUI

struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.card(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.cardStroke(scheme), lineWidth: 1))
    }
}

struct CardDivider: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle().fill(Palette.cardStroke(scheme)).frame(height: 1).padding(.leading, 14)
    }
}

/// A numbered instruction line.
struct StepRow: View {
    var number: Int
    var text: String
    var tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(tint))
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// A bulleted hint line.
struct TipRow: View {
    var symbol: String
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// Label on the left, value on the right.
struct InfoRow<Value: View>: View {
    var label: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            value
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
    }
}

struct Spinner: View {
    var color: Color
    var size: CGFloat = 14
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 0.78)
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { turning = true }
            }
    }
}

struct BatteryGauge: View {
    var percent: Int?
    var charging: Bool

    private var tint: Color {
        guard let percent else { return .secondary }
        if charging { return Tone.good.color }
        if percent <= 15 { return Tone.bad.color }
        if percent <= 35 { return Tone.warn.color }
        return Tone.good.color
    }

    var body: some View {
        HStack(spacing: 7) {
            if charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Tone.good.color)
            }
            HStack(spacing: 1.5) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.5)
                        .stroke(Color.secondary.opacity(0.7), lineWidth: 1.2)
                        .frame(width: 27, height: 13)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint)
                        .frame(width: max(2, 22 * CGFloat(percent ?? 0) / 100), height: 8.5)
                        .padding(.leading, 2.4)
                        .opacity(percent == nil ? 0 : 1)
                }
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.secondary.opacity(0.7))
                    .frame(width: 2, height: 5)
            }
            Text(percent.map { "\($0)%" } ?? "Reading…")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}

struct StatusPill: View {
    var text: String
    var tone: Tone
    var busy: Bool

    var body: some View {
        HStack(spacing: 6) {
            if busy {
                Spinner(color: tone.color, size: 10)
            } else {
                Circle().fill(tone.color).frame(width: 7, height: 7)
            }
            Text(text.uppercased())
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundColor(tone.color)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(Capsule().fill(tone.color.opacity(0.14)))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 11).fill(tint))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 11))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 11))
    }
}

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundColor(.secondary)
            .opacity(configuration.isPressed ? 0.5 : 1)
            .contentShape(Rectangle())
    }
}

/// Short-lived message above the buttons ("Trying again…", "Controller switched off").
struct NoteBar: View {
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill").font(.system(size: 12))
            Text(text).font(.system(size: 12.5, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundColor(Tone.active.color)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(Tone.active.color.opacity(0.12)))
    }
}
