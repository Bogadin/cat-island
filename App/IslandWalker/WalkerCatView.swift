import SwiftUI
import UIKit

/// Which pre-rendered sprites exist (checked once; images are added by the 3D team later).
enum WalkerSprites {
    static let available: Set<MurzikSprite> = Set(MurzikSprite.allCases.filter { $0.uiImage != nil })
    static let hasWalkCycle: Bool = MurzikSprite.walkCycle.allSatisfy { available.contains($0) }

    static func has(_ sprite: MurzikSprite) -> Bool { available.contains(sprite) }
}

/// Draws Murzik for one `WalkerFrame`: a 3D sprite when exported, otherwise a 2D fallback.
/// The view is a square of `size` points; the cat's feet are on its bottom edge.
struct WalkerCatView: View {
    let frame: WalkerFrame
    let mood: MurzikMood
    let time: Double
    var size: CGFloat = IslandGeometry.catBox

    var body: some View {
        pose
            .frame(width: size, height: size)
            .scaleEffect(x: frame.facingLeft ? -1 : 1, y: 1)
            .scaleEffect(x: frame.scaleX, y: frame.scaleY, anchor: .bottom)
            .rotationEffect(.degrees(frame.tilt), anchor: .bottom)
            .rotationEffect(.degrees(frame.spin))
    }

    private var blink: Bool {
        // Slow cat blink every few seconds.
        time.truncatingRemainder(dividingBy: 4.3) < 0.14
    }

    @ViewBuilder
    private var pose: some View {
        switch frame.pose {
        case .hidden:
            Color.clear
        case .walk, .run:
            if WalkerSprites.hasWalkCycle {
                SpriteImage(sprite: MurzikSprite.walkCycle[frame.walkFrame])
            } else {
                WalkerSideCat(mood: mood, phase: frame.walkPhase, legs: .walk, time: time, size: size, eyesClosed: blink)
            }
        case .stand:
            sprite(.walk0) {
                WalkerSideCat(mood: mood, phase: 0, legs: .walk, time: time, size: size, eyesClosed: blink)
            }
        case .jump:
            sprite(.walk2) {
                WalkerSideCat(mood: mood, phase: 0, legs: .leap, time: time, size: size)
            }
        case .pounce:
            sprite(.playful) {
                WalkerSideCat(mood: .playful, phase: 0, legs: .crouch, time: time, size: size)
            }
        case .stretch:
            sprite(.stretch) {
                WalkerSideCat(mood: .sleepy, phase: 0, legs: .stretch, time: time, size: size)
            }
        case .dangle:
            sprite(.surprised) {
                WalkerSideCat(mood: .surprised, phase: 0, legs: .dangle, time: time, size: size)
            }
        case .sitFront:
            sprite(MurzikSprite.forMood(mood)) { sitting(mood: mood) }
        case .sitSide:
            sprite(.sitSide) { sitting(mood: mood) }
        case .groom:
            sprite(.groom) { sitting(mood: .happy, closed: true) }
        case .surprised:
            sprite(.surprised) { sitting(mood: .surprised) }
        case .loaf:
            sprite(.sleepy) { sitting(mood: .sleepy, scale: 0.92) }
        case .sleep:
            sprite(.sleeping) { WalkerCurledCat(size: size) }
        case .peekDown:
            sprite(.peek) { WalkerPeekCat(mood: mood == .sleeping ? .idle : mood, size: size, eyesClosed: blink) }
        }
    }

    @ViewBuilder
    private func sprite<Fallback: View>(_ sprite: MurzikSprite, @ViewBuilder fallback: () -> Fallback) -> some View {
        if WalkerSprites.has(sprite) {
            SpriteImage(sprite: sprite)
        } else {
            fallback()
        }
    }

    private func sitting(mood: MurzikMood, closed: Bool = false, scale: CGFloat = 1) -> some View {
        CatFigure(
            mood: mood,
            eyesClosed: closed || blink,
            tailAngle: sin(time * 2.1) * 9,
            breath: 1
        )
        .accessibilityHidden(true)
        .frame(width: size * 0.54 * scale, height: size * 0.71 * scale)
        .frame(width: size, height: size, alignment: .bottom)
        .offset(y: -size * 0.02)
    }
}

