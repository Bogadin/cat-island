import SwiftUI

/// Colors of Murzik's room for each part of the day.
struct RoomTheme: Equatable {
    var wallTop: Color
    var wallBottom: Color
    var floorTop: Color
    var floorBottom: Color
    var skyTop: Color
    var skyBottom: Color
    var frame: Color
    var beam: Color
    var rug: Color
    var rugInner: Color
    var leaf: Color
    var isDark: Bool

    /// Main text color on the room background.
    var ink: Color { isDark ? MurzikPalette.cream : MurzikPalette.ink }
    var inkSoft: Color { isDark ? MurzikPalette.cream.opacity(0.72) : MurzikPalette.inkSoft }
    /// Glassy card fill on this background.
    var card: Color { isDark ? Color(red: 0.98, green: 0.95, blue: 0.91).opacity(0.94) : Color.white.opacity(0.82) }

    static func `for`(_ phase: DayPhase) -> RoomTheme {
        switch phase {
        case .morning:
            return RoomTheme(
                wallTop: Color(red: 1.00, green: 0.94, blue: 0.88), wallBottom: Color(red: 0.99, green: 0.87, blue: 0.79),
                floorTop: Color(red: 0.93, green: 0.80, blue: 0.68), floorBottom: Color(red: 0.86, green: 0.70, blue: 0.58),
                skyTop: Color(red: 0.70, green: 0.84, blue: 0.98), skyBottom: Color(red: 1.00, green: 0.84, blue: 0.72),
                frame: Color(red: 1.00, green: 0.98, blue: 0.95), beam: Color(red: 1.00, green: 0.93, blue: 0.76),
                rug: Color(red: 0.89, green: 0.60, blue: 0.55), rugInner: Color(red: 0.96, green: 0.77, blue: 0.69),
                leaf: Color(red: 0.42, green: 0.63, blue: 0.47), isDark: false)
        case .day:
            return RoomTheme(
                wallTop: Color(red: 0.99, green: 0.96, blue: 0.92), wallBottom: Color(red: 0.96, green: 0.91, blue: 0.85),
                floorTop: Color(red: 0.92, green: 0.84, blue: 0.74), floorBottom: Color(red: 0.84, green: 0.74, blue: 0.63),
                skyTop: Color(red: 0.52, green: 0.74, blue: 0.97), skyBottom: Color(red: 0.84, green: 0.92, blue: 0.99),
                frame: Color.white, beam: Color(red: 1.00, green: 0.98, blue: 0.90),
                rug: Color(red: 0.88, green: 0.62, blue: 0.58), rugInner: Color(red: 0.96, green: 0.80, blue: 0.74),
                leaf: Color(red: 0.40, green: 0.64, blue: 0.47), isDark: false)
        case .evening:
            return RoomTheme(
                wallTop: Color(red: 0.99, green: 0.87, blue: 0.78), wallBottom: Color(red: 0.94, green: 0.74, blue: 0.67),
                floorTop: Color(red: 0.87, green: 0.67, blue: 0.58), floorBottom: Color(red: 0.75, green: 0.55, blue: 0.50),
                skyTop: Color(red: 0.55, green: 0.45, blue: 0.74), skyBottom: Color(red: 1.00, green: 0.62, blue: 0.45),
                frame: Color(red: 1.00, green: 0.95, blue: 0.90), beam: Color(red: 1.00, green: 0.74, blue: 0.48),
                rug: Color(red: 0.80, green: 0.48, blue: 0.47), rugInner: Color(red: 0.92, green: 0.66, blue: 0.60),
                leaf: Color(red: 0.36, green: 0.52, blue: 0.40), isDark: false)
        case .night:
            return RoomTheme(
                wallTop: Color(red: 0.26, green: 0.26, blue: 0.42), wallBottom: Color(red: 0.20, green: 0.20, blue: 0.34),
                floorTop: Color(red: 0.24, green: 0.22, blue: 0.35), floorBottom: Color(red: 0.15, green: 0.14, blue: 0.25),
                skyTop: Color(red: 0.06, green: 0.08, blue: 0.22), skyBottom: Color(red: 0.18, green: 0.21, blue: 0.42),
                frame: Color(red: 0.40, green: 0.40, blue: 0.58), beam: Color(red: 0.70, green: 0.76, blue: 1.00),
                rug: Color(red: 0.44, green: 0.33, blue: 0.47), rugInner: Color(red: 0.53, green: 0.42, blue: 0.55),
                leaf: Color(red: 0.24, green: 0.34, blue: 0.34), isDark: true)
        }
    }
}

