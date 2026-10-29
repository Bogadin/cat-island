import CoreGraphics
import Foundation

/// Small deterministic RNG (SplitMix64) so plans are reproducible in tests and UI screenshots.
struct WalkerRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func chance(_ p: Double) -> Bool {
        Double.random(in: 0..<1, using: &self) < p
    }

    mutating func value(_ range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &self)
    }

    mutating func point(_ range: ClosedRange<CGFloat>) -> CGFloat {
        CGFloat.random(in: range, using: &self)
    }
}

/// Builds a continuous chain of segments: every segment starts where the previous one ended.
struct WalkerScript {
    let geo: IslandGeometry
    private(set) var segments: [WalkerSegment] = []
    private(set) var point: CGPoint
    private(set) var surface: WalkerSurface
    private(set) var facingLeft: Bool

    init(geometry: IslandGeometry, point: CGPoint, surface: WalkerSurface, facingLeft: Bool) {
        geo = geometry
        self.point = point
        self.surface = surface
        self.facingLeft = facingLeft
    }

    var duration: Double { segments.reduce(0) { $0 + $1.duration } }

    /// The plan is finished when a segment whose end is only known at run time was added.
    var isOpenEnded: Bool { segments.last?.replanAfter ?? false }

    private mutating func append(_ kind: WalkerSegment.Kind, duration: Double, end: CGPoint, surface newSurface: WalkerSurface, facingLeft left: Bool) {
        guard !isOpenEnded else { return }
        segments.append(WalkerSegment(kind: kind, duration: max(duration, 0.05), end: end, endSurface: newSurface, endFacingLeft: left))
        point = end
        surface = newSurface
        facingLeft = left
    }

    // MARK: Primitives

    mutating func walk(toX x: CGFloat, speed: CGFloat = WalkerMotion.walkSpeed, endSurface: WalkerSurface? = nil) {
        let target = CGPoint(x: x, y: point.y)
        let distance = abs(x - point.x)
        guard distance > 1 else {
            if let endSurface { surface = endSurface }
            return
        }
        append(
            .walk(from: point, to: target, speed: speed),
            duration: WalkerMotion.walkDuration(distance: distance, speed: speed),
            end: target, surface: endSurface ?? surface, facingLeft: x < point.x
        )
    }

    mutating func hop(to target: CGPoint, surface newSurface: WalkerSurface, height: CGFloat = 10, land: Bool = true) {
        let dx = target.x - point.x
        let left = abs(dx) < 1 ? facingLeft : dx < 0
        append(
            .hop(from: point, to: target, height: height, facingLeft: left),
            duration: WalkerMotion.hopDuration(from: point, to: target, height: height),
            end: target, surface: newSurface, facingLeft: left
        )
        if land {
            append(.land(at: target, facingLeft: left), duration: WalkerMotion.landDuration, end: target, surface: newSurface, facingLeft: left)
        }
    }

    mutating func hold(_ pose: WalkerPose, _ duration: Double, bubble: String? = nil, facingLeft face: Bool? = nil) {
        let left = face ?? facingLeft
        append(.hold(pose, at: point, facingLeft: left, bubble: bubble), duration: duration, end: point, surface: surface, facingLeft: left)
    }

    /// Faces the island from wherever he is.
    var towardIsland: Bool { point.x > geo.pill.midX }

    // MARK: Moves around the island

    /// Gets down to the floor under the island (and optionally walks to `x` there).
    mutating func goUnder(x: CGFloat? = nil, speed: CGFloat = WalkerMotion.walkSpeed) {
        switch surface {
        case .under:
            break
        case .ledgeLeft:
            walk(toX: geo.leftLedgeX, speed: speed)
            hop(to: CGPoint(x: geo.leftLedgeX - 14, y: geo.underFloorY), surface: .under, height: 6)
        case .ledgeRight:
            walk(toX: geo.rightLedgeX, speed: speed)
            hop(to: CGPoint(x: geo.rightLedgeX + 14, y: geo.underFloorY), surface: .under, height: 6)
        case .inside:
            peekDownAndDrop(x: geo.clampUnderPill(x ?? geo.pill.midX))
        case .air:
            hop(to: CGPoint(x: geo.clampToPatrol(x ?? point.x), y: geo.underFloorY), surface: .under, height: 6)
        }
        if let x { walk(toX: geo.clampToPatrol(x), speed: speed) }
    }

