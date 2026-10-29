import Foundation

/// Part of the day, used for the room lighting and Murzik's daily rhythm.
enum DayPhase: String, Codable, CaseIterable, Hashable, Sendable {
    case morning   // 05:00–10:59
    case day       // 11:00–16:59
    case evening   // 17:00–20:59
    case night     // 21:00–04:59
}

/// A welcome shown when she opens the app.
enum Greeting: Equatable, Hashable, Sendable {
    /// The very first time they meet.
    case firstMeeting
    /// A new day has started (first visit of the day, in the morning).
    case goodMorning
    /// She has been away for a while.
    case missedYou(hours: Int)
    /// She came back late at night.
    case lateNight
}

/// Little things Murzik brings her.
enum Gift: String, Codable, CaseIterable, Hashable, Sendable {
    case flower
    case leaf
    case feather
    case star
    case heart
    case yarn

    var symbolName: String {
        switch self {
        case .flower: return "camera.macro"
        case .leaf: return "leaf.fill"
        case .feather: return "wind"
        case .star: return "star.fill"
        case .heart: return "heart.fill"
        case .yarn: return "circle.hexagongrid.fill"
        }
    }
}

/// A spontaneous cute moment.
enum Surprise: Equatable, Hashable, Sendable {
    /// He brings her a gift.
    case gift(Gift)
    /// A sweet message; index into `Strings.surpriseMessages` (wraps around).
    case message(Int)
}

/// One entry in Murzik's mood diary.
struct MoodSample: Codable, Equatable, Hashable, Sendable {
    var mood: MurzikMood
    var date: Date
}

/// The relationship between her and Murzik: visits, love streak, gifts and mood diary.
/// Persisted separately from `PetState` (key `PetStorage.bondKey`), so the original state JSON is untouched.
/// Decoding tolerates missing keys, so new fields can be added later without losing data.
struct BondState: Codable, Equatable, Sendable {
    /// When she last had the app open (updated when it goes to the background, too).
    var lastVisit: Date?
    /// When she last showed him love (pet, feed, play, purr).
    var lastLoveDate: Date?
    /// Consecutive days with at least one act of love, ending at `lastLoveDate`'s day.
    var streakDays: Int
    /// Acts of love on `lastLoveDate`'s day.
    var loveOnLastDay: Int
    /// Acts of love, ever.
    var totalLove: Int
    /// Gifts he has brought her.
    var giftsReceived: Int
    /// When the last surprise happened.
    var lastSurprise: Date?
    /// Total time spent purring together, in seconds.
    var purrSeconds: Double
    /// Mood diary, oldest first, capped at `PersonalityEngine.moodHistoryLimit`.
    var moodHistory: [MoodSample]

    init(
        lastVisit: Date? = nil,
        lastLoveDate: Date? = nil,
        streakDays: Int = 0,
        loveOnLastDay: Int = 0,
        totalLove: Int = 0,
        giftsReceived: Int = 0,
        lastSurprise: Date? = nil,
        purrSeconds: Double = 0,
        moodHistory: [MoodSample] = []
    ) {
        self.lastVisit = lastVisit
        self.lastLoveDate = lastLoveDate
        self.streakDays = streakDays
        self.loveOnLastDay = loveOnLastDay
        self.totalLove = totalLove
        self.giftsReceived = giftsReceived
        self.lastSurprise = lastSurprise
        self.purrSeconds = purrSeconds
        self.moodHistory = moodHistory
    }

    private enum CodingKeys: String, CodingKey {
        case lastVisit, lastLoveDate, streakDays, loveOnLastDay, totalLove
        case giftsReceived, lastSurprise, purrSeconds, moodHistory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastVisit = try c.decodeIfPresent(Date.self, forKey: .lastVisit)
        lastLoveDate = try c.decodeIfPresent(Date.self, forKey: .lastLoveDate)
        streakDays = try c.decodeIfPresent(Int.self, forKey: .streakDays) ?? 0
        loveOnLastDay = try c.decodeIfPresent(Int.self, forKey: .loveOnLastDay) ?? 0
        totalLove = try c.decodeIfPresent(Int.self, forKey: .totalLove) ?? 0
        giftsReceived = try c.decodeIfPresent(Int.self, forKey: .giftsReceived) ?? 0
        lastSurprise = try c.decodeIfPresent(Date.self, forKey: .lastSurprise)
        purrSeconds = try c.decodeIfPresent(Double.self, forKey: .purrSeconds) ?? 0
        moodHistory = (try? c.decodeIfPresent([MoodSample].self, forKey: .moodHistory)) ?? []
    }
}