/// A warm, softly lit room behind the 3D stage: wall, arched window with the sky of the hour,
/// a light beam, floor, rug, a plant and a little framed heart.
struct RoomBackdrop: View {
    let phase: DayPhase
    /// The stage's frame in global coordinates (the rug and floor line follow it). `.zero` = estimate.
    var stageFrame: CGRect = .zero
    var animated = true

    var body: some View {
        let theme = RoomTheme.for(phase)
        GeometryReader { geo in
            let size = geo.size
            let origin = geo.frame(in: .global).origin
            let stage = stageFrame == .zero
                ? CGRect(x: 0, y: size.height * 0.13, width: size.width, height: size.height * 0.6)
                : stageFrame.offsetBy(dx: -origin.x, dy: -origin.y)
            let floorY = stage.maxY - stage.height * 0.2
            let windowWidth = min(size.width * 0.38, 178)
            let windowHeight = windowWidth * 1.58
            let window = CGRect(
                x: size.width * 0.07, y: max(stage.minY - 30, floorY - windowHeight - 105),
                width: windowWidth, height: windowHeight
            )

            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [theme.wallTop, theme.wallBottom], startPoint: .top, endPoint: .bottom)

                // Soft vignette in the corners.
                RadialGradient(
                    colors: [Color.white.opacity(theme.isDark ? 0.05 : 0.35), .clear],
                    center: UnitPoint(x: 0.5, y: stage.midY / max(size.height, 1)),
                    startRadius: 20, endRadius: size.width * 0.9
                )

                ArchWindow(theme: theme, phase: phase, animated: animated)
                    .frame(width: window.width, height: window.height)
                    .position(x: window.midX, y: window.midY)

                // Window sill.
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(theme.frame)
                    .frame(width: window.width + 24, height: 10)
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
                    .position(x: window.midX, y: window.maxY + 4)

                FramedHeart(theme: theme)
                    .frame(width: 62, height: 74)
                    .position(x: size.width * 0.8, y: window.minY + 120)

                StringLights(
                    from: CGPoint(x: -10, y: window.minY - 26),
                    to: CGPoint(x: size.width + 10, y: window.minY - 40),
                    sag: 54, isDark: theme.isDark, animated: animated
                )

                // Floor.
                LinearGradient(colors: [theme.floorTop, theme.floorBottom], startPoint: .top, endPoint: .bottom)
                    .frame(width: size.width, height: max(0, size.height - floorY))
                    .offset(y: floorY)
                Rectangle()
                    .fill(theme.wallBottom.opacity(0.9))
                    .frame(width: size.width, height: 7)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.black.opacity(theme.isDark ? 0.25 : 0.08)).frame(height: 1.5)
                    }
                    .offset(y: floorY - 7)

                LightBeam(window: window, floorY: floorY, color: theme.beam, isDark: theme.isDark)

                if theme.isDark {
                    // A warm lamp glow behind Murzik keeps the black cat readable at night.
                    RadialGradient(
                        colors: [Color(red: 1.0, green: 0.80, blue: 0.55).opacity(0.38), .clear],
                        center: .center, startRadius: 10, endRadius: stage.width * 0.55
                    )
                    .frame(width: stage.width * 1.2, height: stage.height)
                    .position(x: stage.midX, y: stage.midY + stage.height * 0.05)
                } else {
                    RadialGradient(
                        colors: [Color.white.opacity(0.55), .clear],
                        center: .center, startRadius: 10, endRadius: stage.width * 0.48
                    )
                    .frame(width: stage.width, height: stage.height)
                    .position(x: stage.midX, y: stage.midY)
                }

                // The rug is drawn in 3D by Murzik3DView (with real shadows).

                Plant(theme: theme)
                    .frame(width: 92, height: 150)
                    .position(x: size.width * 0.86, y: floorY - 20)

                if animated {
                    DustMotes(area: CGRect(x: window.minX, y: window.maxY, width: window.width + 140, height: floorY - window.maxY + 80),
                              color: theme.isDark ? Color.white.opacity(0.35) : Color.white.opacity(0.9))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

// MARK: - Pieces

struct ArchShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.width / 2
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.midX, y: rect.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct ArchWindow: View {
    let theme: RoomTheme
    let phase: DayPhase
    let animated: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                ArchShape()
                    .fill(LinearGradient(colors: [theme.skyTop, theme.skyBottom], startPoint: .top, endPoint: .bottom))
                sky(w: w, h: h)
                    .clipShape(ArchShape())
                // Glass sheen.
                ArchShape()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.22), .clear], startPoint: .topLeading, endPoint: .center))
                // Mullions.
                Rectangle().fill(theme.frame).frame(width: 6, height: h - w * 0.18).offset(y: w * 0.09)
                Rectangle().fill(theme.frame).frame(width: w, height: 6).offset(y: h * 0.12)
                ArchShape()
                    .stroke(theme.frame, lineWidth: 9)
            }
            .shadow(color: .black.opacity(theme.isDark ? 0.3 : 0.08), radius: 8, y: 4)
        }
    }

    @ViewBuilder
    private func sky(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            switch phase {
            case .morning:
                sun(color: Color(red: 1.0, green: 0.86, blue: 0.55), size: w * 0.34)
                    .position(x: w * 0.32, y: h * 0.74)
                cloud(width: w * 0.5).position(x: w * 0.66, y: h * 0.36)
            case .day:
                sun(color: Color(red: 1.0, green: 0.93, blue: 0.62), size: w * 0.3)
                    .position(x: w * 0.68, y: h * 0.3)
                cloud(width: w * 0.55).position(x: w * 0.34, y: h * 0.58)
                cloud(width: w * 0.36).position(x: w * 0.74, y: h * 0.78)
            case .evening:
                sun(color: Color(red: 1.0, green: 0.55, blue: 0.35), size: w * 0.42)
                    .position(x: w * 0.5, y: h * 0.9)
                cloud(width: w * 0.48).opacity(0.7).position(x: w * 0.36, y: h * 0.44)
            case .night:
                ForEach(0..<14, id: \.self) { i in
                    let x = (Double((i * 37) % 100) / 100.0) * w
                    let y = (Double((i * 53 + 11) % 100) / 100.0) * h * 0.9 + h * 0.05
                    Circle()
                        .fill(Color.white.opacity(i % 3 == 0 ? 0.95 : 0.6))
                        .frame(width: i % 4 == 0 ? 3.2 : 2, height: i % 4 == 0 ? 3.2 : 2)
                        .position(x: x, y: y)
                }
                Moon(size: w * 0.3)
                    .position(x: w * 0.64, y: h * 0.32)
            }
        }
        .frame(width: w, height: h)
    }

    private func sun(color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background(
                Circle().fill(color.opacity(0.35)).frame(width: size * 2, height: size * 2).blur(radius: 10)
            )
    }

    private func cloud(width: CGFloat) -> some View {
        ZStack {
            Capsule().frame(width: width, height: width * 0.28).offset(y: width * 0.06)
            Circle().frame(width: width * 0.42).offset(x: -width * 0.12, y: -width * 0.04)
            Circle().frame(width: width * 0.32).offset(x: width * 0.16, y: -width * 0.01)
        }
        .foregroundStyle(Color.white.opacity(0.92))
        .frame(width: width, height: width * 0.5)
    }
}