    /// Walks/hops to the ledge beside the island, on the status-bar line.
    mutating func goLedge(left: Bool, speed: CGFloat = WalkerMotion.walkSpeed) {
        guard geo.hasIsland else { return }
        let ledge: WalkerSurface = left ? .ledgeLeft : .ledgeRight
        let ledgeX = left ? geo.leftLedgeX : geo.rightLedgeX
        if surface == ledge {
            walk(toX: ledgeX, speed: speed)
            return
        }
        if surface == .inside {
            peekOutSide(left: left)
            return
        }
        goUnder(speed: speed)
        walk(toX: left ? ledgeX - 14 : ledgeX + 14, speed: speed)
        hop(to: CGPoint(x: ledgeX, y: geo.ledgeY), surface: ledge, height: 9)
    }

    /// From a ledge, walks sideways into the island and disappears.
    mutating func slipIn(speed: CGFloat = 30) {
        guard surface == .ledgeLeft || surface == .ledgeRight else { return }
        let left = surface == .ledgeLeft
        walk(toX: left ? geo.insideLeftX : geo.insideRightX, speed: speed, endSurface: .inside)
    }

    /// From the floor under the island, crouches, wiggles and leaps up into it.
    mutating func hopInto(x: CGFloat) {
        guard geo.hasIsland else { return }
        goUnder(x: geo.clampUnderPill(x))
        hold(.pounce, 0.6)
        let target = CGPoint(x: point.x + (facingLeft ? -10 : 10), y: geo.insideFeetY)
        hop(to: target, surface: .inside, height: 4, land: false)
    }

    /// Hidden while he moves inside the island to its other end.
    mutating func travelInside(toLeft: Bool, duration: Double) {
        guard surface == .inside else { return }
        let target = CGPoint(x: toLeft ? geo.insideLeftX : geo.insideRightX, y: geo.ledgeY)
        point = target
        hold(.hidden, duration, facingLeft: toLeft)
    }

    /// From inside, pokes his head out of one end of the island, then steps out onto the ledge.
    mutating func peekOutSide(left: Bool) {
        guard surface == .inside else { return }
        let inner = CGPoint(x: left ? geo.insideLeftX : geo.insideRightX, y: geo.ledgeY)
        let peek = CGPoint(x: left ? geo.peekLeftX : geo.peekRightX, y: geo.ledgeY)
        append(.peekSide(from: inner, to: peek, facingLeft: left), duration: 2.3, end: peek, surface: .inside, facingLeft: left)
        walk(toX: left ? geo.leftLedgeX : geo.rightLedgeX, speed: 34, endSurface: left ? .ledgeLeft : .ledgeRight)
    }

    /// From inside, hangs head-first out of the island's bottom edge, then flips down to the floor.
    mutating func peekDownAndDrop(x: CGFloat) {
        guard surface == .inside else { return }
        let cut = CGPoint(x: x, y: geo.pill.maxY)
        append(.peekDown(at: cut, facingLeft: facingLeft), duration: 2.4, end: cut, surface: .inside, facingLeft: facingLeft)
        let landing = CGPoint(x: x + (facingLeft ? -8 : 8), y: geo.underFloorY)
        append(.drop(from: cut, to: landing, facingLeft: facingLeft), duration: 0.42, end: landing, surface: .under, facingLeft: facingLeft)
        append(.land(at: landing, facingLeft: facingLeft), duration: WalkerMotion.landDuration, end: landing, surface: .under, facingLeft: facingLeft)
    }

    /// Runs after the butterfly; open-ended (the simulation re-plans afterwards).
    mutating func chase(duration: Double) {
        goUnder()
        let range = geo.patrolRange
        append(
            .chase(y: geo.underFloorY, lower: range.lowerBound, upper: range.upperBound, startX: point.x),
            duration: duration, end: point, surface: .under, facingLeft: facingLeft
        )
    }

    /// Quick reaction to being petted: a happy hop where he is.
    mutating func petHop() {
        switch surface {
        case .under, .ledgeLeft, .ledgeRight:
            hop(to: point, surface: surface, height: 16)
        default:
            hop(to: CGPoint(x: geo.clampToPatrol(point.x), y: geo.underFloorY), surface: .under, height: 10)
        }
    }

    /// Falls from wherever he was dropped back to the floor under the island.
    mutating func fallToFloor() {
        let target = CGPoint(x: geo.clampToPatrol(point.x), y: geo.underFloorY)
        let height: CGFloat = point.y < target.y ? 4 : (point.y - target.y) * 0.25 + 14
        hop(to: target, surface: .under, height: height)
    }
}

