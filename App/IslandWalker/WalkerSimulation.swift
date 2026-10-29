import CoreGraphics
import Foundation

/// Runs Murzik's choreography: plays segments from the planner, reacts to mood changes, taps
/// and drags. Not observable on purpose — the overlay's `TimelineView` pulls a snapshot each frame,
/// so nothing runs while the overlay is paused or hidden. Use from the main thread only.
final class WalkerSimulation {
    struct Effect: Identifiable {
        enum Kind { case heart }
        let id: Int
        let kind: Kind
        let start: Double
        let origin: CGPoint
    }

    struct Snapshot {
        var frame: WalkerFrame
        var time: Double
        var mood: MurzikMood
        var effects: [Effect]
        var butterfly: CGPoint?
        var butterflyAlpha: Double
        var isDragging: Bool
    }

    /// Mood override for UI tests and previews.
    var forcedMood: MurzikMood?
    var seed: UInt64

    private(set) var time: Double = 0
    private var lastDate: Date?
    private var geometry: IslandGeometry?
    private var planner: WalkerPlanner?
    private var mood: MurzikMood = .idle
    private var queue: [WalkerSegment] = []
    private var current: WalkerSegment?
    private var segmentStart: Double = 0
    private var frame = WalkerFrame(feet: .zero, pose: .hidden)
    private var needsShowcase = true
    private var replanSoon = false
    private var effects: [Effect] = []
    private var nextEffectID = 0
    private var dragPoint: CGPoint?
    private var dragTilt: Double = 0
    private var butterflyAlpha: Double = 0

    init(seed: UInt64 = UInt64(Date().timeIntervalSince1970)) {
        self.seed = seed
    }

    var currentFrame: WalkerFrame { frame }

    // MARK: Frame loop

    func advance(to date: Date, mood newMood: MurzikMood, geometry geo: IslandGeometry) -> Snapshot {
        // Clamp the step so a pause (app inactive, timeline paused) doesn't make him teleport.
        let dt = lastDate.map { min(max(date.timeIntervalSince($0), 0), 1.0 / 15) } ?? 0
        lastDate = date
        time += dt
        step(mood: newMood, geometry: geo, dt: dt)
        return snapshot()
    }

    /// Advances by a fixed `dt` (used by tests).
    func step(mood newMood: MurzikMood, geometry geo: IslandGeometry, dt: Double) {
        if geometry != geo {
            geometry = geo
            let planner = WalkerPlanner(geometry: geo, seed: seed)
            frame = planner.startFrame
            self.planner = planner
            needsShowcase = true
            queue = []
            current = nil
        }
        let mood = forcedMood ?? newMood
        if mood != self.mood {
            self.mood = mood
            replanSoon = true
        }

        let wantsButterfly = mood == .playful || mood == .excited || isChasing
        let target: Double = wantsButterfly ? 1 : 0
        butterflyAlpha += (target - butterflyAlpha) * min(1, dt * 2.5)

        effects.removeAll { time - $0.start > 1.6 }

        if let dragPoint {
            frame = WalkerFrame(feet: dragPoint, pose: .dangle, facingLeft: frame.facingLeft)
            frame.tilt = dragTilt + sin(time * 5) * 4
            dragTilt *= 0.9
            return
        }
        playSegments(geometry: geo)
    }

    private var isChasing: Bool {
        if let current, case .chase = current.kind { return true }
        return false
    }

    private func playSegments(geometry geo: IslandGeometry) {
        for _ in 0..<12 {
            if current == nil {
                if queue.isEmpty {
                    queue = makePlan()
                }
                current = queue.removeFirst()
            }
            guard let segment = current else { return }
            let local = time - segmentStart
            if replanSoon, segment.isInterruptible {
                replanSoon = false
                queue = []
                current = nil
                segmentStart = time
                continue
            }
            if local >= segment.duration {
                frame = WalkerMotion.sample(segment, at: segment.duration, clock: time, geometry: geo)
                segmentStart += segment.duration
                current = nil
                if segment.replanAfter || replanSoon {
                    replanSoon = false
                    queue = []
                    segmentStart = time
                }
                continue
            }
            frame = WalkerMotion.sample(segment, at: local, clock: time, geometry: geo)
            return
        }
    }

    private func makePlan() -> [WalkerSegment] {
        guard var planner else { return [] }
        let showcase = needsShowcase
        needsShowcase = false
        let plan = planner.plan(mood: mood, from: frame, showcase: showcase)
        self.planner = planner
        return plan
    }

    private func interrupt(with build: (inout WalkerScript) -> Void) {
        guard let geo = geometry else { return }
        let surface = geo.surface(at: frame.feet, hidden: frame.pose == .hidden)
        var script = WalkerScript(geometry: geo, point: frame.feet, surface: surface, facingLeft: frame.facingLeft)
        build(&script)
        queue = script.segments
        current = nil
        segmentStart = time
        replanSoon = false
    }

    private func snapshot() -> Snapshot {
        var butterfly: CGPoint?
        if butterflyAlpha > 0.01, let geo = geometry {
            butterfly = WalkerButterfly.position(at: time, geometry: geo)
        }
        return Snapshot(
            frame: frame, time: time, mood: mood, effects: effects,
            butterfly: butterfly, butterflyAlpha: butterflyAlpha, isDragging: dragPoint != nil
        )
    }

    // MARK: Interaction

    /// Whether he can be touched right now (not while hidden inside the island).
    var isTouchable: Bool {
        guard let geo = geometry else { return false }
        if frame.pose == .hidden { return false }
        if dragPoint != nil { return true }
        if frame.upsideDown { return true }
        return geo.surface(at: frame.feet) != .inside
    }

    /// Tap: a happy hop with a heart.
    func pet() {
        guard isTouchable, dragPoint == nil else { return }
        addHeart(at: CGPoint(x: frame.feet.x, y: frame.feet.y - (frame.upsideDown ? -20 : 34)))
        interrupt { script in
            script.petHop()
            script.hold(.sitFront, 1.3, facingLeft: script.towardIsland)
        }
    }

    func addHeart(at point: CGPoint) {
        nextEffectID += 1
        effects.append(Effect(id: nextEffectID, kind: .heart, start: time, origin: point))
    }

    /// Drag: he dangles under the finger.
    func drag(to feet: CGPoint) {
        if let old = dragPoint {
            dragTilt = min(max(dragTilt + Double(feet.x - old.x) * 1.2, -28), 28)
        }
        dragPoint = feet
        frame.feet = feet
        frame.pose = .dangle
        frame.upsideDown = false
        frame.spin = 0
    }

    /// Drop: he falls back to the floor with a bounce, shakes it off and carries on.
    func release() {
        guard dragPoint != nil else { return }
        dragPoint = nil
        frame.pose = .jump
        interrupt { script in
            script.fallToFloor()
            script.hold(.sitFront, 0.9, facingLeft: script.towardIsland)
        }
    }
}