private struct Moon: View {
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color(red: 1.0, green: 0.96, blue: 0.82))
            .frame(width: size, height: size)
            .mask {
                Rectangle()
                    .overlay(Circle().frame(width: size * 0.86, height: size * 0.86).offset(x: size * 0.32, y: -size * 0.12).blendMode(.destinationOut))
                    .compositingGroup()
            }
            .background(Circle().fill(Color(red: 1.0, green: 0.95, blue: 0.75).opacity(0.25)).frame(width: size * 2, height: size * 2).blur(radius: 12))
    }
}

private struct LightBeam: View {
    let window: CGRect
    let floorY: CGFloat
    let color: Color
    let isDark: Bool

    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: window.minX + 6, y: window.maxY))
            p.addLine(to: CGPoint(x: window.maxX - 6, y: window.maxY))
            p.addLine(to: CGPoint(x: window.maxX + 150, y: floorY + 120))
            p.addLine(to: CGPoint(x: window.minX + 40, y: floorY + 150))
            p.closeSubpath()
        }
        .fill(LinearGradient(
            colors: [color.opacity(isDark ? 0.16 : 0.5), color.opacity(0)],
            startPoint: UnitPoint(x: 0.2, y: 0.0), endPoint: UnitPoint(x: 0.6, y: 1.0)
        ))
        .blur(radius: 14)
        .blendMode(isDark ? .screen : .softLight)
        .overlay(
            Path { p in
                p.move(to: CGPoint(x: window.minX + 6, y: window.maxY))
                p.addLine(to: CGPoint(x: window.maxX - 6, y: window.maxY))
                p.addLine(to: CGPoint(x: window.maxX + 150, y: floorY + 120))
                p.addLine(to: CGPoint(x: window.minX + 40, y: floorY + 150))
                p.closeSubpath()
            }
            .fill(color.opacity(isDark ? 0.06 : 0.18))
            .blur(radius: 20)
        )
    }
}

