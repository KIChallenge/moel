import SwiftUI

enum MascotExpression { case calm, listening, working, speaking, confirmation }

/// One original rounded companion, reused on the route and in Focus.
/// Base green #008E5C follows the public Sozialversicherung SV-Grün palette.
struct SoviMascot: View {
    var size: CGFloat = 200
    var expression: MascotExpression = .calm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Ellipse().fill(SoviTheme.ink.opacity(0.09))
                .frame(width: size * 0.65, height: size * 0.07).offset(y: size * 0.43)
            Capsule().fill(Color(hex: 0x006A46)).frame(width: size * 0.18, height: size * 0.10)
                .rotationEffect(.degrees(-8)).offset(x: -size * 0.18, y: size * 0.38)
            Capsule().fill(Color(hex: 0x006A46)).frame(width: size * 0.18, height: size * 0.10)
                .rotationEffect(.degrees(8)).offset(x: size * 0.18, y: size * 0.38)
            RoundedRectangle(cornerRadius: size * 0.32)
                .fill(LinearGradient(colors: [Color(hex: 0x2FA979), Color(hex: 0x008E5C)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 0.74, height: size * 0.77)
            Capsule().fill(Color(hex: 0x53BB8F)).frame(width: size * 0.13, height: size * 0.28)
                .rotationEffect(.degrees(expression == .confirmation ? -55 : -25))
                .offset(x: -size * 0.37, y: size * (expression == .confirmation ? -0.04 : 0.11))
            Capsule().fill(Color(hex: 0x008E5C)).frame(width: size * 0.13, height: size * 0.28)
                .rotationEffect(.degrees(25)).offset(x: size * 0.37, y: size * 0.11)
            Ellipse().fill(Color(hex: 0xD9F0E4)).frame(width: size * 0.50, height: size * 0.43).offset(y: size * 0.07)
            HStack(spacing: size * 0.025) {
                iconEye(isLeft: true)
                iconEye(isLeft: false)
            }
            .offset(y: -size * 0.11)
            HStack(spacing: size * 0.32) {
                cheek; cheek
            }.offset(y: size * 0.06)
            if expression == .speaking {
                Ellipse().fill(Color(hex: 0x164D36)).frame(width: size * 0.07, height: size * 0.095).offset(y: size * 0.13)
            } else {
                Smile().stroke(Color(hex: 0x164D36), style: StrokeStyle(lineWidth: size * 0.018, lineCap: .round))
                    .frame(width: size * 0.10, height: size * 0.055).offset(y: size * 0.13)
            }
            LeafShape().fill(Color(hex: 0xA4D6AD)).frame(width: size * 0.13, height: size * 0.19)
                .rotationEffect(.degrees(28)).offset(x: size * 0.05, y: -size * 0.42)
            if expression == .listening {
                Image(systemName: "waveform").font(.system(size: size * 0.15)).foregroundStyle(SoviTheme.accent)
                    .offset(x: size * 0.48, y: -size * 0.16)
            }
            if expression == .working {
                Image(systemName: "ellipsis").font(.system(size: size * 0.14)).foregroundStyle(SoviTheme.accent)
                    .offset(x: size * 0.46, y: -size * 0.20)
            }
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: expression)
        .accessibilityHidden(true)
    }

    private func iconEye(isLeft: Bool) -> some View {
        MascotIconEye(isLeft: isLeft)
            .frame(width: size * 0.23, height: size * 0.23 * 158 / 127)
            .scaleEffect(y: expression == .confirmation ? 0.82 : 1)
    }
    private var cheek: some View {
        Ellipse().fill(Color(hex: 0xEFADA0).opacity(0.8)).frame(width: size * 0.07, height: size * 0.035)
    }
}
private struct Smile: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in p.move(to: .zero); p.addQuadCurve(to: CGPoint(x: r.width, y: 0), control: CGPoint(x: r.midX, y: r.height)) }
    }
}
private struct LeafShape: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: r.height))
            p.addQuadCurve(to: CGPoint(x: r.width, y: 0), control: .zero)
            p.addQuadCurve(to: CGPoint(x: 0, y: r.height), control: CGPoint(x: r.width, y: r.height))
        }
    }
}

/// Exact outlines, inward-looking pupils and highlights from AppIcon.icon's
/// left.svg and right.svg, rendered as vectors at every mascot size.
private struct MascotIconEye: View {
    let isLeft: Bool

    var body: some View {
        GeometryReader { geometry in
            let scale = CGAffineTransform(scaleX: geometry.size.width / 127,
                                          y: geometry.size.height / 158)
            ZStack {
                outline.applying(scale).fill(.white)
                pupil.applying(scale).fill(Color(hex: 0x4C4B4C))
                highlight.applying(scale).fill(.white)
            }
        }
    }

