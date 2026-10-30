import CoreGraphics
import Foundation

/// What Murzik's body is doing in a frame (mapped to a sprite or to the 2D fallback drawing).
enum WalkerPose: Equatable, Sendable {
    case walk, run, stand
    case sitFront, sitSide, loaf, sleep
    case peekDown          // hanging upside down from the island's bottom edge
    case jump, pounce, stretch, groom, surprised, dangle
    case hidden            // inside the island
}

/// One rendered state of the walker.
struct WalkerFrame: Equatable {
    /// Bottom-centre of the cat box (between the feet). For `upsideDown` frames: the top-centre
    /// of the box, i.e. the line where his body disappears into the island.
    var feet: CGPoint
    var pose: WalkerPose = .sitFront
    var facingLeft = false
    /// Continuous walk-cycle position in sprite frames (8 per cycle).
    var walkPhase: Double = 0
    /// Squash & stretch, anchored at the feet.
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    /// Lean in degrees around the feet (positive = clockwise).
    var tilt: Double = 0
    /// Spin in degrees around the centre of the box (flips).
    var spin: Double = 0
    var upsideDown = false
    var bubble: String?

    var walkFrame: Int {
        let index = Int(walkPhase.rounded(.down)) % 8
        return index < 0 ? index + 8 : index
    }

    /// Centre of the cat box on screen.
    func boxCenter(size: CGFloat = IslandGeometry.catBox) -> CGPoint {
        CGPoint(x: feet.x, y: upsideDown ? feet.y + size / 2 : feet.y - size / 2)
    }
}

/// A piece of choreography with a fixed duration.
struct WalkerSegment {
    enum Kind {
        case walk(from: CGPoint, to: CGPoint, speed: CGFloat)
        case hop(from: CGPoint, to: CGPoint, height: CGFloat, facingLeft: Bool)
        case land(at: CGPoint, facingLeft: Bool)
        case hold(WalkerPose, at: CGPoint, facingLeft: Bool, bubble: String?)
        case peekDown(at: CGPoint, facingLeft: Bool)
        case drop(from: CGPoint, to: CGPoint, facingLeft: Bool)
        case peekSide(from: CGPoint, to: CGPoint, facingLeft: Bool)
        /// Follows the butterfly along the floor and ends with a pounce. Its end point is only known
        /// at run time, so the simulation re-plans after it.
        case chase(y: CGFloat, lower: CGFloat, upper: CGFloat, startX: CGFloat)
    }

    var kind: Kind
    var duration: Double
    /// Where the segment ends (nominal; see `.chase`).
    var end: CGPoint
    var endSurface: WalkerSurface
    var endFacingLeft: Bool

    var replanAfter: Bool {
        if case .chase = kind { return true }
        return false
    }

    /// Segments that may be cut short when his mood changes.
    var isInterruptible: Bool {
        switch kind {
        case .hold, .chase: return true
        default: return false
        }
    }
}

/// Pure motion maths: easing, durations and sampling a segment at a time.
enum WalkerMotion {
    static let walkSpeed: CGFloat = 40
    static let accel = 0.18
    static let crouchTime = 0.11
    static let landDuration = 0.34
    static let pounceTime = 0.55

    static func walkDuration(distance: CGFloat, speed: CGFloat) -> Double {
        max(0.25, Double(distance / max(speed, 1)) / (1 - accel))
    }

    static func hopDuration(from: CGPoint, to: CGPoint, height: CGFloat) -> Double {
        let arc = Double(height + abs(to.y - from.y) / 2)
        return crouchTime + 0.24 + arc / 170 + Double(abs(to.x - from.x)) / 650
    }

    /// Distance per sprite frame: ~11 fps when walking, ~18 fps when running, so the paws
    /// stay planted instead of sliding.
    static func stride(speed: CGFloat) -> Double {
        Double(speed) / (speed > 80 ? 18 : 11)
    }

