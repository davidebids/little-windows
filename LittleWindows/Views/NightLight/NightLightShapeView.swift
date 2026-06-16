import SwiftUI

struct NightLightShapeView: View {
    let shape: NightLightShape
    let color: Color
    let softness: Double

    var body: some View {
        Group {
            switch shape {
            case .fullScreenGlow:
                Rectangle()
                    .fill(.clear)
            case .gradientOrb:
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(0.82),
                                color.opacity(0.92),
                                color.opacity(0.18),
                                .clear
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 150
                        )
                    )
            case .halo:
                GeometryReader { proxy in
                    let diameter = min(proxy.size.width, proxy.size.height)
                    ZStack {
                        Circle()
                            .stroke(
                                color.opacity(0.34),
                                lineWidth: max(3, diameter * 0.18)
                            )
                            .blur(radius: max(1, diameter * 0.05))
                        Circle()
                            .stroke(
                                color,
                                lineWidth: max(2, diameter * 0.09)
                            )
                        Circle()
                            .stroke(
                                Color.white.opacity(0.82),
                                lineWidth: max(1, diameter * 0.025)
                            )
                    }
                    .padding(diameter * 0.15)
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
                }
            case .wave:
                WaveShape()
                    .fill(color.gradient)
            case .windowGlow:
                RoundedRectangle(cornerRadius: 34)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.72), color, color.opacity(0.35)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        HStack(spacing: 10) {
                            Rectangle().fill(.black.opacity(0.12)).frame(width: 5)
                            Rectangle().fill(.black.opacity(0.12)).frame(width: 5)
                        }
                    }
            case .oval:
                Capsule().fill(color.gradient)
            case .roundedRectangle:
                RoundedRectangle(cornerRadius: 48).fill(color.gradient)
            case .circle:
                Circle().fill(color.gradient)
            case .elephant:
                ElephantSilhouette()
                    .fill(color.gradient)
            default:
                Image(systemName: shape.systemImage)
                    .resizable()
                    .scaledToFit()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(color)
            }
        }
        .shadow(
            color: color.opacity(0.68),
            radius: 28 + softness * 42
        )
        .shadow(
            color: color.opacity(0.32),
            radius: 70 + softness * 50
        )
        .accessibilityLabel(shape.displayName)
    }
}

private struct ElephantSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(
            in: CGRect(
                x: rect.width * 0.08,
                y: rect.height * 0.34,
                width: rect.width * 0.62,
                height: rect.height * 0.43
            )
        )
        path.addEllipse(
            in: CGRect(
                x: rect.width * 0.57,
                y: rect.height * 0.22,
                width: rect.width * 0.33,
                height: rect.height * 0.36
            )
        )
        path.addEllipse(
            in: CGRect(
                x: rect.width * 0.52,
                y: rect.height * 0.27,
                width: rect.width * 0.24,
                height: rect.height * 0.26
            )
        )
        path.addPath(
            RoundedRectangle(cornerRadius: rect.width * 0.035)
                .path(
                    in: CGRect(
                        x: rect.width * 0.78,
                        y: rect.height * 0.42,
                        width: rect.width * 0.11,
                        height: rect.height * 0.34
                    )
                )
        )
        for x in [CGFloat(0.18), CGFloat(0.50)] {
            path.addPath(
                RoundedRectangle(cornerRadius: rect.width * 0.035)
                    .path(
                        in: CGRect(
                            x: rect.width * x,
                            y: rect.height * 0.66,
                            width: rect.width * 0.13,
                            height: rect.height * 0.24
                        )
                    )
            )
        }

        var tail = Path()
        tail.move(
            to: CGPoint(
                x: rect.width * 0.1,
                y: rect.height * 0.46
            )
        )
        tail.addCurve(
            to: CGPoint(
                x: rect.width * 0.015,
                y: rect.height * 0.62
            ),
            control1: CGPoint(
                x: rect.width * 0.03,
                y: rect.height * 0.47
            ),
            control2: CGPoint(
                x: rect.width * 0.04,
                y: rect.height * 0.58
            )
        )
        path.addPath(tail.strokedPath(.init(lineWidth: rect.width * 0.035, lineCap: .round)))
        return path
    }
}

private struct WaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.55))
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.42),
            control1: CGPoint(x: rect.width * 0.25, y: rect.height * 0.05),
            control2: CGPoint(x: rect.width * 0.68, y: rect.height * 0.92)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}
