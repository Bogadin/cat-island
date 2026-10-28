import Foundation

/// Every expression Murzik can show. The raw value is persisted and sent
/// inside the Live Activity content state, so never rename existing cases.
enum MurzikMood: String, Codable, CaseIterable, Hashable, Sendable {
    case idle
    case happy
    case sleepy
    case sleeping
    case playful
    case hungry
    case loving
    case surprised
    case blinking
    case excited

    /// Moods that show open eyes and can therefore blink in the app.
    var canBlink: Bool {
        switch self {
        case .idle, .playful, .hungry, .excited, .sleepy: return true
        default: return false
        }
    }

    /// SF Symbol used as the small mood indicator (Dynamic Island trailing, chips).
    var symbolName: String {
        switch self {
        case .idle: return "pawprint.fill"
        case .happy: return "sun.max.fill"
        case .sleepy: return "moon.fill"
        case .sleeping: return "moon.zzz.fill"
        case .playful: return "sparkles"
        case .hungry: return "fish.fill"
        case .loving: return "heart.fill"
        case .surprised: return "exclamationmark"
        case .blinking: return "eye.fill"
        case .excited: return "star.fill"
        }
    }
}

/// Things the user can do to Murzik.
enum PetAction: String, Codable, CaseIterable, Hashable, Sendable {
    case pet
    case feed
    case play
    case sleep
    case wake

    var symbolName: String {
        switch self {
        case .pet: return "hand.raised.fill"
        case .feed: return "fish.fill"
        case .play: return "sparkles"
        case .sleep: return "moon.zzz.fill"
        case .wake: return "sun.max.fill"
        }
    }
}
