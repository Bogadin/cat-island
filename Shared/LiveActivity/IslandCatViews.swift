import SwiftUI

// Full-body Murzik for the Live Activity: the pre-rendered 3D sprite when it is in the asset
// catalog (192 px PNGs, tiny in memory), otherwise a 2D full-body drawing (sitting figure or a
// side-view walker), so every layout works before the 3D sprites arrive.

/// Murzik in a square box of `size` points, feet on the bottom edge.
struct IslandCatPose: View {
    var scene: IslandScene
    var mood: MurzikMood
    var size: CGFloat

    var body: some View {
        let sprite = scene.sprite(for: mood)
        Group {
            if let image = sprite.uiImage {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
            } else {
                IslandCatFallback(pose: scene.pose, frame: scene.frame, mood: mood)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(x: scene.facingLeft ? -1 : 1, y: 1)
        .offset(y: scene.pose == .hop ? -size * 0.2 : 0)
        .accessibilityElement()
        .accessibilityLabel(Text("\(Strings.name), \(Strings.moodTitle(mood))"))
    }
}

/// 2D stand-in for a sprite.
struct IslandCatFallback: View {
    var pose: IslandScene.Pose
    var frame: Int
    var mood: MurzikMood

    var body: some View {
        switch pose {
        case .walk:
            IslandWalkingCat2D(frame: frame, mood: mood)
        case .stretch:
            IslandWalkingCat2D(frame: 0, mood: mood, stretch: true)
        case .eat:
            IslandWalkingCat2D(frame: 0, mood: .happy, headDown: true)
        case .rest, .hop:
            CatFigure(mood: mood)
        }
    }
}

/// A side-view walking Murzik facing right, drawn with shapes (legs swing with `frame`).
struct IslandWalkingCat2D: View {
    var frame: Int
    var mood: MurzikMood
    var stretch = false
    var headDown = false

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let phase = Double(((frame % 8) + 8) % 8) / 8 * 2 * Double.pi
            let swing = stretch ? 0 : sin(phase) * 26
            let bodyY = stretch ? 0.64 : 0.6
            ZStack {
                tail(s)
                leg(s, x: 0.3, top: bodyY, angle: stretch ? 8 : -swing, far: true)
                leg(s, x: 0.6, top: bodyY, angle: stretch ? -30 : swing, far: true)
                Ellipse()
                    .fill(LinearGradient(colors: [MurzikPalette.furTop, MurzikPalette.furBottom], startPoint: .top, endPoint: .bottom))
                    .overlay(Ellipse().stroke(MurzikPalette.rimBright, lineWidth: s * 0.03))
                    .frame(width: s * 0.6, height: s * 0.3)
                    .rotationEffect(.degrees(stretch ? 8 : (headDown ? 6 : 0)))
                    .position(x: s * 0.45, y: s * bodyY)
                leg(s, x: 0.36, top: bodyY, angle: stretch ? 4 : swing, far: false)
                leg(s, x: 0.67, top: bodyY, angle: stretch ? -36 : -swing, far: false)
                CatFace(mood: mood, detail: .compact)
                    .frame(width: s * 0.52, height: s * 0.52)
                    .position(x: s * (headDown ? 0.76 : 0.74), y: s * (stretch ? 0.52 : (headDown ? 0.56 : 0.34)))
            }
            .frame(width: s, height: s)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func leg(_ s: CGFloat, x: CGFloat, top: CGFloat, angle: Double, far: Bool) -> some View {
        let length = 0.96 - top
        return Capsule()
            .fill(far ? MurzikPalette.furBottom : MurzikPalette.furMid)
            .overlay(Capsule().stroke(MurzikPalette.rimBright.opacity(far ? 0.45 : 1), lineWidth: s * 0.024))
            .frame(width: s * 0.1, height: s * length)
            .rotationEffect(.degrees(angle), anchor: .top)
            .position(x: s * x, y: s * (top + length / 2))
    }

    private func tail(_ s: CGFloat) -> some View {
        let path = Path { p in
            p.move(to: CGPoint(x: s * 0.2, y: s * 0.58))
            p.addQuadCurve(to: CGPoint(x: s * 0.06, y: s * 0.18), control: CGPoint(x: s * -0.02, y: s * 0.5))
        }
        return ZStack {
            path.stroke(MurzikPalette.rimBright, style: StrokeStyle(lineWidth: s * 0.1, lineCap: .round))
            path.stroke(MurzikPalette.furMid, style: StrokeStyle(lineWidth: s * 0.055, lineCap: .round))
        }
    }
}

/// Hearts, food or sparkles floating above Murzik.
struct IslandEffectBadge: View {
    var effect: IslandScene.Effect
    var size: CGFloat

    var body: some View {
        switch effect {
        case .none:
            EmptyView()
        case .hearts:
            ZStack {
                symbol("heart.fill", MurzikPalette.heart, 0.55).offset(x: -size * 0.28, y: size * 0.12)
                symbol("heart.fill", MurzikPalette.heart, 0.8).offset(x: size * 0.12, y: -size * 0.1)
                symbol("heart.fill", MurzikPalette.heart.opacity(0.8), 0.4).offset(x: size * 0.42, y: size * 0.22)
            }
        case .food:
            symbol("fish.fill", MurzikPalette.amber, 0.7)
        case .sparkles:
            symbol("sparkles", Color(red: 1, green: 0.85, blue: 0.3), 0.9)
        }
    }

    private func symbol(_ name: String, _ color: Color, _ scale: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size * scale, weight: .bold))
            .foregroundStyle(color)
    }
}

