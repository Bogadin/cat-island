import XCTest
@testable import Murzik

/// Day rhythm, greetings, love streak, surprises, mood diary and their persistence.
final class ExperienceEngineTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 2027-01-(15 + dayOffset) at hour:minute UTC.
    private func at(day dayOffset: Int = 0, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2027, month: 1, day: 15 + dayOffset, hour: hour, minute: minute))!
    }

    // MARK: Day phase & rhythm

    func testDayPhases() {
        XCTAssertEqual(PersonalityEngine.dayPhase(at: at(4, 59), calendar: calendar), .night)
        XCTAssertEqual(PersonalityEngine.dayPhase(at: at(5), calendar: calendar), .morning)
        XCTAssertEqual(PersonalityEngine.dayPhase(at: at(10, 59), calendar: calendar), .morning)
        XCTAssertEqual(PersonalityEngine.dayPhase(at: at(11), calendar: calendar), .day)
        XCTAssertEqual(PersonalityEngine.dayPhase(at: at(17), calendar: calendar), .evening)
        XCTAssertEqual(PersonalityEngine.dayPhase(at: at(21), calendar: calendar), .night)
        XCTAssertEqual(PersonalityEngine.dayPhase(at: at(0, 30), calendar: calendar), .night)
    }

    func testSleepierAtNight() {
        let s = PetState(fullness: 0.8, energy: 0.6, happiness: 0.5, lastUpdated: at(23))
        XCTAssertEqual(PersonalityEngine.baseMood(for: s), .idle)
        XCTAssertEqual(PersonalityEngine.displayMood(for: s, at: at(23), calendar: calendar), .sleepy)
        XCTAssertEqual(PersonalityEngine.displayMood(for: s, at: at(13), calendar: calendar), .idle)
        // Evening: only when tired.
        XCTAssertEqual(PersonalityEngine.displayMood(for: s, at: at(18), calendar: calendar), .idle)
        var tired = s
        tired.energy = 0.3
        XCTAssertEqual(PersonalityEngine.displayMood(for: tired, at: at(18), calendar: calendar), .sleepy)
    }

    func testRhythmNeverOverridesNeedsOrReactions() {
        let hungry = PetState(fullness: 0.1, energy: 0.5, lastUpdated: at(23))
        XCTAssertEqual(PersonalityEngine.displayMood(for: hungry, at: at(23), calendar: calendar), .hungry)
        let rested = PetState(fullness: 0.8, energy: 0.9, happiness: 0.9, lastUpdated: at(23))
        XCTAssertEqual(PersonalityEngine.displayMood(for: rested, at: at(23), calendar: calendar), .happy)
        let petted = PersonalityEngine.apply(.pet, to: PetState(energy: 0.5, happiness: 0.5, lastUpdated: at(23)), at: at(23))
        XCTAssertEqual(PersonalityEngine.displayMood(for: petted, at: at(23), calendar: calendar), .loving)
    }

    func testBedtime() {
        XCTAssertTrue(PersonalityEngine.isBedtime(for: PetState(), at: at(22), calendar: calendar))
        XCTAssertFalse(PersonalityEngine.isBedtime(for: PetState(isSleeping: true), at: at(22), calendar: calendar))
        XCTAssertFalse(PersonalityEngine.isBedtime(for: PetState(), at: at(14), calendar: calendar))
    }

    // MARK: Greeting

    func testFirstMeeting() {
        XCTAssertEqual(PersonalityEngine.greeting(bond: BondState(), at: at(12), calendar: calendar), .firstMeeting)
    }

    func testNoGreetingAfterShortAbsence() {
        let bond = BondState(lastVisit: at(12))
        XCTAssertNil(PersonalityEngine.greeting(bond: bond, at: at(14, 30), calendar: calendar))
    }

    func testMissedYouAfterAWhile() {
        let bond = BondState(lastVisit: at(12))
        XCTAssertEqual(PersonalityEngine.greeting(bond: bond, at: at(16), calendar: calendar), .missedYou(hours: 4))
        XCTAssertEqual(Strings.greetingTitle(.missedYou(hours: 4)), "התגעגעתי אלייך!")
    }

    func testGoodMorningOnANewDay() {
        let bond = BondState(lastVisit: at(23))
        XCTAssertEqual(PersonalityEngine.greeting(bond: bond, at: at(day: 1, 7, 30), calendar: calendar), .goodMorning)
    }

    func testLateNightGreeting() {
        let bond = BondState(lastVisit: at(15))
        XCTAssertEqual(PersonalityEngine.greeting(bond: bond, at: at(23), calendar: calendar), .lateNight)
    }

    func testGreetingIgnoresClockGoingBackwards() {
        let bond = BondState(lastVisit: at(18))
        XCTAssertNil(PersonalityEngine.greeting(bond: bond, at: at(9), calendar: calendar))
    }

    func testRecordVisitSuppressesNextGreeting() {
        let bond = PersonalityEngine.recordVisit(BondState(), at: at(12))
        XCTAssertEqual(bond.lastVisit, at(12))
        XCTAssertNil(PersonalityEngine.greeting(bond: bond, at: at(12, 5), calendar: calendar))
    }

    // MARK: Love & streak

    func testLoveCountsTodayAndStartsStreak() {
        var bond = BondState()
        for minute in 0..<3 {
            bond = PersonalityEngine.recordLove(bond, at: at(10, minute), calendar: calendar)
        }
        XCTAssertEqual(PersonalityEngine.loveToday(bond, at: at(20), calendar: calendar), 3)
        XCTAssertEqual(PersonalityEngine.currentStreak(bond, at: at(20), calendar: calendar), 1)
        XCTAssertEqual(bond.totalLove, 3)
    }

    func testStreakGrowsOnConsecutiveDays() {
        var bond = BondState()
        bond = PersonalityEngine.recordLove(bond, at: at(day: 0, 23, 50), calendar: calendar)
        bond = PersonalityEngine.recordLove(bond, at: at(day: 1, 0, 10), calendar: calendar)
        bond = PersonalityEngine.recordLove(bond, at: at(day: 2, 12), calendar: calendar)
        XCTAssertEqual(bond.streakDays, 3)
        XCTAssertEqual(PersonalityEngine.loveToday(bond, at: at(day: 2, 13), calendar: calendar), 1)
        // Still counts the next day (she has until midnight to keep it)…
        XCTAssertEqual(PersonalityEngine.currentStreak(bond, at: at(day: 3, 22), calendar: calendar), 3)
        XCTAssertEqual(PersonalityEngine.loveToday(bond, at: at(day: 3, 22), calendar: calendar), 0)
        // …but is gone after a whole missed day.
        XCTAssertEqual(PersonalityEngine.currentStreak(bond, at: at(day: 4, 1), calendar: calendar), 0)
    }

    func testStreakRestartsAfterAGap() {
        var bond = BondState()
        bond = PersonalityEngine.recordLove(bond, at: at(day: 0, 12), calendar: calendar)
        bond = PersonalityEngine.recordLove(bond, at: at(day: 1, 12), calendar: calendar)
        bond = PersonalityEngine.recordLove(bond, at: at(day: 4, 12), calendar: calendar)
        XCTAssertEqual(bond.streakDays, 1)
        XCTAssertEqual(bond.loveOnLastDay, 1)
        XCTAssertEqual(bond.totalLove, 3)
    }

    func testPurrTimeAccumulates() {
        var bond = PersonalityEngine.recordPurr(BondState(), seconds: 12)
        bond = PersonalityEngine.recordPurr(bond, seconds: -5)
        bond = PersonalityEngine.recordPurr(bond, seconds: 3)
        XCTAssertEqual(bond.purrSeconds, 15, accuracy: 1e-9)
    }

    // MARK: Surprises

    func testNoSurpriseWhenSleepingOrHungry() {
        let bond = BondState()
        XCTAssertNil(PersonalityEngine.surprise(for: PetState(isSleeping: true), bond: bond, at: at(12), roll: 0, pick: 0))
        XCTAssertNil(PersonalityEngine.surprise(for: PetState(fullness: 0.1), bond: bond, at: at(12), roll: 0, pick: 0))
    }

    func testHappyCatBringsGifts() {
        let state = PetState(fullness: 0.8, energy: 0.8, happiness: 0.9)
        let surprise = PersonalityEngine.surprise(for: state, bond: BondState(), at: at(12), roll: 0.01, pick: 2)
        XCTAssertEqual(surprise, .gift(Gift.allCases[2]))
    }

    func testMessageWhenRollIsHigherOrLessHappy() {
        let happy = PetState(fullness: 0.8, energy: 0.8, happiness: 0.9)
        let chance = PersonalityEngine.surpriseChance(for: happy)
        XCTAssertEqual(PersonalityEngine.surprise(for: happy, bond: BondState(), at: at(12), roll: chance * 0.75, pick: 7), .message(7))
        let calm = PetState(fullness: 0.8, energy: 0.8, happiness: 0.4)
        XCTAssertEqual(PersonalityEngine.surprise(for: calm, bond: BondState(), at: at(12), roll: 0.0, pick: 3), .message(3))
        XCTAssertNil(PersonalityEngine.surprise(for: happy, bond: BondState(), at: at(12), roll: chance + 0.01, pick: 3))
    }

    func testSurpriseCooldown() {
        let state = PetState(fullness: 0.8, energy: 0.8, happiness: 0.9)
        var bond = PersonalityEngine.applySurprise(.gift(.flower), to: BondState(), at: at(12))
        XCTAssertEqual(bond.giftsReceived, 1)
        XCTAssertNil(PersonalityEngine.surprise(for: state, bond: bond, at: at(12, 10), roll: 0, pick: 0))
        XCTAssertNotNil(PersonalityEngine.surprise(for: state, bond: bond, at: at(12, 25), roll: 0, pick: 0))
        bond = PersonalityEngine.applySurprise(.message(1), to: bond, at: at(13))
        XCTAssertEqual(bond.giftsReceived, 1)
        XCTAssertEqual(bond.lastSurprise, at(13))
    }

    func testNegativePickIsSafe() {
        let state = PetState(fullness: 0.8, energy: 0.8, happiness: 0.9)
        let surprise = PersonalityEngine.surprise(for: state, bond: BondState(), at: at(12), roll: 0, pick: Int.min)
        XCTAssertNotNil(surprise)
        XCTAssertFalse(Strings.surpriseMessage(Int.min).isEmpty)
        XCTAssertFalse(Strings.surpriseMessage(12345).isEmpty)
    }

    // MARK: Mood diary

    func testMoodDiaryDeduplicatesAndCaps() {
        var bond = BondState()
        bond = PersonalityEngine.recordMood(.happy, in: bond, at: at(10))
        bond = PersonalityEngine.recordMood(.happy, in: bond, at: at(10, 5))      // same mood, too soon
        bond = PersonalityEngine.recordMood(.blinking, in: bond, at: at(10, 6))   // never recorded
        bond = PersonalityEngine.recordMood(.hungry, in: bond, at: at(10, 7))
        bond = PersonalityEngine.recordMood(.hungry, in: bond, at: at(10, 40))    // same mood, later: sampled again
        XCTAssertEqual(bond.moodHistory.map(\.mood), [.happy, .hungry, .hungry])

        for i in 0..<(PersonalityEngine.moodHistoryLimit + 10) {
            bond = PersonalityEngine.recordMood(i % 2 == 0 ? .idle : .loving, in: bond, at: at(day: 1, 0, 0).addingTimeInterval(Double(i) * 60))
        }
        XCTAssertEqual(bond.moodHistory.count, PersonalityEngine.moodHistoryLimit)
    }

    func testMoodsTodayAndDominantMood() {
        var bond = BondState()
        bond = PersonalityEngine.recordMood(.sleeping, in: bond, at: at(day: -1, 23))
        bond = PersonalityEngine.recordMood(.happy, in: bond, at: at(9))
        bond = PersonalityEngine.recordMood(.loving, in: bond, at: at(10))
        bond = PersonalityEngine.recordMood(.happy, in: bond, at: at(11))
        XCTAssertEqual(PersonalityEngine.moodsToday(bond, at: at(12), calendar: calendar).count, 3)
        XCTAssertEqual(PersonalityEngine.dominantMoodToday(bond, at: at(12), calendar: calendar), .happy)
        XCTAssertNil(PersonalityEngine.dominantMoodToday(bond, at: at(day: 3, 12), calendar: calendar))
    }

    // MARK: Persistence

    func testBondRoundTripAndDefaults() throws {
        let suite = "murzik.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = PetStorage(defaults: defaults)
        XCTAssertEqual(storage.loadBond(), BondState())

        var bond = PersonalityEngine.recordLove(BondState(lastVisit: at(9)), at: at(10), calendar: calendar)
        bond = PersonalityEngine.recordMood(.loving, in: bond, at: at(10))
        bond = PersonalityEngine.applySurprise(.gift(.star), to: bond, at: at(11))
        storage.saveBond(bond)
        XCTAssertEqual(storage.loadBond(), bond)
        // The state is stored independently.
        XCTAssertNil(defaults.data(forKey: PetStorage.stateKey))
    }

    func testBondDecodesPartialAndUnknownJSON() throws {
        let json = #"{"streakDays": 5, "somethingNew": true, "moodHistory": [{"mood": "notAMood", "date": 0}]}"#
        let bond = try JSONDecoder().decode(BondState.self, from: Data(json.utf8))
        XCTAssertEqual(bond.streakDays, 5)
        XCTAssertEqual(bond.totalLove, 0)
        XCTAssertNil(bond.lastVisit)
        XCTAssertTrue(bond.moodHistory.isEmpty)
    }

    func testCorruptBondFallsBackToDefaults() throws {
        let suite = "murzik.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("nope".utf8), forKey: PetStorage.bondKey)
        XCTAssertEqual(PetStorage(defaults: defaults).loadBond(), BondState())
    }

    func testLegacyStateJSONStillDecodes() throws {
        // JSON written by the first version of the app (before the bond existed).
        let legacy = #"{"fullness":0.5,"energy":0.6,"happiness":0.7,"isSleeping":false,"lastUpdated":700000000}"#
        let suite = "murzik.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(legacy.utf8), forKey: PetStorage.stateKey)
        let state = PetStorage(defaults: defaults).load(now: at(12))
        XCTAssertEqual(state.fullness, 0.5, accuracy: 1e-9)
        XCTAssertEqual(state.lastUpdated, Date(timeIntervalSinceReferenceDate: 700_000_000))
        XCTAssertNil(state.lastReaction)
    }

    // MARK: Text & symbols

    func testExperienceTextAndSymbols() {
        let greetings: [Greeting] = [.firstMeeting, .goodMorning, .missedYou(hours: 3), .missedYou(hours: 30), .lateNight]
        for greeting in greetings {
            XCTAssertFalse(Strings.greetingTitle(greeting).isEmpty)
            XCTAssertFalse(Strings.greetingSubtitle(greeting).isEmpty)
            XCTAssertNotNil(UIImage(systemName: Strings.greetingSymbol(greeting)), Strings.greetingSymbol(greeting))
        }
        for gift in Gift.allCases {
            XCTAssertFalse(Strings.giftName(gift).isEmpty)
            XCTAssertNotNil(UIImage(systemName: gift.symbolName), "missing SF Symbol \(gift.symbolName)")
        }
        for phase in DayPhase.allCases {
            XCTAssertFalse(Strings.phaseTitle(phase).isEmpty)
        }
        for kind in ToyKind.allCases {
            XCTAssertNotNil(UIImage(systemName: kind.symbolName), "missing SF Symbol \(kind.symbolName)")
        }
        let uiSymbols = ["sunrise.fill", "sun.max.fill", "sunset.fill", "moon.stars.fill", "gearshape.fill", "flame.fill",
                         "gift.fill", "figure.walk", "speaker.wave.2.fill", "hand.tap.fill", "textformat", "waveform",
                         "hand.draw.fill", "heart.text.square.fill", "exclamationmark.triangle.fill", "sparkles"]
        for name in uiSymbols {
            XCTAssertNotNil(UIImage(systemName: name), "missing SF Symbol \(name)")
        }
    }

    func testPurrPatternIsValid() throws {
        XCTAssertNoThrow(try PurrHaptics.purrPattern())
    }
}