    /// Trapezoidal velocity profile: accelerate, cruise, decelerate. Maps 0…1 → 0…1.
    static func trapezoid(_ u: Double, accel a: Double = accel) -> Double {
        let u = min(max(u, 0), 1)
        let vmax = 1 / (1 - a)
        if u < a { return 0.5 * vmax * u * u / a }
        if u < 1 - a { return 0.5 * vmax * a + vmax * (u - a) }
        let r = 1 - u
        return 1 - 0.5 * vmax * r * r / a
    }

    static func smooth(_ u: Double) -> Double {
        let u = min(max(u, 0), 1)
        return u * u * (3 - 2 * u)
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ u: Double) -> CGFloat {
        a + (b - a) * CGFloat(u)
    }

    /// Damped squash after touching down; `t` in seconds since landing.
    static func landingSquash(_ t: Double) -> CGFloat {
        CGFloat(1 - 0.26 * exp(-10 * t) * cos(20 * t))
    }

    /// Samples `segment` at local time `t`. `clock` is the absolute simulation time (for idle
    /// motion such as breathing and for the butterfly).
    static func sample(_ segment: WalkerSegment, at t: Double, clock: Double, geometry geo: IslandGeometry) -> WalkerFrame {
        let duration = segment.duration
        let u = duration > 0 ? min(max(t / duration, 0), 1) : 1
        switch segment.kind {
        case let .walk(from, to, speed):
            let p = trapezoid(u)
            let run = speed > 80
            let left = to.x < from.x
            var frame = WalkerFrame(feet: CGPoint(x: lerp(from.x, to.x, p), y: from.y), pose: run ? .run : .walk, facingLeft: left)
            frame.walkPhase = Double(abs(to.x - from.x)) * p / stride(speed: speed)
            if run { frame.tilt = left ? -4 : 4 }
            return frame

        case let .hop(from, to, height, left):
            let dir: Double = left ? -1 : 1
            if t < crouchTime {
                let c = smooth(t / crouchTime)
                var frame = WalkerFrame(feet: from, pose: .pounce, facingLeft: left)
                frame.scaleY = CGFloat(1 - 0.2 * c)
                frame.scaleX = CGFloat(1 + 0.12 * c)
                return frame
            }
            let flight = max(duration - crouchTime, 0.01)
            let f = min(max((t - crouchTime) / flight, 0), 1)
            let arc = height + abs(to.y - from.y) / 2
            let x = lerp(from.x, to.x, f)
            let y = lerp(from.y, to.y, f) - arc * CGFloat(4 * f * (1 - f))
            var frame = WalkerFrame(feet: CGPoint(x: x, y: y), pose: .jump, facingLeft: left)
            let stretch = 0.16 * (1 - f) * (1 - f) + 0.06 * pow(f, 4)
            frame.scaleY = CGFloat(1 + stretch)
            frame.scaleX = CGFloat(1 - stretch * 0.6)
            frame.tilt = dir * -14 * cos(.pi * f)
            frame.walkPhase = 2
            return frame

        case let .land(at, left):
            var frame = WalkerFrame(feet: at, pose: .stand, facingLeft: left)
            let s = landingSquash(t)
            frame.scaleY = s
            frame.scaleX = 1 + (1 - s) * 0.7
            return frame

        case let .hold(pose, at, left, bubble):
            var frame = WalkerFrame(feet: at, pose: pose, facingLeft: left)
            switch pose {
            case .sleep:
                frame.scaleY = CGFloat(1 + 0.03 * sin(clock * 1.5))
                frame.scaleX = CGFloat(1 - 0.012 * sin(clock * 1.5))
            case .loaf:
                frame.scaleY = CGFloat(1 + 0.02 * sin(clock * 1.8))
            case .stretch:
                let s = sin(.pi * u)
                frame.scaleX = CGFloat(1 + 0.10 * s)
                frame.scaleY = CGFloat(1 - 0.08 * s)
            case .pounce:
                // Butt wiggle before the leap.
                frame.tilt = sin(clock * 22) * 3
            case .surprised:
                let s = landingSquash(t * 0.7)
                frame.scaleY = 2 - s
            case .hidden:
                break
            default:
                frame.scaleY = CGFloat(1 + 0.012 * sin(clock * 2.4))
            }
            if let bubble, u > 0.06, u < 0.94 { frame.bubble = bubble }
            return frame

        case let .peekDown(at, left):
            // Slides head-first out of the island's bottom edge, hangs and sways, then lets go.
            let depth = IslandGeometry.catBox * 0.62
            let emerge = smooth(t / 0.45)
            var frame = WalkerFrame(feet: CGPoint(x: at.x, y: at.y - 2 - (1 - CGFloat(emerge)) * depth), pose: .peekDown, facingLeft: left)
            frame.upsideDown = true
            frame.spin = 180
            frame.tilt = 8 * sin(clock * 2.6) * emerge
            return frame

        case let .drop(from, to, left):
            let size = IslandGeometry.catBox
            let c0 = CGPoint(x: from.x, y: from.y - 2 + size / 2)
            let c1 = CGPoint(x: to.x, y: to.y - size / 2)
            let cx = lerp(c0.x, c1.x, u)
            let cy = lerp(c0.y, c1.y, u * u) - 12 * CGFloat(sin(.pi * u))
            var frame = WalkerFrame(feet: CGPoint(x: cx, y: cy + size / 2), pose: .jump, facingLeft: left)
            frame.spin = 180 + (left ? -180 : 180) * smooth(u)
            frame.walkPhase = 2
            return frame

        case let .peekSide(from, to, left):
            let emerge = smooth(t / 0.5)
            var frame = WalkerFrame(feet: CGPoint(x: lerp(from.x, to.x, emerge), y: to.y), pose: .stand, facingLeft: left)
            // Curious head bob while looking around.
            frame.tilt = sin(clock * 3.2) * 5 * emerge
            return frame

        case let .chase(y, lower, upper, startX):
            let startClock = clock - t
            let runTime = max(duration - pounceTime, 0)
            func target(_ tt: Double) -> CGFloat {
                min(max(WalkerButterfly.position(at: startClock + tt - 0.35, geometry: geo).x, lower), upper)
            }
            func chaseX(_ tt: Double) -> CGFloat {
                lerp(startX, target(tt), smooth(tt / 0.9))
            }
            let tt = min(t, runTime)
            let x = chaseX(tt)
            let butterflyX = WalkerButterfly.position(at: clock, geometry: geo).x
            let left = butterflyX < x
            if t < runTime {
                let v = Double(abs(chaseX(tt + 0.04) - x)) / 0.04
                var frame = WalkerFrame(feet: CGPoint(x: x, y: y), facingLeft: left)
                if v > 70 {
                    frame.pose = .run
                    frame.walkPhase = clock * 18
                    frame.tilt = left ? -4 : 4
                } else if v > 10 {
                    frame.pose = .walk
                    frame.walkPhase = clock * 11
                } else {
                    frame.pose = .pounce
                    frame.tilt = sin(clock * 22) * 3
                }
                return frame
            }
            let f = min(max((t - runTime) / pounceTime, 0), 1)
            var frame = WalkerFrame(feet: CGPoint(x: x, y: y - 30 * CGFloat(4 * f * (1 - f))), pose: .jump, facingLeft: left)
            frame.tilt = (left ? -1 : 1) * -14 * cos(.pi * f)
            frame.scaleY = CGFloat(1 + 0.12 * (1 - f))
            frame.walkPhase = 2
            return frame
        }
    }
}

/// A little butterfly that flutters around the island when Murzik is playful.
enum WalkerButterfly {
    static func position(at t: Double, geometry geo: IslandGeometry) -> CGPoint {
        let p = geo.pill
        let x = p.midX + (p.width / 2 + 46) * CGFloat(sin(t * 0.61)) + 14 * CGFloat(sin(t * 1.9))
        let y = p.maxY + 16 + 9 * CGFloat(sin(t * 1.3)) + 5 * CGFloat(sin(t * 3.1))
        return CGPoint(x: x, y: y)
    }
}