    private var outline: Path {
        if isLeft {
            Path { path in
                path.move(to: CGPoint(x: 61.35, y: 0))
                path.addLine(to: CGPoint(x: 60.94, y: 0))
                path.addCurve(to: CGPoint(x: 2.73, y: 57.79), control1: CGPoint(x: 28.51, y: 0), control2: CGPoint(x: 2.73, y: 25.78))
                path.addLine(to: CGPoint(x: 2.73, y: 99.79))
                path.addCurve(to: CGPoint(x: 60.52, y: 158), control1: CGPoint(x: 2.73, y: 132.22), control2: CGPoint(x: 28.51, y: 158))
                path.addLine(to: CGPoint(x: 60.94, y: 158))
                path.addCurve(to: CGPoint(x: 119.15, y: 100.21), control1: CGPoint(x: 93.37, y: 158), control2: CGPoint(x: 119.15, y: 132.22))
                path.addLine(to: CGPoint(x: 119.15, y: 57.79))
                path.addCurve(to: CGPoint(x: 61.35, y: 0), control1: CGPoint(x: 119.15, y: 25.78), control2: CGPoint(x: 93.37, y: 0))
                path.closeSubpath()
            }
        } else {
            Path { path in
                path.move(to: CGPoint(x: 65.92, y: 0))
                path.addLine(to: CGPoint(x: 65.51, y: 0))
                path.addCurve(to: CGPoint(x: 7.3, y: 57.79), control1: CGPoint(x: 33.08, y: 0), control2: CGPoint(x: 7.3, y: 25.78))
                path.addLine(to: CGPoint(x: 7.3, y: 99.79))
                path.addCurve(to: CGPoint(x: 65.09, y: 158), control1: CGPoint(x: 7.3, y: 132.22), control2: CGPoint(x: 33.08, y: 158))
                path.addLine(to: CGPoint(x: 65.51, y: 158))
                path.addCurve(to: CGPoint(x: 123.72, y: 100.21), control1: CGPoint(x: 97.94, y: 158), control2: CGPoint(x: 123.72, y: 132.22))
                path.addLine(to: CGPoint(x: 123.72, y: 57.79))
                path.addCurve(to: CGPoint(x: 65.92, y: 0), control1: CGPoint(x: 123.72, y: 25.78), control2: CGPoint(x: 97.94, y: 0))
                path.closeSubpath()
            }
        }
    }

    private var pupil: Path {
        if isLeft {
            Path { path in
                path.move(to: CGPoint(x: 81.89, y: 30.12))
                path.addLine(to: CGPoint(x: 78.28, y: 30.12))
                path.addCurve(to: CGPoint(x: 49.64, y: 58.76), control1: CGPoint(x: 62.43, y: 30.12), control2: CGPoint(x: 49.64, y: 42.91))
                path.addLine(to: CGPoint(x: 49.64, y: 90.17))
                path.addCurve(to: CGPoint(x: 78.56, y: 119.09), control1: CGPoint(x: 49.64, y: 106.3), control2: CGPoint(x: 62.43, y: 119.09))
                path.addLine(to: CGPoint(x: 82.17, y: 119.09))
                path.addCurve(to: CGPoint(x: 110.81, y: 90.45), control1: CGPoint(x: 98.02, y: 119.09), control2: CGPoint(x: 110.81, y: 106.3))
                path.addLine(to: CGPoint(x: 110.81, y: 58.76))
                path.addCurve(to: CGPoint(x: 81.89, y: 30.12), control1: CGPoint(x: 110.81, y: 42.91), control2: CGPoint(x: 98.02, y: 30.12))
                path.closeSubpath()
            }
        } else {
            Path { path in
                path.move(to: CGPoint(x: 46.31, y: 30.12))
                path.addLine(to: CGPoint(x: 42.7, y: 30.12))
                path.addCurve(to: CGPoint(x: 14.06, y: 58.76), control1: CGPoint(x: 26.85, y: 30.12), control2: CGPoint(x: 14.06, y: 42.91))
                path.addLine(to: CGPoint(x: 14.06, y: 90.18))
                path.addCurve(to: CGPoint(x: 42.98, y: 119.09), control1: CGPoint(x: 14.06, y: 106.3), control2: CGPoint(x: 26.85, y: 119.09))
                path.addLine(to: CGPoint(x: 46.59, y: 119.09))
                path.addCurve(to: CGPoint(x: 75.23, y: 90.45), control1: CGPoint(x: 62.44, y: 119.09), control2: CGPoint(x: 75.23, y: 106.3))
                path.addLine(to: CGPoint(x: 75.23, y: 58.76))
                path.addCurve(to: CGPoint(x: 46.31, y: 30.12), control1: CGPoint(x: 75.23, y: 42.91), control2: CGPoint(x: 62.44, y: 30.12))
                path.closeSubpath()
            }
        }
    }

    private var highlight: Path {
        if isLeft {
            Path { path in
                path.move(to: CGPoint(x: 59.37, y: 66.27))
                path.addCurve(to: CGPoint(x: 44.08, y: 50.97), control1: CGPoint(x: 50.92, y: 66.27), control2: CGPoint(x: 44.08, y: 59.43))
                path.addCurve(to: CGPoint(x: 59.37, y: 35.68), control1: CGPoint(x: 44.08, y: 42.52), control2: CGPoint(x: 50.92, y: 35.68))
                path.addCurve(to: CGPoint(x: 74.66, y: 50.97), control1: CGPoint(x: 67.83, y: 35.68), control2: CGPoint(x: 74.66, y: 42.52))
                path.addCurve(to: CGPoint(x: 59.37, y: 66.27), control1: CGPoint(x: 74.66, y: 59.43), control2: CGPoint(x: 67.83, y: 66.27))
                path.closeSubpath()
            }
        } else {
            Path { path in
                path.move(to: CGPoint(x: 26.57, y: 63.49))
                path.addCurve(to: CGPoint(x: 11.28, y: 48.19), control1: CGPoint(x: 18.12, y: 63.49), control2: CGPoint(x: 11.28, y: 56.65))
                path.addCurve(to: CGPoint(x: 26.57, y: 32.9), control1: CGPoint(x: 11.28, y: 39.74), control2: CGPoint(x: 18.12, y: 32.9))
                path.addCurve(to: CGPoint(x: 41.86, y: 48.19), control1: CGPoint(x: 35.03, y: 32.9), control2: CGPoint(x: 41.86, y: 39.74))
                path.addCurve(to: CGPoint(x: 26.57, y: 63.49), control1: CGPoint(x: 41.86, y: 56.65), control2: CGPoint(x: 35.03, y: 63.49))
                path.closeSubpath()
            }
        }
    }
}