/// 2D side-view Murzik (faces right, feet on the bottom edge) used until the 3D walk sprites exist.
struct WalkerSideCat: View {
    enum Legs { case walk, leap, crouch, stretch, dangle }

    var mood: MurzikMood
    /// Walk-cycle phase in sprite frames (8 frames per stride cycle).
    var phase: Double
    var legs: Legs = .walk
    var time: Double = 0
    var size: CGFloat = IslandGeometry.catBox
    var eyesClosed = false

    var body: some View {
        let s = size
        let cycle = phase / 8 * 2 * .pi
        let angles = legAngles(cycle: cycle)
        let lift: CGFloat = legs == .walk ? s * 0.022 * CGFloat(1 - abs(sin(cycle))) : 0
        let crouch: CGFloat = legs == .crouch ? s * 0.08 : (legs == .stretch ? s * 0.03 : 0)
        let bodyY = s * 0.61 - lift + crouch
        let legLength = s * (legs == .crouch ? 0.17 : 0.24)
        let attachY = bodyY + s * 0.08
        let headY = s * (legs == .stretch ? 0.50 : 0.40) - lift + crouch * 0.6

        ZStack(alignment: .topLeading) {
            WalkerTail(time: time, wagFast: legs == .crouch)
                .stroke(MurzikPalette.rim, style: StrokeStyle(lineWidth: s * 0.10, lineCap: .round))
                .overlay(
                    WalkerTail(time: time, wagFast: legs == .crouch)
                        .stroke(MurzikPalette.furMid, style: StrokeStyle(lineWidth: s * 0.062, lineCap: .round))
                )
                .offset(y: crouch - lift)

            // Far legs (slightly darker), then body, then near legs.
            leg(x: 0.30, attachY: attachY, length: legLength, angle: angles.backFar, far: true)
            leg(x: 0.64, attachY: attachY, length: legLength, angle: angles.frontFar, far: true)

            Capsule()
                .fill(LinearGradient(colors: [MurzikPalette.furTop, MurzikPalette.furBottom], startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().stroke(MurzikPalette.rim, lineWidth: s * 0.022))
                .frame(width: s * 0.56, height: s * 0.27)
                .rotationEffect(.degrees(legs == .stretch ? 8 : 0))
                .position(x: s * 0.48, y: bodyY)

            leg(x: 0.37, attachY: attachY, length: legLength, angle: angles.backNear, far: false)
            leg(x: 0.71, attachY: attachY, length: legLength, angle: angles.frontNear, far: false)

            CatFace(mood: mood, eyesClosed: eyesClosed, detail: .compact)
                .accessibilityHidden(true)
                .frame(width: s * 0.42, height: s * 0.42)
                .rotationEffect(.degrees(legs == .leap ? -8 : sin(time * 1.3) * 3))
                .position(x: s * 0.75, y: headY)
        }
        .frame(width: s, height: s)
    }

    private struct Angles { var backNear, backFar, frontNear, frontFar: Double }

    /// Positive angle = foot swings backwards (for a cat facing right).
    private func legAngles(cycle: Double) -> Angles {
        switch legs {
        case .walk:
            let a = 26 * sin(cycle)
            return Angles(backNear: a, backFar: -a, frontNear: -a, frontFar: a)
        case .leap:
            return Angles(backNear: 48, backFar: 40, frontNear: -42, frontFar: -34)
        case .crouch:
            return Angles(backNear: 30, backFar: 24, frontNear: -32, frontFar: -26)
        case .stretch:
            return Angles(backNear: 6, backFar: 2, frontNear: -38, frontFar: -30)
        case .dangle:
            let a = 9 * sin(time * 6)
            return Angles(backNear: a, backFar: a * 0.7, frontNear: -a, frontFar: -a * 0.7)
        }
    }

    private func leg(x: CGFloat, attachY: CGFloat, length: CGFloat, angle: Double, far: Bool) -> some View {
        let s = size
        let width = s * 0.09
        return Capsule()
            .fill(far ? MurzikPalette.furBottom : MurzikPalette.furMid)
            .overlay(Capsule().stroke(MurzikPalette.rim.opacity(far ? 0.6 : 1), lineWidth: s * 0.016))
            .frame(width: width, height: length)
            .rotationEffect(.degrees(angle), anchor: .top)
            .position(x: s * x, y: attachY + length / 2)
    }
}

/// Murzik's tail for the side view: from the rump, curving up and back, tip swaying.
struct WalkerTail: Shape {
    var time: Double
    var wagFast = false