/// Decides what Murzik does next, based on his mood and where he is.
struct WalkerPlanner {
    static let meow = "מיאו"
    static let heart = "♥"

    let geo: IslandGeometry
    var rng: WalkerRandom

    init(geometry: IslandGeometry, seed: UInt64) {
        geo = geometry
        rng = WalkerRandom(seed: seed)
    }

    /// Where he is when the walker first appears: hiding inside the island (or on the floor
    /// when there is no island).
    var startFrame: WalkerFrame {
        if geo.hasIsland {
            return WalkerFrame(feet: CGPoint(x: geo.pill.midX, y: geo.insideFeetY), pose: .hidden)
        }
        return WalkerFrame(feet: CGPoint(x: geo.pill.midX, y: geo.underFloorY), pose: .sitFront)
    }

    mutating func plan(mood: MurzikMood, from frame: WalkerFrame, showcase: Bool = false) -> [WalkerSegment] {
        let surface = geo.surface(at: frame.feet, hidden: frame.pose == .hidden)
        var s = WalkerScript(geometry: geo, point: frame.feet, surface: surface, facingLeft: frame.facingLeft)
        if !geo.hasIsland {
            planWithoutIsland(&s, mood: mood)
        } else if showcase, mood != .sleeping {
            planShowcase(&s)
        } else {
            switch mood {
            case .sleeping: planSleeping(&s)
            case .sleepy: planSleepy(&s)
            case .hungry: planHungry(&s)
            case .playful, .excited: planPlayful(&s, excited: mood == .excited)
            case .surprised: planSurprised(&s)
            case .idle, .blinking, .happy, .loving: planCalm(&s, mood: mood)
            }
        }
        if s.segments.isEmpty {
            s.hold(.sitFront, 1.5)
        }
        return s.segments
    }

    // MARK: Plans

    /// First appearance: drops out of the island, walks over, hops onto the ledge, slips back into
    /// the island and peeks out of the other end.
    private mutating func planShowcase(_ s: inout WalkerScript) {
        if s.surface == .inside {
            s.peekDownAndDrop(x: geo.pill.midX + 18)
        }
        s.hold(.sitFront, 1.0)
        s.goLedge(left: true)
        s.hold(.sitFront, 1.6, facingLeft: false)
        s.slipIn()
        s.travelInside(toLeft: false, duration: 1.0)
        s.peekOutSide(left: false)
        s.hold(.sitFront, 1.4, facingLeft: true)
        s.goUnder(x: geo.pill.midX + 30)
        s.hold(.groom, 2.2)
    }

    private mutating func planCalm(_ s: inout WalkerScript, mood: MurzikMood) {
        if s.surface == .inside {
            if rng.chance(0.5) {
                s.peekDownAndDrop(x: rng.point(geo.underPillRange))
            } else {
                s.peekOutSide(left: rng.chance(0.5))
            }
            s.hold(.sitFront, rng.value(1.2...2.4), facingLeft: s.towardIsland)
            return
        }
        let roll = rng.value(0...1)
        if roll < 0.3 {
            // Patrol under the island and sit for a while.
            s.goUnder(x: rng.point(geo.patrolRange))
            s.hold(.sitFront, rng.value(2.0...3.8), facingLeft: s.towardIsland)
            if rng.chance(0.45) { s.hold(.groom, rng.value(1.8...2.6)) }
        } else if roll < 0.65 {
            // Around the island: sit beside it, slip in, come out somewhere else.
            let left = rng.chance(0.5)
            s.goLedge(left: left)
            s.hold(left ? .sitFront : .sitSide, rng.value(1.4...2.6), facingLeft: !left)
            s.slipIn()
            s.travelInside(toLeft: !left, duration: rng.value(0.9...2.2))
            if rng.chance(0.55) {
                s.peekOutSide(left: !left)
                s.hold(.sitFront, rng.value(1.5...3.0), facingLeft: left)
            } else {
                s.peekDownAndDrop(x: rng.point(geo.underPillRange))
                s.hold(.sitFront, 1.2, facingLeft: s.towardIsland)
            }
        } else if roll < 0.85 {
            // Leap up into the island from below, then pop out.
            s.hopInto(x: rng.point(geo.underPillRange))
            s.travelInside(toLeft: rng.chance(0.5), duration: rng.value(0.8...1.8))
            if rng.chance(0.5) {
                s.peekDownAndDrop(x: rng.point(geo.underPillRange))
            } else {
                s.peekOutSide(left: rng.chance(0.5))
                s.hold(.sitFront, 1.6, facingLeft: s.towardIsland)
            }
        } else {
            // Stretch, groom, look around.
            s.hold(.stretch, 1.5)
            s.hold(.groom, rng.value(2.0...2.8))
            s.hold(mood == .loving ? .sitFront : .sitSide, rng.value(1.5...2.5))
        }
    }

