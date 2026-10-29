import Foundation

/// Where Murzik is on the island "stage" and what he is doing. Sent inside the Live Activity
/// content state (a few dozen bytes), so every content update can move him with an animation.
///
/// Positions are physical, left → right: 0 is the left end of the stage (the food bowl, under the
/// Feed button), 1 is the right end (the cushion, under the Pet button). In the compact island
/// positions below 0.5 are drawn in the compact leading (left) region and the rest in the trailing
/// region, so walking from 0.3 to 0.6 takes him "behind the camera" from one side to the other.
struct IslandScene: Codable, Hashable, Sendable {
    enum Pose: String, Codable, Sendable {
        /// The mood pose (`MurzikSprite.forMood`).
        case rest
        /// Walking, side view; `frame` selects the walk-cycle image.
        case walk
        /// A little jump of joy.
        case hop
        /// Eating from the bowl.
        case eat
        /// Stretching before a walk.
        case stretch
    }

    enum Effect: String, Codable, Sendable {
        case none, hearts, food, sparkles
    }

    enum CompactSide: String, Sendable {
        case leading, trailing
    }

    var position: Double
    var facingLeft: Bool
    var pose: Pose
    /// Walk-cycle frame (index into `MurzikSprite.walkCycle`).
    var frame: Int
    var effect: Effect
    /// Increases with every choreography beat; views animate on its changes.
    var step: Int
    /// Real-time paw-print trail (drawn with `ProgressView(timerInterval:)`, moves without updates).
    var trailFrom: Date?
    var trailTo: Date?

    init(
        position: Double = IslandChoreography.leftSpot,
        facingLeft: Bool = false,
        pose: Pose = .rest,
        frame: Int = 0,
        effect: Effect = .none,
        step: Int = 0,
        trailFrom: Date? = nil,
        trailTo: Date? = nil
    ) {
        self.position = position
        self.facingLeft = facingLeft
        self.pose = pose
        self.frame = frame
        self.effect = effect
        self.step = step
        self.trailFrom = trailFrom
        self.trailTo = trailTo
    }

    /// Where Murzik sits before any choreography has run.
    static let home = IslandScene()

    var compactSide: CompactSide { position < 0.5 ? .leading : .trailing }

    /// Position inside his compact region, 0…1 from that region's left edge to its right edge.
    var compactLocalPosition: Double {
        let p = min(1, max(0, position))
        return compactSide == .leading ? p * 2 : (p - 0.5) * 2
    }

    var isWalking: Bool { pose == .walk || pose == .stretch }

    /// The same place, sitting in his mood pose.
    func resting() -> IslandScene {
        var s = self
        s.pose = .rest
        s.frame = 0
        s.effect = .none
        s.step &+= 1
        return s
    }

    /// The paw-print trail range, if it is valid.
    var trailRange: ClosedRange<Date>? {
        guard let trailFrom, let trailTo, trailFrom < trailTo else { return nil }
        return trailFrom...trailTo
    }

    /// The pre-rendered pose to show.
    func sprite(for mood: MurzikMood) -> MurzikSprite {
        switch pose {
        case .rest: return MurzikSprite.forMood(mood)
        case .walk: return MurzikSprite.walkCycle[((frame % 8) + 8) % 8]
        case .hop: return .excited
        case .eat: return .sitSide
        case .stretch: return .stretch
        }
    }
}

/// One content update of a choreography: send `scene` at `at` seconds after the sequence starts.
struct IslandBeat: Equatable, Sendable {
    var at: TimeInterval
    var scene: IslandScene
}

/// Pure choreography: turns "walk across", "go to the Pet button", … into a short list of beats.
/// iOS animates each content update for at most 2 s, so beats are spaced a little longer than
/// `animationDuration`, and every sequence ends with Murzik resting.
enum IslandChoreography {
    /// SwiftUI animation between two beats (iOS caps Live Activity animations at 2 s).
    static let animationDuration: TimeInterval = 1.5
    /// A calm walking step.
    static let stepInterval: TimeInterval = 1.7
    static let stepLength = 0.17
    /// A quicker trot toward a button that was just tapped.
    static let trotInterval: TimeInterval = 1.6
    static let trotLength = 0.3
    /// Where he likes to sit on each side.
    static let leftSpot = 0.16
    static let rightSpot = 0.84
    /// Next to the bowl (Feed) and the cushion (Pet).
    static let feedSpot = 0.1
    static let petSpot = 0.9
    /// Upper bound for one sequence (keeps the update rate reasonable).
    static let maxBeats = 10