/// Murzik's bowl at the left end of the stage.
struct IslandFoodBowl: View {
    var hungry: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            if !hungry {
                Image(systemName: "fish.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(MurzikPalette.amber.opacity(0.9))
                    .offset(y: -7)
            }
            BowlShape()
                .fill(LinearGradient(colors: [MurzikPalette.amber, MurzikPalette.amber.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .frame(width: 20, height: 9)
                .shadow(color: hungry ? MurzikPalette.amber.opacity(0.9) : .clear, radius: 4)
        }
        .frame(width: 22, height: 18, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

private struct BowlShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.midX + rect.width * 0.3, y: rect.maxY), control: CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX - rect.width * 0.3, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.minX + rect.width * 0.04, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The cushion at the right end of the stage, where he likes to be petted.
struct IslandCushion: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(colors: [MurzikPalette.heart.opacity(0.75), MurzikPalette.heart.opacity(0.4)], startPoint: .top, endPoint: .bottom))
                .frame(width: 26, height: 7)
            Image(systemName: "heart.fill")
                .font(.system(size: 5, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: 28, height: 8)
        .accessibilityHidden(true)
    }
}

/// Real-time paw-print trail from the cushion to the bowl. It fills as Murzik gets hungrier using
/// `ProgressView(timerInterval:)` as a mask, so it advances without any content update.
struct IslandPawTrail: View {
    var range: ClosedRange<Date>?
    var hungry: Bool

    var body: some View {
        ZStack {
            prints.foregroundStyle(Color.white.opacity(0.12))
            if hungry {
                prints.foregroundStyle(MurzikPalette.amber.opacity(0.9))
            } else if let range {
                prints
                    .foregroundStyle(MurzikPalette.amber.opacity(0.95))
                    .mask {
                        timerBar(range)
                            .tint(.white)
                            .scaleEffect(x: 1, y: 8)
                    }
                // The same timer as a thin fuse on the ground line (Apple's documented real-time view).
                timerBar(range)
                    .tint(MurzikPalette.amber.opacity(0.7))
                    .frame(height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .offset(y: 5)
            }
        }
        .accessibilityHidden(true)
    }

    /// A linear timer bar that fills from right (cushion) to left (bowl).
    private func timerBar(_ range: ClosedRange<Date>) -> some View {
        ProgressView(timerInterval: range, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .labelsHidden()
        .scaleEffect(x: -1, y: 1)
    }

    private var prints: some View {
        HStack(spacing: 0) {
            ForEach(0..<11, id: \.self) { i in
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 7, weight: .bold))
                    .rotationEffect(.degrees(-90))
                    .offset(y: i % 2 == 0 ? -2 : 2)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