    private mutating func planSleeping(_ s: inout WalkerScript) {
        if s.surface != .ledgeLeft {
            s.goLedge(left: true, speed: 24)
            s.walk(toX: geo.leftLedgeX - 12, speed: 20)
            s.hold(.loaf, 1.4, facingLeft: false)
        }
        s.hold(.sleep, 12, facingLeft: false)
    }

    private mutating func planSleepy(_ s: inout WalkerScript) {
        let left = s.surface == .ledgeRight ? false : (s.surface == .ledgeLeft ? true : rng.chance(0.6))
        s.goLedge(left: left, speed: 24)
        s.hold(.stretch, 1.6)
        s.hold(.loaf, rng.value(6...10), facingLeft: !left)
    }

    private mutating func planHungry(_ s: inout WalkerScript) {
        s.goUnder(speed: 55)
        let range = (geo.pill.minX - 30)...(geo.pill.maxX + 30)
        for _ in 0..<Int.random(in: 2...3, using: &rng) {
            s.walk(toX: geo.clampToPatrol(rng.point(range)), speed: 58)
            s.hold(.sitFront, rng.value(1.3...1.8), bubble: Self.meow, facingLeft: s.towardIsland)
        }
        if rng.chance(0.3) {
            // Checks whether there is food up in the island.
            s.hopInto(x: rng.point(geo.underPillRange))
            s.travelInside(toLeft: rng.chance(0.5), duration: 1.0)
            s.peekDownAndDrop(x: rng.point(geo.underPillRange))
        }
    }

    private mutating func planPlayful(_ s: inout WalkerScript, excited: Bool) {
        if s.surface == .inside {
            s.peekDownAndDrop(x: rng.point(geo.underPillRange))
        }
        let roll = rng.value(0...1)
        if roll < 0.45 {
            s.chase(duration: rng.value(5.5...7.5))
            return
        }
        if roll < 0.8 {
            // Zoomies!
            s.goUnder(speed: 120)
            let range = geo.patrolRange
            s.walk(toX: range.lowerBound, speed: 150)
            s.hop(to: CGPoint(x: range.lowerBound + 34, y: geo.underFloorY), surface: .under, height: 22)
            s.walk(toX: range.upperBound, speed: 165)
            s.hold(.pounce, 0.6, facingLeft: true)
            s.walk(toX: geo.pill.midX + rng.point(-30...30), speed: 140)
            if excited {
                s.hop(to: s.point, surface: .under, height: 26)
                s.hop(to: s.point, surface: .under, height: 20)
            }
            return
        }
        s.hopInto(x: rng.point(geo.underPillRange))
        s.travelInside(toLeft: rng.chance(0.5), duration: 0.7)
        s.peekOutSide(left: rng.chance(0.5))
        s.goUnder(speed: 120)
    }

    private mutating func planSurprised(_ s: inout WalkerScript) {
        if s.surface == .inside {
            s.peekDownAndDrop(x: rng.point(geo.underPillRange))
        }
        if s.surface == .air { s.goUnder() }
        s.hold(.surprised, 1.0)
        s.hop(to: s.point, surface: s.surface, height: 14)
        s.hold(.sitFront, 1.5)
    }

    private mutating func planWithoutIsland(_ s: inout WalkerScript, mood: MurzikMood) {
        s.goUnder()
        switch mood {
        case .sleeping:
            s.hold(.sleep, 12)
        case .sleepy:
            s.hold(.loaf, 8)
        case .playful, .excited:
            if rng.chance(0.5) {
                s.chase(duration: 6)
            } else {
                s.walk(toX: geo.patrolRange.lowerBound, speed: 150)
                s.walk(toX: geo.patrolRange.upperBound, speed: 160)
                s.hop(to: s.point, surface: .under, height: 22)
            }
        case .hungry:
            s.walk(toX: rng.point(geo.patrolRange), speed: 58)
            s.hold(.sitFront, 1.6, bubble: Self.meow, facingLeft: s.towardIsland)
        default:
            s.walk(toX: rng.point(geo.patrolRange))
            s.hold(.sitFront, rng.value(2...3.5), facingLeft: s.towardIsland)
            if rng.chance(0.4) { s.hold(.groom, 2.2) }
        }
    }
}
