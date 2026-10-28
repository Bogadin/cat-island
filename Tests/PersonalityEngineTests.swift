import XCTest
@testable import Murzik

final class PersonalityEngineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func hours(_ h: Double) -> Date { t0.addingTimeInterval(h * 3600) }

    // MARK: Time

    func testAwakeDecayPerHour() {
        let s = PetState(fullness: 0.8, energy: 0.9, happiness: 0.8, lastUpdated: t0)
        let a = PersonalityEngine.advance(s, to: hours(2))
        XCTAssertEqual(a.fullness, 0.64, accuracy: 1e-9)
        XCTAssertEqual(a.energy, 0.80, accuracy: 1e-9)
        XCTAssertEqual(a.happiness, 0.72, accuracy: 1e-9)
        XCTAssertEqual(a.lastUpdated, hours(2))
    }

    func testValuesClampAtZero() {
        let s = PetState(fullness: 0.1, energy: 0.1, happiness: 0.1, lastUpdated: t0)
        let a = PersonalityEngine.advance(s, to: hours(100))
        XCTAssertEqual(a.fullness, 0)
        XCTAssertEqual(a.energy, 0)
        XCTAssertEqual(a.happiness, 0)
    }

    func testSleepRestoresEnergyAndWakesUpWhenFull() {
        let s = PetState(fullness: 0.9, energy: 0.2, happiness: 0.8, isSleeping: true, lastUpdated: t0)
        // 0.8 energy to recover at 0.2/h -> wakes after 4h, then 1h awake.
        let a = PersonalityEngine.advance(s, to: hours(5))
        XCTAssertFalse(a.isSleeping)
        XCTAssertEqual(a.energy, 0.95, accuracy: 1e-9)
        XCTAssertEqual(a.fullness, 0.9 - 0.04 * 4 - 0.08, accuracy: 1e-9)
    }

    func testStillSleepingBeforeRested() {
        let s = PetState(energy: 0.2, isSleeping: true, lastUpdated: t0)
        let a = PersonalityEngine.advance(s, to: hours(1))
        XCTAssertTrue(a.isSleeping)
        XCTAssertEqual(a.energy, 0.4, accuracy: 1e-9)
    }

    func testClockGoingBackwardsDoesNotChangeNeeds() {
        let s = PetState(fullness: 0.5, energy: 0.5, happiness: 0.5, lastUpdated: hours(3))
        let a = PersonalityEngine.advance(s, to: hours(1))
        XCTAssertEqual(a.fullness, 0.5)
        XCTAssertEqual(a.lastUpdated, hours(1))
    }

    // MARK: Actions

    func testPetMakesMurzikLoving() {
        let s = PetState(happiness: 0.5, lastUpdated: t0)
        let a = PersonalityEngine.apply(.pet, to: s, at: t0)
        XCTAssertEqual(a.happiness, 0.65, accuracy: 1e-9)
        XCTAssertEqual(PersonalityEngine.mood(for: a, at: t0), .loving)
    }

    func testPetWhenVeryHappyIsExcited() {
        let s = PetState(happiness: 0.9, lastUpdated: t0)
        let a = PersonalityEngine.apply(.pet, to: s, at: t0)
        XCTAssertEqual(PersonalityEngine.mood(for: a, at: t0), .excited)
    }

    func testPettingASleepingCatKeepsHimAsleep() {
        let s = PetState(isSleeping: true, lastUpdated: t0)
        let a = PersonalityEngine.apply(.pet, to: s, at: t0)
        XCTAssertTrue(a.isSleeping)
        XCTAssertNil(a.lastReaction)
        XCTAssertEqual(PersonalityEngine.mood(for: a, at: t0), .sleeping)
    }

    func testFeedingAHungryCatMakesHimExcited() {
        let s = PetState(fullness: 0.1, lastUpdated: t0)
        XCTAssertEqual(PersonalityEngine.mood(for: s, at: t0), .hungry)
        let a = PersonalityEngine.apply(.feed, to: s, at: t0)
        XCTAssertEqual(a.fullness, 0.45, accuracy: 1e-9)
        XCTAssertEqual(PersonalityEngine.mood(for: a, at: t0), .excited)
    }

    func testFeedingWakesHimUp() {
        let s = PetState(fullness: 0.5, isSleeping: true, lastUpdated: t0)
        let a = PersonalityEngine.apply(.feed, to: s, at: t0)
        XCTAssertFalse(a.isSleeping)
        XCTAssertEqual(PersonalityEngine.mood(for: a, at: t0), .happy)
    }

    func testPlayCostsEnergyAndFood() {
        let s = PetState(fullness: 0.8, energy: 0.8, happiness: 0.5, lastUpdated: t0)
        let a = PersonalityEngine.apply(.play, to: s, at: t0)
        XCTAssertEqual(a.happiness, 0.7, accuracy: 1e-9)
        XCTAssertEqual(a.energy, 0.7, accuracy: 1e-9)
        XCTAssertEqual(a.fullness, 0.75, accuracy: 1e-9)
        XCTAssertEqual(PersonalityEngine.mood(for: a, at: t0), .playful)
    }

    func testTooTiredToPlay() {
        let s = PetState(energy: 0.1, lastUpdated: t0)
        let a = PersonalityEngine.apply(.play, to: s, at: t0)
        XCTAssertEqual(a.energy, 0.1, accuracy: 1e-9)
        XCTAssertEqual(PersonalityEngine.mood(for: a, at: t0), .sleepy)
    }

    func testSleepAndWake() {
        let s = PetState(lastUpdated: t0)
        let asleep = PersonalityEngine.apply(.sleep, to: s, at: t0)
        XCTAssertTrue(asleep.isSleeping)
        XCTAssertEqual(PersonalityEngine.mood(for: asleep, at: t0), .sleeping)

        let awake = PersonalityEngine.apply(.wake, to: asleep, at: hours(0.5))
        XCTAssertFalse(awake.isSleeping)
        XCTAssertEqual(PersonalityEngine.mood(for: awake, at: hours(0.5)), .surprised)
    }

    func testWakingAnAwakeCatDoesNothing() {
        let s = PetState(lastUpdated: t0)
        let a = PersonalityEngine.apply(.wake, to: s, at: t0)
        XCTAssertNil(a.lastReaction)
        XCTAssertFalse(a.isSleeping)
    }

    func testActionsNeverExceedBounds() {
        var s = PetState(fullness: 0.95, energy: 1, happiness: 0.99, lastUpdated: t0)
        for action in PetAction.allCases + PetAction.allCases {
            s = PersonalityEngine.apply(action, to: s, at: t0)
            for v in [s.fullness, s.energy, s.happiness] {
                XCTAssert((0...1).contains(v), "\(action) produced \(v)")
            }
        }
    }

    // MARK: Mood

    func testReactionExpiresBackToBaseMood() {
        let s = PetState(fullness: 0.8, energy: 0.8, happiness: 0.85, lastUpdated: t0)
        let a = PersonalityEngine.apply(.feed, to: s, at: t0)
        XCTAssertEqual(PersonalityEngine.mood(for: a, at: t0.addingTimeInterval(1)), .happy)
        let later = t0.addingTimeInterval(PersonalityEngine.reactionDuration + 1)
        XCTAssertEqual(PersonalityEngine.mood(for: a, at: later), PersonalityEngine.baseMood(for: a))
    }

    func testReactionFromTheFutureIsIgnored() {
        var s = PetState(lastUpdated: t0)
        s.lastReaction = .init(mood: .loving, date: hours(1))
        XCTAssertEqual(PersonalityEngine.mood(for: s, at: t0), PersonalityEngine.baseMood(for: s))
    }

    func testBaseMoodPriority() {
        XCTAssertEqual(PersonalityEngine.baseMood(for: PetState(fullness: 0.1, energy: 0.1, isSleeping: true)), .sleeping)
        XCTAssertEqual(PersonalityEngine.baseMood(for: PetState(fullness: 0.1, energy: 0.1)), .hungry)
        XCTAssertEqual(PersonalityEngine.baseMood(for: PetState(fullness: 0.8, energy: 0.1)), .sleepy)
        XCTAssertEqual(PersonalityEngine.baseMood(for: PetState(fullness: 0.8, energy: 0.8, happiness: 0.9)), .happy)
        XCTAssertEqual(PersonalityEngine.baseMood(for: PetState(fullness: 0.8, energy: 0.8, happiness: 0.2)), .playful)
        XCTAssertEqual(PersonalityEngine.baseMood(for: PetState(fullness: 0.8, energy: 0.8, happiness: 0.5)), .idle)
    }

    // MARK: Hunger prediction

    func testHungryDateWhileAwake() {
        let s = PetState(fullness: 0.65, lastUpdated: t0)
        // (0.65 - 0.25) / 0.08 = 5h
        XCTAssertEqual(PersonalityEngine.hungryDate(for: s).timeIntervalSince(t0), 5 * 3600, accuracy: 1)
    }

    func testHungryDateMatchesSimulation() {
        let s = PetState(fullness: 0.9, energy: 0.6, isSleeping: true, lastUpdated: t0)
        let date = PersonalityEngine.hungryDate(for: s)
        let before = PersonalityEngine.advance(s, to: date.addingTimeInterval(-60))
        let after = PersonalityEngine.advance(s, to: date.addingTimeInterval(60))
        XCTAssertNotEqual(PersonalityEngine.baseMood(for: before), .hungry)
        XCTAssertEqual(PersonalityEngine.baseMood(for: after), .hungry)
    }

    func testHungryDateWhenAlreadyHungryIsNow() {
        let s = PetState(fullness: 0.1, lastUpdated: t0)
        XCTAssertEqual(PersonalityEngine.hungryDate(for: s), t0)
    }

    // MARK: Live Activity content

    func testContentStateUsesStaleToShowHunger() {
        let s = PetState(fullness: 0.8, energy: 0.8, happiness: 0.5, lastUpdated: t0)
        let content = MurzikAttributes.ContentState(state: s, now: t0)
        XCTAssertEqual(content.displayMood(isStale: false), .idle)
        XCTAssertEqual(content.displayMood(isStale: true), .hungry)
        XCTAssertTrue(content.showsHungerCountdown(isStale: false, now: t0))
        XCTAssertFalse(content.showsHungerCountdown(isStale: true, now: t0))
    }

    func testSleepingCatStaysAsleepWhenStaleIfStillSleeping() {
        // Low fullness, little sleep left to do? He wakes first -> hungry when stale.
        let wakesFirst = PetState(fullness: 0.6, energy: 0.9, isSleeping: true, lastUpdated: t0)
        let c1 = MurzikAttributes.ContentState(state: wakesFirst, now: t0)
        XCTAssertNotNil(c1.wakesAt)
        XCTAssertEqual(c1.displayMood(isStale: true), .hungry)

        // Long sleep ahead and nearly hungry: still asleep when hunger arrives.
        let sleepsOn = PetState(fullness: 0.3, energy: 0.0, isSleeping: true, lastUpdated: t0)
        let c2 = MurzikAttributes.ContentState(state: sleepsOn, now: t0)
        XCTAssertEqual(c2.displayMood(isStale: true), .sleeping)
    }

    func testContentStateRoundTripsAndFitsPayloadLimit() throws {
        let content = MurzikAttributes.ContentState(state: PetState(lastUpdated: t0), now: t0)
        let data = try JSONEncoder().encode(content)
        XCTAssertLessThan(data.count, 4096)
        XCTAssertEqual(try JSONDecoder().decode(MurzikAttributes.ContentState.self, from: data), content)
    }

    // MARK: Persistence

    func testStorageRoundTrip() throws {
        let suite = "murzik.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = PetStorage(defaults: defaults)

        let fresh = storage.load(now: t0)
        XCTAssertEqual(fresh.lastUpdated, t0)

        var s = PetState(fullness: 0.3, energy: 0.4, happiness: 0.5, isSleeping: true, lastUpdated: t0)
        s.lastReaction = .init(mood: .loving, date: t0)
        storage.save(s)
        XCTAssertEqual(storage.load(now: hours(5)), s)

        XCTAssertTrue(storage.islandEnabled)
        storage.islandEnabled = false
        XCTAssertFalse(storage.islandEnabled)
    }

    func testCorruptStorageFallsBackToDefaults() throws {
        let suite = "murzik.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: PetStorage.stateKey)
        let s = PetStorage(defaults: defaults).load(now: t0)
        XCTAssertEqual(s, PetState(lastUpdated: t0))
    }

    func testEveryMoodHasTextAndSymbol() {
        for mood in MurzikMood.allCases {
            XCTAssertFalse(Strings.moodTitle(mood).isEmpty)
            XCTAssertFalse(Strings.moodMessage(mood).isEmpty)
            XCTAssertNotNil(UIImage(systemName: mood.symbolName), "missing SF Symbol \(mood.symbolName)")
        }
        for action in PetAction.allCases {
            XCTAssertNotNil(UIImage(systemName: action.symbolName), "missing SF Symbol \(action.symbolName)")
        }
    }
}