    func path(in rect: CGRect) -> Path {
        let s = rect.width
        let sway = CGFloat(sin(time * (wagFast ? 9 : 2.6))) * s * 0.05
        var path = Path()
        path.move(to: CGPoint(x: s * 0.24, y: s * 0.58))
        path.addCurve(
            to: CGPoint(x: s * 0.08 + sway, y: s * 0.20),
            control1: CGPoint(x: s * 0.06, y: s * 0.60),
            control2: CGPoint(x: s * 0.02 + sway * 0.5, y: s * 0.36)
        )
        return path
    }
}

/// Curled-up sleeping Murzik (2D fallback for `murzik_sleeping`).
struct WalkerCurledCat: View {
    var size: CGFloat

    var body: some View {
        let s = size
        ZStack(alignment: .topLeading) {
            Ellipse()
                .fill(LinearGradient(colors: [MurzikPalette.furTop, MurzikPalette.furBottom], startPoint: .top, endPoint: .bottom))
                .overlay(Ellipse().stroke(MurzikPalette.rim, lineWidth: s * 0.022))
                .frame(width: s * 0.70, height: s * 0.32)
                .position(x: s * 0.55, y: s * 0.80)
            Path { path in
                path.move(to: CGPoint(x: s * 0.86, y: s * 0.80))
                path.addQuadCurve(to: CGPoint(x: s * 0.34, y: s * 0.93), control: CGPoint(x: s * 0.82, y: s * 1.0))
            }
            .stroke(MurzikPalette.rim, style: StrokeStyle(lineWidth: s * 0.10, lineCap: .round))
            Path { path in
                path.move(to: CGPoint(x: s * 0.86, y: s * 0.80))
                path.addQuadCurve(to: CGPoint(x: s * 0.34, y: s * 0.93), control: CGPoint(x: s * 0.82, y: s * 1.0))
            }
            .stroke(MurzikPalette.furMid, style: StrokeStyle(lineWidth: s * 0.062, lineCap: .round))
            CatFace(mood: .sleeping, detail: .compact)
                .accessibilityHidden(true)
                .frame(width: s * 0.40, height: s * 0.40)
                .rotationEffect(.degrees(-12))
                .position(x: s * 0.28, y: s * 0.76)
        }
        .frame(width: s, height: s)
    }
}

/// Head and front paws rising from the bottom edge (2D fallback for `murzik_peek`).
struct WalkerPeekCat: View {
    var mood: MurzikMood
    var size: CGFloat
    var eyesClosed = false

    var body: some View {
        let s = size
        ZStack(alignment: .topLeading) {
            CatFace(mood: mood, eyesClosed: eyesClosed, detail: .compact)
                .accessibilityHidden(true)
                .frame(width: s * 0.56, height: s * 0.56)
                .position(x: s * 0.5, y: s * 0.66)
            paw.position(x: s * 0.34, y: s * 0.95)
            paw.position(x: s * 0.66, y: s * 0.95)
        }
        .frame(width: s, height: s)
    }

    private var paw: some View {
        Capsule()
            .fill(MurzikPalette.furMid)
            .overlay(Capsule().stroke(MurzikPalette.rim, lineWidth: size * 0.02))
            .frame(width: size * 0.15, height: size * 0.10)
    }
}