/// A sagging string of warm fairy lights across the wall; they glow brighter at night.
private struct StringLights: View {
    let from: CGPoint
    let to: CGPoint
    let sag: CGFloat
    let isDark: Bool
    let animated: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.murzikAnimationsPaused) private var paused

    private var control: CGPoint {
        CGPoint(x: (from.x + to.x) / 2, y: max(from.y, to.y) + sag * 2)
    }

    private func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
            y: u * u * from.y + 2 * u * t * control.y + t * t * to.y
        )
    }

    private static let colors: [Color] = [
        Color(red: 1.0, green: 0.82, blue: 0.45),
        Color(red: 1.0, green: 0.62, blue: 0.62),
        Color(red: 1.0, green: 0.90, blue: 0.62),
        Color(red: 0.98, green: 0.70, blue: 0.48),
    ]

    var body: some View {
        let count = 11
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: from)
                p.addQuadCurve(to: to, control: control)
            }
            .stroke(Color(red: 0.35, green: 0.30, blue: 0.28).opacity(isDark ? 0.6 : 0.35), lineWidth: 1.2)

            if animated && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: paused)) { timeline in
                    bulbs(count: count, time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                bulbs(count: count, time: 0)
            }
        }
    }

    private func bulbs(count: Int, time: TimeInterval) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<count, id: \.self) { i in
                let t = (CGFloat(i) + 0.5) / CGFloat(count)
                let p = point(at: t)
                let color = Self.colors[i % Self.colors.count]
                let twinkle = 0.75 + 0.25 * sin(time * 1.7 + Double(i) * 1.3)
                ZStack {
                    Circle()
                        .fill(color.opacity((isDark ? 0.55 : 0.3) * twinkle))
                        .frame(width: isDark ? 26 : 16, height: isDark ? 26 : 16)
                        .blur(radius: isDark ? 7 : 4)
                    Capsule()
                        .fill(color)
                        .frame(width: 7, height: 11)
                        .opacity(isDark ? twinkle : 0.95)
                }
                .position(x: p.x, y: p.y + 6)
            }
        }
    }
}