    /// Walk frames alternate between two contrasting poses so each step reads as a step.
    static func walkFrame(forStep index: Int) -> Int { index % 2 == 0 ? 5 : 1 }

    /// Steps from `start` to `target`. The first beat is sent at `startAt`.
    static func walk(
        from start: IslandScene,
        to target: Double,
        stepLength: Double,
        interval: TimeInterval,
        startAt: TimeInterval
    ) -> (beats: [IslandBeat], end: IslandScene, endAt: TimeInterval) {
        let target = min(1, max(0, target))
        let distance = target - start.position
        var scene = start
        guard abs(distance) > 0.01 else { return ([], scene, startAt) }
        let steps = max(1, Int((abs(distance) / stepLength).rounded(.up)))
        var beats: [IslandBeat] = []
        var t = startAt
        scene.facingLeft = distance < 0
        for i in 1...steps {
            scene.position = start.position + distance * Double(i) / Double(steps)
            scene.pose = .walk
            scene.frame = walkFrame(forStep: i)
            scene.effect = .none
            scene.step &+= 1
            beats.append(IslandBeat(at: t, scene: scene))
            t += interval
        }
        return (beats, scene, t)
    }

    /// Played when the app goes to the background: Murzik stretches, walks across the island to the
    /// other side (through the camera area in the compact island) and sits down.
    /// - Parameter restNotBefore: an active reaction's remaining time; he sits down only after it.
    static func crossing(from start: IslandScene, restNotBefore: TimeInterval = 0) -> [IslandBeat] {
        let target = start.position < 0.5 ? rightSpot : leftSpot
        var scene = start
        scene.pose = .stretch
        scene.frame = 0
        scene.effect = .none
        scene.facingLeft = target < start.position
        scene.step &+= 1
        var beats = [IslandBeat(at: 0.3, scene: scene)]
        let walk = walk(from: scene, to: target, stepLength: stepLength, interval: stepInterval, startAt: 0.3 + stepInterval)
        beats += walk.beats
        beats.append(IslandBeat(at: max(walk.endAt, restNotBefore), scene: walk.end.resting()))
        return beats
    }

    /// Played after Pet/Feed (or any reaction): he trots to the button that was tapped, reacts
    /// (hop with hearts / eating), and sits down once the reaction is over.
    /// - Parameters:
    ///   - action: the island button that was tapped, or nil for a reaction triggered elsewhere.
    ///   - reactionMood: the active reaction mood, if any.
    ///   - isSleeping: a sleeping cat does not walk; he just purrs in place.
    ///   - restNotBefore: remaining time of the reaction.
    static func reaction(
        to action: PetAction?,
        reactionMood: MurzikMood?,
        isSleeping: Bool,
        from start: IslandScene,
        restNotBefore: TimeInterval
    ) -> [IslandBeat] {
        var scene = start
        if isSleeping {
            scene.pose = .rest
            scene.effect = .hearts
            scene.step &+= 1
            return [
                IslandBeat(at: 0.2, scene: scene),
                IslandBeat(at: max(0.2 + stepInterval, restNotBefore), scene: scene.resting()),
            ]
        }

        var beats: [IslandBeat] = []
        var t: TimeInterval = 0.2
        let target: Double?
        switch action {
        case .feed?: target = feedSpot
        case .pet?: target = petSpot
        default: target = nil
        }
        if let target {
            let walk = walk(from: scene, to: target, stepLength: trotLength, interval: trotInterval, startAt: t)
            beats += walk.beats
            scene = walk.end
            t = walk.endAt
        }

        let joy: IslandScene.Effect = reactionMood == .excited ? .sparkles : .hearts
        if action == .feed {
            // Eat from the bowl (on the left), then a happy hop.
            scene.pose = .eat
            scene.facingLeft = true
            scene.effect = .food
            scene.step &+= 1
            beats.append(IslandBeat(at: t, scene: scene))
            t += stepInterval
            scene.pose = .hop
            scene.facingLeft = false
            scene.effect = joy
            scene.step &+= 1
            beats.append(IslandBeat(at: t, scene: scene))
            t += stepInterval
        } else {
            scene.pose = .hop
            scene.effect = joy
            scene.step &+= 1
            beats.append(IslandBeat(at: t, scene: scene))
            t += stepInterval
            // Sit and enjoy it a moment longer.
            scene.pose = .rest
            scene.step &+= 1
            beats.append(IslandBeat(at: t, scene: scene))
            t += stepInterval
        }
        beats.append(IslandBeat(at: max(t, restNotBefore), scene: scene.resting()))
        return beats
    }
}
