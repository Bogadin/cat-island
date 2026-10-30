import Foundation

/// Daily rhythm, greetings, love streaks, surprises and the mood diary.
/// Pure and deterministic like the rest of the engine: time, calendar and randomness are parameters.
extension PersonalityEngine {
    /// Away this long → "I missed you".
    static let greetingAbsence: TimeInterval = 3 * 3600
    /// Minimum time between two surprises.
    static let surpriseCooldown: TimeInterval = 20 * 60
    /// A repeated mood is written to the diary at most this often.
    static let moodSampleInterval: TimeInterval = 20 * 60
    static let moodHistoryLimit = 96

    // MARK: Day rhythm

    static func dayPhase(at now: Date, calendar: Calendar = .current) -> DayPhase {
        switch calendar.component(.hour, from: now) {
        case 5..<11: return .morning
        case 11..<17: return .day
        case 17..<21: return .evening
        default: return .night
        }
    }

    /// The mood the app shows: like `mood(for:at:)`, but Murzik gets sleepy in the evening and at night.
    /// (The Live Activity keeps using `mood(for:at:)`.)
    static func displayMood(for state: PetState, at now: Date, calendar: Calendar = .current) -> MurzikMood {
        displayMood(for: state, at: now, phase: dayPhase(at: now, calendar: calendar))
    }

    /// Same as `displayMood(for:at:calendar:)` with an explicit part of the day.
    static func displayMood(for state: PetState, at now: Date, phase: DayPhase) -> MurzikMood {
        if let reaction = state.lastReaction, isReactionActive(reaction, at: now) {
            return reaction.mood
        }
        let base = baseMood(for: state)
        guard base == .idle || base == .happy else { return base }
        switch phase {
        case .night where state.energy < 0.75: return .sleepy
        case .evening where state.energy < 0.4: return .sleepy
        default: return base
        }
    }

    /// Late and he is still awake: suggest bedtime.
    static func isBedtime(for state: PetState, at now: Date, calendar: Calendar = .current) -> Bool {
        !state.isSleeping && dayPhase(at: now, calendar: calendar) == .night
    }

    // MARK: Greeting

    /// The welcome to show when she opens the app, or nil if she was here recently.
    /// Call before `recordVisit`.
    static func greeting(bond: BondState, at now: Date, calendar: Calendar = .current) -> Greeting? {
        guard let last = bond.lastVisit else { return .firstMeeting }
        let away = now.timeIntervalSince(last)
        guard away >= 0 else { return nil }
        let phase = dayPhase(at: now, calendar: calendar)
        if phase == .morning, away >= 2 * 3600, !calendar.isDate(last, inSameDayAs: now) {
            return .goodMorning
        }
        guard away >= greetingAbsence else { return nil }
        if phase == .night { return .lateNight }
        return .missedYou(hours: Int(away / 3600))
    }

    static func recordVisit(_ bond: BondState, at now: Date) -> BondState {
        var b = bond
        b.lastVisit = now
        return b
    }

    // MARK: Love & streak

    /// Whole calendar days from `a` to `b` (0 = same day, 1 = yesterday → today).
    static func dayGap(from a: Date, to b: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
    }

    /// Counts an act of love (pet, feed, play, purr) and keeps the daily streak.
    static func recordLove(_ bond: BondState, at now: Date, calendar: Calendar = .current) -> BondState {
        var b = bond
        if let last = b.lastLoveDate {
            let gap = dayGap(from: last, to: now, calendar: calendar)
            if gap == 0 {
                b.loveOnLastDay += 1
                b.streakDays = max(1, b.streakDays)
            } else if gap == 1 {
                b.streakDays += 1
                b.loveOnLastDay = 1
            } else {
                // Missed a day, or the clock went backwards: start over.
                b.streakDays = 1
                b.loveOnLastDay = 1
            }
        } else {
            b.streakDays = 1
            b.loveOnLastDay = 1
        }
        b.totalLove += 1
        b.lastLoveDate = now
        return b
    }

    /// The streak as of `now` (0 once a whole day has passed without love).
    static func currentStreak(_ bond: BondState, at now: Date, calendar: Calendar = .current) -> Int {
        guard let last = bond.lastLoveDate else { return 0 }
        let gap = dayGap(from: last, to: now, calendar: calendar)
        return (gap == 0 || gap == 1) ? bond.streakDays : 0
    }

    /// Acts of love today.
    static func loveToday(_ bond: BondState, at now: Date, calendar: Calendar = .current) -> Int {
        guard let last = bond.lastLoveDate, dayGap(from: last, to: now, calendar: calendar) == 0 else { return 0 }
        return bond.loveOnLastDay
    }

    static func recordPurr(_ bond: BondState, seconds: TimeInterval) -> BondState {
        var b = bond
        b.purrSeconds += max(0, seconds)
        return b
    }

    // MARK: Surprises

    /// Chance (per check) that something cute happens. Happier cat → more surprises.
    static func surpriseChance(for state: PetState) -> Double {
        0.05 + 0.15 * clamp(state.happiness)
    }

    /// Decides whether a surprise happens now.
    /// - Parameters:
    ///   - roll: a random number in 0..<1.
    ///   - pick: any random integer, used to choose which gift or message.
    static func surprise(for state: PetState, bond: BondState, at now: Date, roll: Double, pick: Int) -> Surprise? {
        guard !state.isSleeping, state.fullness >= hungryThreshold else { return nil }
        if let last = bond.lastSurprise, now >= last, now.timeIntervalSince(last) < surpriseCooldown {
            return nil
        }
        let chance = surpriseChance(for: state)
        guard roll < chance else { return nil }
        let index = Int(pick.magnitude % 10_000)
        if state.happiness >= 0.6, roll < chance * 0.5 {
            return .gift(Gift.allCases[index % Gift.allCases.count])
        }
        return .message(index)
    }

    static func applySurprise(_ surprise: Surprise, to bond: BondState, at now: Date) -> BondState {
        var b = bond
        b.lastSurprise = now
        if case .gift = surprise { b.giftsReceived += 1 }
        return b
    }

    // MARK: Mood diary

    static func recordMood(_ mood: MurzikMood, in bond: BondState, at now: Date) -> BondState {
        guard mood != .blinking else { return bond }
        if let last = bond.moodHistory.last {
            if now < last.date { return bond }
            if last.mood == mood, now.timeIntervalSince(last.date) < moodSampleInterval { return bond }
        }
        var b = bond
        b.moodHistory.append(MoodSample(mood: mood, date: now))
        if b.moodHistory.count > moodHistoryLimit {
            b.moodHistory.removeFirst(b.moodHistory.count - moodHistoryLimit)
        }
        return b
    }

    static func moodsToday(_ bond: BondState, at now: Date, calendar: Calendar = .current) -> [MoodSample] {
        bond.moodHistory.filter { calendar.isDate($0.date, inSameDayAs: now) }
    }

    /// The mood he showed most often today (nil if the diary is empty today).
    static func dominantMoodToday(_ bond: BondState, at now: Date, calendar: Calendar = .current) -> MurzikMood? {
        let today = moodsToday(bond, at: now, calendar: calendar)
        guard !today.isEmpty else { return nil }
        var counts: [MurzikMood: Int] = [:]
        for sample in today { counts[sample.mood, default: 0] += 1 }
        // Ties: the most recent wins.
        return today.reversed().max { (counts[$0.mood] ?? 0) < (counts[$1.mood] ?? 0) }?.mood
    }
}