private struct Rug: View {
    let theme: RoomTheme

    var body: some View {
        ZStack {
            Ellipse().fill(Color.black.opacity(theme.isDark ? 0.25 : 0.08)).offset(y: 4).blur(radius: 4)
            Ellipse().fill(theme.rug)
            Ellipse().strokeBorder(theme.rugInner, style: StrokeStyle(lineWidth: 2.5, dash: [6, 5])).padding(7)
            Ellipse().fill(theme.rugInner.opacity(0.65)).padding(.horizontal, 60).padding(.vertical, 16)
        }
    }
}

private struct Plant: View {
    let theme: RoomTheme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                ForEach(0..<7, id: \.self) { i in
                    let angle = -60.0 + Double(i) * 20.0
                    Ellipse()
                        .fill(LinearGradient(colors: [theme.leaf.opacity(0.95), theme.leaf.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                        .frame(width: w * 0.24, height: h * (i % 2 == 0 ? 0.5 : 0.42))
                        .offset(y: -h * 0.2)
                        .rotationEffect(.degrees(angle), anchor: .bottom)
                        .position(x: w / 2, y: h * 0.42)
                }
                // Pot.
                Path { p in
                    p.move(to: CGPoint(x: w * 0.2, y: h * 0.62))
                    p.addLine(to: CGPoint(x: w * 0.8, y: h * 0.62))
                    p.addLine(to: CGPoint(x: w * 0.7, y: h))
                    p.addLine(to: CGPoint(x: w * 0.3, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color(red: 0.86, green: 0.52, blue: 0.40), Color(red: 0.72, green: 0.40, blue: 0.32)],
                                     startPoint: .top, endPoint: .bottom))
                .opacity(theme.isDark ? 0.75 : 1)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: 0.92, green: 0.60, blue: 0.47).opacity(theme.isDark ? 0.75 : 1))
                    .frame(width: w * 0.68, height: h * 0.07)
                    .position(x: w / 2, y: h * 0.63)
            }
        }
    }
}

private struct FramedHeart: View {
    let theme: RoomTheme

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(theme.isDark ? Color(red: 0.32, green: 0.31, blue: 0.48) : Color(red: 1.0, green: 0.97, blue: 0.93))
            .overlay(
                Image(systemName: "heart.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(MurzikPalette.heart.opacity(theme.isDark ? 0.75 : 0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color(red: 0.78, green: 0.60, blue: 0.42).opacity(theme.isDark ? 0.6 : 1), lineWidth: 5)
            )
            .shadow(color: .black.opacity(theme.isDark ? 0.3 : 0.1), radius: 5, y: 3)
            .rotationEffect(.degrees(-3))
    }
}

private struct DustMotes: View {
    let area: CGRect
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.murzikAnimationsPaused) private var paused

    var body: some View {
        if !reduceMotion, area.width > 0, area.height > 0 {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: paused)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, _ in
                    for i in 0..<12 {
                        let seed = Double(i) * 1.618
                        let x = area.minX + area.width * (0.5 + 0.45 * sin(t * 0.05 + seed * 3.1))
                        let y = area.minY + area.height * (0.5 + 0.45 * sin(t * 0.07 + seed * 1.7))
                        let r = 1.0 + (Double(i % 3) * 0.6)
                        let alpha = 0.35 + 0.35 * sin(t * 0.6 + seed)
                        context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                     with: .color(color.opacity(alpha)))
                    }
                }
            }
        }
    }
}
