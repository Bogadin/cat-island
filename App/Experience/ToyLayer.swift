import SwiftUI

/// Toy mode overlay: a feather on a string or a laser dot she drags around the stage.
/// Lives in a left-to-right coordinate space (positions are physical).
struct ToyLayer: View {
    @ObservedObject var director: StageDirector
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let point = CGPoint(x: director.toyPoint.x * size.width, y: director.toyPoint.y * size.height)
            ZStack(alignment: .topLeading) {
                Color.clear
                switch director.toyKind {
                case .feather:
                    let anchor = CGPoint(x: min(size.width * 0.92, point.x + size.width * 0.3), y: 0)
                    Path { path in
                        path.move(to: anchor)
                        path.addQuadCurve(
                            to: point,
                            control: CGPoint(x: (anchor.x + point.x) / 2, y: max(anchor.y, point.y) + 50)
                        )
                    }
                    .stroke(MurzikPalette.ink.opacity(0.4), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    SwayingFeather(animated: !reduceMotion)
                        .frame(width: 40, height: 84)
                        .position(x: point.x, y: point.y + 38)
                case .laser:
                    LaserDot(animated: !reduceMotion)
                        .frame(width: 44, height: 44)
                        .position(point)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        director.moveToy(to: CGPoint(
                            x: value.location.x / max(size.width, 1),
                            y: value.location.y / max(size.height, 1)
                        ))
                    }
                    .onEnded { _ in director.toyReleased() }
            )
        }
        .accessibilityElement()
        .accessibilityLabel(Text(director.toyKind.title))
        .accessibilityHint(Text(Strings.toyHint))
        .accessibilityIdentifier("toy.layer")
    }
}

private struct SwayingFeather: View {
    let animated: Bool

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                FeatherToy()
                    .rotationEffect(.degrees(sin(t * 2.6) * 14), anchor: .top)
            }
        } else {
            FeatherToy()
        }
    }
}

/// A soft pink-to-lilac feather with a quill, hanging from its top.
struct FeatherToy: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                FeatherVane()
                    .fill(LinearGradient(
                        colors: [Color(red: 1.0, green: 0.62, blue: 0.72), Color(red: 0.76, green: 0.60, blue: 0.98)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: w, height: h * 0.86)
                    .position(x: w / 2, y: h * 0.5)
                // Barbs.
                ForEach(0..<5, id: \.self) { i in
                    let y = h * (0.28 + Double(i) * 0.12)
                    Path { p in
                        p.move(to: CGPoint(x: w / 2, y: y))
                        p.addLine(to: CGPoint(x: w * (i % 2 == 0 ? 0.88 : 0.12), y: y - h * 0.07))
                    }
                    .stroke(Color.white.opacity(0.55), lineWidth: 1.2)
                }
                // Quill.
                Path { p in
                    p.move(to: CGPoint(x: w / 2, y: 0))
                    p.addQuadCurve(to: CGPoint(x: w / 2 + 2, y: h), control: CGPoint(x: w / 2 - 3, y: h * 0.5))
                }
                .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .shadow(color: Color(red: 0.76, green: 0.45, blue: 0.75).opacity(0.35), radius: 6, y: 3)
        }
    }
}

struct FeatherVane: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                       control: CGPoint(x: rect.maxX + rect.width * 0.25, y: rect.minY + rect.height * 0.4))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                       control: CGPoint(x: rect.minX - rect.width * 0.3, y: rect.minY + rect.height * 0.5))
        p.closeSubpath()
        return p
    }
}

private struct LaserDot: View {
    let animated: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().fill(Color.red.opacity(0.18)).scaleEffect(pulse ? 1.0 : 0.7).blur(radius: 6)
            Circle().fill(Color.red.opacity(0.45)).frame(width: 22, height: 22).blur(radius: 3)
            Circle().fill(Color(red: 1.0, green: 0.2, blue: 0.25)).frame(width: 13, height: 13)
            Circle().fill(Color.white.opacity(0.9)).frame(width: 5, height: 5)
        }
        .onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// Soft expanding rings around Murzik while he purrs.
struct PurrRings: View {
    @State private var expand = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .strokeBorder(MurzikPalette.heart.opacity(0.35), lineWidth: 2)
                    .scaleEffect(expand ? 1.0 : 0.45)
                    .opacity(expand ? 0 : 0.9)
                    .animation(
                        .easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(Double(i) * 0.8),
                        value: expand
                    )
            }
        }
        .onAppear { expand = true }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
