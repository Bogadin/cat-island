import Foundation

/// Murzik's persisted needs. All values are in 0...1.
struct PetState: Codable, Equatable, Sendable {
    struct Reaction: Codable, Equatable, Sendable {
        var mood: MurzikMood
        var date: Date
    }

    var fullness: Double
    var energy: Double
    var happiness: Double
    var isSleeping: Bool
    var lastUpdated: Date
    var lastReaction: Reaction?

    init(
        fullness: Double = 0.8,
        energy: Double = 0.9,
        happiness: Double = 0.8,
        isSleeping: Bool = false,
        lastUpdated: Date = .now,
        lastReaction: Reaction? = nil
    ) {
        self.fullness = fullness
        self.energy = energy
        self.happiness = happiness
        self.isSleeping = isSleeping
        self.lastUpdated = lastUpdated
        self.lastReaction = lastReaction
    }
}

/// Pure, deterministic rules for how Murzik's needs change over time and in response to actions.
/// Every function takes `now` explicitly so the engine is fully testable.
enum PersonalityEngine {
    static let hungryThreshold = 0.25
    static let sleepyThreshold = 0.25
    static let happyThreshold = 0.75
    static let boredThreshold = 0.35
    /// How long a reaction (e.g. "loving" after a pet) overrides the base mood.
    static let reactionDuration: TimeInterval = 6

    struct Rates: Equatable {
        var fullness: Double
        var energy: Double
        var happiness: Double
    }

    /// Change per hour.
    static func rates(sleeping: Bool) -> Rates {
        sleeping
            ? Rates(fullness: -0.04, energy: 0.20, happiness: -0.01)
            : Rates(fullness: -0.08, energy: -0.05, happiness: -0.04)
    }

    // MARK: Time

    /// Applies the passage of time. Murzik wakes up on his own once fully rested.
    static func advance(_ state: PetState, to now: Date) -> PetState {
        var s = state
        let elapsed = now.timeIntervalSince(state.lastUpdated)
        guard elapsed > 0 else {
            // Clock moved backwards (manual time change): just re-anchor.
            s.lastUpdated = now
            return s
        }
        var hours = elapsed / 3600

        if s.isSleeping {
            let sleepRates = rates(sleeping: true)
            let hoursToFull = max(0, (1 - s.energy) / sleepRates.energy)
            if hours >= hoursToFull {
                apply(sleepRates, hours: hoursToFull, to: &s)
                s.energy = 1
                s.isSleeping = false
                hours -= hoursToFull
            } else {
                apply(sleepRates, hours: hours, to: &s)
                hours = 0
            }
        }
        if hours > 0 {
            apply(rates(sleeping: false), hours: hours, to: &s)
        }
        s.lastUpdated = now
        return s
    }

    private static func apply(_ r: Rates, hours: Double, to s: inout PetState) {
        s.fullness = clamp(s.fullness + r.fullness * hours)
        s.energy = clamp(s.energy + r.energy * hours)
        s.happiness = clamp(s.happiness + r.happiness * hours)
    }

    // MARK: Actions

    static func apply(_ action: PetAction, to state: PetState, at now: Date) -> PetState {
        var s = advance(state, to: now)
        var reaction: MurzikMood?

        switch action {
        case .pet:
            if s.isSleeping {
                // A sleeping cat just purrs a little and keeps sleeping.
                s.happiness += 0.05
            } else {
                s.happiness += 0.15
                reaction = s.happiness >= 0.95 ? .excited : .loving
            }
        case .feed:
            let wasHungry = s.fullness < hungryThreshold
            if s.isSleeping {
                s.isSleeping = false
            }
            s.fullness += 0.35
            s.happiness += 0.05
            reaction = wasHungry ? .excited : .happy
        case .play:
            if s.isSleeping {
                s.isSleeping = false
                reaction = .surprised
            } else if s.energy < 0.15 {
                s.happiness += 0.02
                reaction = .sleepy
            } else {
                s.happiness += 0.2
                s.energy -= 0.1
                s.fullness -= 0.05
                reaction = .playful
            }
        case .sleep:
            s.isSleeping = true
        case .wake:
            if s.isSleeping {
                s.isSleeping = false
                reaction = .surprised
            }
        }

        s.fullness = clamp(s.fullness)
        s.energy = clamp(s.energy)
        s.happiness = clamp(s.happiness)
        s.lastUpdated = now
        s.lastReaction = reaction.map { PetState.Reaction(mood: $0, date: now) }
        return s
    }

    // MARK: Mood

    /// The mood to display. Call with an already-advanced state.
    static func mood(for state: PetState, at now: Date) -> MurzikMood {
        if let reaction = state.lastReaction, isReactionActive(reaction, at: now) {
            return reaction.mood
        }
        return baseMood(for: state)
    }

    static func isReactionActive(_ reaction: PetState.Reaction, at now: Date) -> Bool {
        let age = now.timeIntervalSince(reaction.date)
        return age >= 0 && age < reactionDuration
    }

    static func baseMood(for state: PetState) -> MurzikMood {
        if state.isSleeping { return .sleeping }
        if state.fullness < hungryThreshold { return .hungry }
        if state.energy < sleepyThreshold { return .sleepy }
        if state.happiness >= happyThreshold { return .happy }
        if state.happiness < boredThreshold { return .playful }
        return .idle
    }

    /// When Murzik will become hungry if nothing else happens (accounts for waking up mid-way).
    static func hungryDate(for state: PetState) -> Date {
        let excess = state.fullness - hungryThreshold
        guard excess > 0 else { return state.lastUpdated }

        var hours = 0.0
        var fullness = state.fullness
        if state.isSleeping {
            let sleepRates = rates(sleeping: true)
            let hoursToWake = max(0, (1 - state.energy) / sleepRates.energy)
            let fullnessAtWake = fullness + sleepRates.fullness * hoursToWake
            if fullnessAtWake <= hungryThreshold {
                return state.lastUpdated.addingTimeInterval(excess / -sleepRates.fullness * 3600)
            }
            hours = hoursToWake
            fullness = fullnessAtWake
        }
        hours += (fullness - hungryThreshold) / -rates(sleeping: false).fullness
        return state.lastUpdated.addingTimeInterval(hours * 3600)
    }

    /// When a sleeping Murzik will wake up on his own (nil if awake).
    static func wakeDate(for state: PetState) -> Date? {
        guard state.isSleeping else { return nil }
        let hours = max(0, (1 - state.energy) / rates(sleeping: true).energy)
        return state.lastUpdated.addingTimeInterval(hours * 3600)
    }

    static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
}
