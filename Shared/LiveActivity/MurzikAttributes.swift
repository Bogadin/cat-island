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
            hungryAt: PersonalityEngine.hungryDate(for: state)
        )
    }

    /// The mood to draw. Once the content is stale (past `hungryAt`) Murzik is hungry,
    /// unless he is asleep.
    func displayMood(isStale: Bool) -> MurzikMood {
        if isStale && !isSleeping { return .hungry }
        return mood
    }

    /// Whether the hunger countdown should be shown.
    func showsHungerCountdown(isStale: Bool, now: Date = .now) -> Bool {
        !isStale && fullness >= PersonalityEngine.hungryThreshold && hungryAt > now
    }
}
