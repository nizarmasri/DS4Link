import DS4LinkCore
import SwiftUI

/// A stylised PlayStation pad drawn from plain shapes. It carries the instructions (the buttons
/// to hold pulse and get labels) and doubles as the input tester (pressed buttons light up and
/// the sticks follow your thumbs).
struct ControllerArt: View {
    struct Style {
        var body: Color
        var detail: Color
        var recess: Color
    }

    var lightBar: Color
    var accent: Color
    var pressed: Set<PadButton> = []
    var hinted: Set<PadButton> = []
    var leftStick: CGPoint = .zero
    var rightStick: CGPoint = .zero
    var showCallouts = false
    var style: Style?

    @Environment(\.colorScheme) private var scheme
    @State private var pulse = false

    static let canvas = CGSize(width: 300, height: 204)
    /// Everything is laid out in a 300-wide grid and shifted down to leave room for the labels.
    private let top: CGFloat = 18

    private var colors: Style {
        style ?? Style(body: Palette.padBody(scheme), detail: Palette.padDetail(scheme), recess: Palette.padRecess(scheme))
    }

    var body: some View {
        ZStack {
            shoulders
            shell
            centre
            leftCluster
            rightCluster
            sticks
            if showCallouts { callouts }
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height)
        .onAppear {
            withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { pulse = true }
        }
    }

    // MARK: Pieces

    private var shoulders: some View {
        ZStack {
            piece(.l2, RoundedRectangle(cornerRadius: 7), w: 38, h: 20, x: 72, y: 20, base: colors.recess)
            piece(.r2, RoundedRectangle(cornerRadius: 7), w: 38, h: 20, x: 228, y: 20, base: colors.recess)
            piece(.l1, RoundedRectangle(cornerRadius: 5), w: 48, h: 12, x: 72, y: 30, base: colors.detail)
            piece(.r1, RoundedRectangle(cornerRadius: 5), w: 48, h: 12, x: 228, y: 30, base: colors.detail)
        }
    }

    private var shell: some View {
        ZStack {
            Capsule().fill(colors.body)
                .frame(width: 58, height: 124)
                .rotationEffect(.degrees(13))
                .position(x: 54, y: 118 + top)
            Capsule().fill(colors.body)
                .frame(width: 58, height: 124)
                .rotationEffect(.degrees(-13))
                .position(x: 246, y: 118 + top)
            RoundedRectangle(cornerRadius: 36).fill(colors.body)
                .frame(width: 222, height: 110)
                .position(x: 150, y: 88 + top)
        }
    }

    private var centre: some View {
        ZStack {
            Capsule().fill(lightBar)
                .frame(width: 60, height: 5)
                .shadow(color: lightBar.opacity(0.85), radius: 5)
                .position(x: 150, y: 37 + top)
            piece(.touchpad, RoundedRectangle(cornerRadius: 9), w: 94, h: 46, x: 150, y: 66, base: colors.recess)
            halo(.share, x: 95, y: 49, size: 20)
            piece(.share, Capsule(), w: 7.5, h: 16, x: 95, y: 49, base: colors.detail)
            piece(.options, Capsule(), w: 7.5, h: 16, x: 205, y: 49, base: colors.detail)
            halo(.ps, x: 150, y: 124, size: 20)
            piece(.ps, Circle(), w: 14, h: 14, x: 150, y: 124, base: colors.detail)
        }
    }

    private var leftCluster: some View {
        ZStack {
            piece(.up, RoundedRectangle(cornerRadius: 3), w: 11, h: 14, x: 70, y: 68, base: colors.detail)
            piece(.down, RoundedRectangle(cornerRadius: 3), w: 11, h: 14, x: 70, y: 94, base: colors.detail)
            piece(.left, RoundedRectangle(cornerRadius: 3), w: 14, h: 11, x: 57, y: 81, base: colors.detail)
            piece(.right, RoundedRectangle(cornerRadius: 3), w: 14, h: 11, x: 83, y: 81, base: colors.detail)
        }
    }

    private var rightCluster: some View {
        ZStack {
            piece(.triangle, Circle(), w: 15, h: 15, x: 230, y: 66, base: colors.detail)
            piece(.cross, Circle(), w: 15, h: 15, x: 230, y: 96, base: colors.detail)
            piece(.square, Circle(), w: 15, h: 15, x: 215, y: 81, base: colors.detail)
            piece(.circle, Circle(), w: 15, h: 15, x: 245, y: 81, base: colors.detail)
        }
    }

    private var sticks: some View {
        ZStack {
            stick(.l3, x: 112, y: 122, offset: leftStick)
            stick(.r3, x: 188, y: 122, offset: rightStick)
        }
    }

    private var callouts: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 112, y: 3 + top))
                path.addLine(to: CGPoint(x: 97.5, y: 37 + top))
                path.move(to: CGPoint(x: 150, y: 162 + top))
                path.addLine(to: CGPoint(x: 150, y: 136 + top))
            }
            .stroke(accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            tag("SHARE", x: 120, y: -6)
            tag("PS", x: 150, y: 172)
        }
    }

    // MARK: Building blocks

    private func isLit(_ button: PadButton) -> Bool {
        pressed.contains(button) || hinted.contains(button)
    }

    private func piece<S: Shape>(_ button: PadButton, _ shape: S, w: CGFloat, h: CGFloat, x: CGFloat, y: CGFloat, base: Color) -> some View {
        shape.fill(isLit(button) ? accent : base)
            .frame(width: w, height: h)
            .position(x: x, y: y + top)
    }

    @ViewBuilder
    private func halo(_ button: PadButton, x: CGFloat, y: CGFloat, size: CGFloat) -> some View {
        if hinted.contains(button) {
            Circle().stroke(accent, lineWidth: 2)
                .frame(width: size, height: size)
                .scaleEffect(pulse ? 2.4 : 1.0)
                .opacity(pulse ? 0 : 0.9)
                .position(x: x, y: y + top)
        }
    }

    private func stick(_ button: PadButton, x: CGFloat, y: CGFloat, offset: CGPoint) -> some View {
        ZStack {
            Circle().fill(colors.recess).frame(width: 37, height: 37)
            Circle().fill(isLit(button) ? accent : colors.detail)
                .frame(width: 25, height: 25)
                .offset(x: offset.x * 6, y: -offset.y * 6)
        }
        .position(x: x, y: y + top)
    }

    private func tag(_ text: String, x: CGFloat, y: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .heavy, design: .rounded))
            .tracking(0.5)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(accent))
            .fixedSize()
            .position(x: x, y: y + top)
    }
}
