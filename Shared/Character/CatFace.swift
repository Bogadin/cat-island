import SwiftUI

/// How a mood maps onto facial features.
struct FaceSpec: Equatable {
    enum Pupil: Equatable {
        case slit(width: CGFloat, dx: CGFloat)
        case round(diameter: CGFloat, dx: CGFloat, dy: CGFloat)
    }

    enum Eyes: Equatable {
        case open(Pupil, scale: CGFloat)
        case half(Pupil)
        case happyArc
        case sleepArc
        case blink
        case hearts
    }

    enum Mouth: Equatable {
        case w, open, o, tongue
    }

    var eyes: Eyes
    var mouth: Mouth
    var blush = false
    var zzz = false

    static func forMood(_ mood: MurzikMood, eyesClosed: Bool = false) -> FaceSpec {
        var spec: FaceSpec
        switch mood {
        case .idle:
            spec = FaceSpec(eyes: .open(.slit(width: 0.34, dx: 0), scale: 1), mouth: .w)
        case .happy:
            spec = FaceSpec(eyes: .happyArc, mouth: .open, blush: true)
        case .sleepy:
            spec = FaceSpec(eyes: .half(.slit(width: 0.30, dx: 0)), mouth: .w)
        case .sleeping:
            spec = FaceSpec(eyes: .sleepArc, mouth: .w, zzz: true)
        case .playful:
            spec = FaceSpec(eyes: .open(.slit(width: 0.30, dx: 0.035), scale: 0.95), mouth: .tongue)
        case .hungry:
            spec = FaceSpec(eyes: .open(.round(diameter: 0.15, dx: 0, dy: 0.006), scale: 1.05), mouth: .o)
        case .loving:
            spec = FaceSpec(eyes: .hearts, mouth: .w, blush: true)
        case .surprised:
            spec = FaceSpec(eyes: .open(.round(diameter: 0.07, dx: 0, dy: 0), scale: 1.16), mouth: .o)
        case .blinking:
            spec = FaceSpec(eyes: .blink, mouth: .w)
        case .excited:
            spec = FaceSpec(eyes: .open(.round(diameter: 0.135, dx: 0, dy: 0), scale: 1.08), mouth: .open, blush: true)
        }
        if eyesClosed, mood.canBlink {
            spec.eyes = .blink
        }
        return spec
    }
}

/// Murzik's head. Pure SwiftUI shapes, so it renders crisply in the app, in widgets and in the Dynamic Island.
struct CatFace: View {
    enum Detail {
        /// App and expanded presentations: whiskers, highlights, extras.
        case full
        /// Compact / minimal Dynamic Island: thicker lines, fewer details.
        case compact
    }

    var mood: MurzikMood
    var eyesClosed = false
    var detail: Detail = .full

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            CatFaceLayers(spec: FaceSpec.forMood(mood, eyesClosed: eyesClosed), detail: detail, size: side)
                .frame(width: side, height: side)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text("\(Strings.name), \(Strings.moodTitle(mood))"))
    }
}

private struct CatFaceLayers: View {
    let spec: FaceSpec
    let detail: CatFace.Detail
    let size: CGFloat

    private var isCompact: Bool { detail == .compact }
    private var rimWidth: CGFloat { size * (isCompact ? 0.06 : 0.022) }
    private var lineWidth: CGFloat { size * (isCompact ? 0.07 : 0.036) }

    private var furFill: RadialGradient {
        RadialGradient(
            colors: [MurzikPalette.furTop, MurzikPalette.furMid, MurzikPalette.furBottom],
            center: UnitPoint(x: 0.42, y: 0.40),
            startRadius: 0,
            endRadius: size * 0.62
        )
    }

    var body: some View {
        ZStack {
            CatShape(.head).fill(furFill)
            CatShape(.head).stroke(isCompact ? MurzikPalette.rimBright : MurzikPalette.rim, lineWidth: rimWidth)
            CatShape(.innerEars).fill(MurzikPalette.innerEar)

            if spec.blush {
                CatShape(.blush).fill(MurzikPalette.blush.opacity(isCompact ? 0.5 : 0.35))
            }

            eye(.left)
            eye(.right)

            if !isCompact || spec.mouth == .o || spec.mouth == .open {
                mouth
            }
            CatShape(.nose).fill(MurzikPalette.nose)

            if !isCompact {
                CatShape(.whiskers).stroke(MurzikPalette.whisker, style: StrokeStyle(lineWidth: size * 0.009, lineCap: .round))
            }

            if spec.zzz && !isCompact {
                sleepingZs
            }
        }
    }

