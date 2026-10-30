import ActivityKit
import Foundation

/// Live Activity definition shared by the app and the widget extension.
struct MurzikAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var mood: MurzikMood
        var fullness: Double
        var energy: Double
        var happiness: Double
        var isSleeping: Bool
        /// When Murzik becomes hungry. Drives a live countdown and the activity's stale date,
        /// so the island changes to "hungry" on time without any update from the app.
        var hungryAt: Date
        /// When a sleeping Murzik wakes up on his own (nil when awake).
        var wakesAt: Date?
        /// Where Murzik is on the island stage and what he is doing (walk choreography).
        /// Optional so content from older builds still decodes.
        var stage: IslandScene? = nil
    }

    var name: String
}

extension MurzikAttributes.ContentState {
    /// Builds the content from an already-advanced state.
    init(state: PetState, now: Date) {
        self.init(
            mood: PersonalityEngine.mood(for: state, at: now),
            fullness: state.fullness,
            energy: state.energy,
            happiness: state.happiness,
            isSleeping: state.isSleeping,
            hungryAt: PersonalityEngine.hungryDate(for: state),
            wakesAt: PersonalityEngine.wakeDate(for: state)
        )
    }

    /// The scene to draw (his home spot when no choreography has run yet).
    var scene: IslandScene { stage ?? .home }

    /// The mood to draw. Once the content is stale (past `hungryAt`) Murzik is hungry,
    /// unless he is asleep.
    func displayMood(isStale: Bool) -> MurzikMood {
        if isStale && !sleepsThroughHunger { return .hungry }
        return mood
    }

    /// True when he is asleep and will still be asleep when hunger arrives.
    var sleepsThroughHunger: Bool {
        guard isSleeping else { return false }
        guard let wakesAt else { return true }
        return wakesAt > hungryAt
    }

    /// Whether the hunger countdown should be shown.
    func showsHungerCountdown(isStale: Bool, now: Date = .now) -> Bool {
        !isStale && fullness >= PersonalityEngine.hungryThreshold && hungryAt > now
    }
}