    // MARK: Eyes

    @ViewBuilder
    private func eye(_ side: EyeSide) -> some View {
        switch spec.eyes {
        case let .open(pupil, scale):
            ZStack {
                CatShape(.eyeball(side, scale: scale)).fill(eyeFill(side, scale: scale))
                pupilShape(side, pupil, scale: scale).fill(Color.black)
                CatShape(.highlight(side, dx: -0.035 * scale, dy: -0.035 * scale, diameter: 0.055 * scale)).fill(Color.white)
                if !isCompact {
                    CatShape(.highlight(side, dx: 0.03 * scale, dy: 0.03 * scale, diameter: 0.025 * scale)).fill(Color.white.opacity(0.85))
                }
            }
            .clipShape(CatShape(.eyeball(side, scale: scale)))

        case let .half(pupil):
            ZStack {
                ZStack {
                    CatShape(.halfEyeball(side)).fill(eyeFill(side, scale: 1))
                    pupilShape(side, pupil, scale: 1).fill(Color.black)
                }
                .clipShape(CatShape(.halfEyeball(side)))
                CatShape(.eyelid(side)).stroke(MurzikPalette.rim, style: StrokeStyle(lineWidth: lineWidth * 0.7, lineCap: .round))
            }

        case .happyArc:
            CatShape(.happyArc(side)).stroke(MurzikPalette.closedEye, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

        case .sleepArc:
            CatShape(.sleepArc(side)).stroke(MurzikPalette.closedEye, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

        case .blink:
            CatShape(.blinkLine(side)).stroke(MurzikPalette.closedEye, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

        case .hearts:
            ZStack {
                CatShape(.heartEye(side)).fill(MurzikPalette.heart)
                if !isCompact {
                    CatShape(.highlight(side, dx: -0.04, dy: -0.03, diameter: 0.04)).fill(Color.white.opacity(0.9))
                }
            }
        }
    }

    private func eyeFill(_ side: EyeSide, scale: CGFloat) -> RadialGradient {
        RadialGradient(
            colors: [MurzikPalette.eyeCenter, MurzikPalette.eyeEdge],
            center: UnitPoint(x: side.cx, y: CatGeometry.eyeY),
            startRadius: 0,
            endRadius: size * 0.12 * scale
        )
    }

    private func pupilShape(_ side: EyeSide, _ pupil: FaceSpec.Pupil, scale: CGFloat) -> CatShape {
        switch pupil {
        case let .slit(width, dx):
            return CatShape(.slitPupil(side, width: width, dx: dx, scale: scale))
        case let .round(diameter, dx, dy):
            return CatShape(.roundPupil(side, diameter: diameter, dx: dx, dy: dy))
        }
    }

    // MARK: Mouth

    @ViewBuilder
    private var mouth: some View {
        let stroke = StrokeStyle(lineWidth: size * (isCompact ? 0.03 : 0.014), lineCap: .round, lineJoin: .round)
        switch spec.mouth {
        case .w:
            CatShape(.mouthW).stroke(MurzikPalette.mouth, style: stroke)
        case .open:
            ZStack {
                CatShape(.mouthOpen).fill(MurzikPalette.mouthInside)
                CatShape(.mouthOpen).stroke(MurzikPalette.mouth, style: stroke)
            }
        case .o:
            ZStack {
                CatShape(.mouthO).fill(MurzikPalette.mouthInside)
                CatShape(.mouthO).stroke(MurzikPalette.mouth, style: stroke)
            }
        case .tongue:
            ZStack {
                CatShape(.tongue).fill(MurzikPalette.tongue)
                CatShape(.mouthW).stroke(MurzikPalette.mouth, style: stroke)
            }
        }
    }

    private var sleepingZs: some View {
        ZStack {
            Text("z")
                .font(.system(size: size * 0.11, weight: .heavy, design: .rounded))
                .position(x: size * 0.80, y: size * 0.25)
            Text("z")
                .font(.system(size: size * 0.15, weight: .heavy, design: .rounded))
                .position(x: size * 0.89, y: size * 0.11)
        }
        .foregroundStyle(MurzikPalette.sky)
        .frame(width: size, height: size)
    }
}
