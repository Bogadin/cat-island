import XCTest
@testable import Murzik

/// Pure choreography logic for Murzik walking in the Dynamic Island.
final class LiveActivityChoreographyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func assertWellFormed(_ beats: [IslandBeat], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(beats.isEmpty, file: file, line: line)
        XCTAssertLessThanOrEqual(beats.count, IslandChoreography.maxBeats, file: file, line: line)
        var previous: IslandBeat?
        for beat in beats {
            XCTAssertTrue((0...1).contains(beat.scene.position), "position \(beat.scene.position)", file: file, line: line)
            if let previous {
                // Updates are spaced so each ≤2 s animation finishes and we don't spam ActivityKit.
                XCTAssertGreaterThanOrEqual(beat.at - previous.at, 1.2, file: file, line: line)
                XCTAssertGreaterThan(beat.scene.step, previous.scene.step, file: file, line: line)
            }
            previous = beat
        }
        let last = beats[beats.count - 1]
        XCTAssertEqual(last.scene.pose, .rest, "must end resting", file: file, line: line)
        XCTAssertEqual(last.scene.effect, .none, file: file, line: line)
        XCTAssertLessThan(last.at, 20, "must fit in a background task", file: file, line: line)
    }

    func testAnimationFitsBetweenBeats() {
        XCTAssertLessThanOrEqual(IslandChoreography.animationDuration, 2)
        XCTAssertLessThan(IslandChoreography.animationDuration, IslandChoreography.stepInterval)
        XCTAssertLessThan(IslandChoreography.animationDuration, IslandChoreography.trotInterval)
    }

    func testCrossingWalksFromLeadingToTrailingThroughTheCamera() {
        let beats = IslandChoreography.crossing(from: IslandScene(position: IslandChoreography.leftSpot))
        assertWellFormed(beats)
        XCTAssertEqual(beats.first?.scene.pose, .walk)
        XCTAssertLessThanOrEqual(beats.count, 5, "few updates: iOS throttles bursts")
        let walking = beats.filter { $0.scene.pose == .walk }
        XCTAssertGreaterThanOrEqual(walking.count, 3)
        XCTAssertTrue(walking.allSatisfy { !$0.scene.facingLeft })
        XCTAssertTrue(walking.contains { $0.scene.compactSide == .leading })
        XCTAssertTrue(walking.contains { $0.scene.compactSide == .trailing })
        // Strictly moving right, alternating walk frames.
        for (a, b) in zip(walking, walking.dropFirst()) {
            XCTAssertGreaterThan(b.scene.position, a.scene.position)
            XCTAssertNotEqual(a.scene.frame, b.scene.frame)
        }
        XCTAssertEqual(beats.last!.scene.position, IslandChoreography.rightSpot, accuracy: 0.001)
    }

    func testCrossingFromTheRightWalksBackLeft() {
        let beats = IslandChoreography.crossing(from: IslandScene(position: 0.84))
        assertWellFormed(beats)
        XCTAssertTrue(beats.filter { $0.scene.pose == .walk }.allSatisfy { $0.scene.facingLeft })
        XCTAssertEqual(beats.last!.scene.position, IslandChoreography.leftSpot, accuracy: 0.001)
    }

    func testCrossingWaitsForTheReactionBeforeSitting() {
        let beats = IslandChoreography.crossing(from: IslandScene(position: 0.16), restNotBefore: 15)
        assertWellFormed(beats)
        XCTAssertEqual(beats.last!.at, 15, accuracy: 0.001)
    }

    func testPetWalksToThePetButtonAndShowsHearts() {
        let beats = IslandChoreography.reaction(to: .pet, reactionMood: .loving, isSleeping: false, from: IslandScene(position: 0.16), restNotBefore: 6.3)
        assertWellFormed(beats)
        XCTAssertTrue(beats.contains { $0.scene.pose == .walk })
        XCTAssertTrue(beats.contains { $0.scene.pose == .hop && $0.scene.effect == .hearts })
        XCTAssertEqual(beats.last!.scene.position, IslandChoreography.petSpot, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(beats.last!.at, 6.3)
        XCTAssertLessThan(beats.last!.at, 10, "an island button should finish quickly")
    }

    func testFeedWalksToTheBowlAndEats() {
        let beats = IslandChoreography.reaction(to: .feed, reactionMood: .excited, isSleeping: false, from: IslandScene(position: 0.84), restNotBefore: 6.3)
        assertWellFormed(beats)
        let eat = beats.first { $0.scene.pose == .eat }
        XCTAssertNotNil(eat)
        XCTAssertEqual(eat?.scene.effect, .food)
        XCTAssertEqual(eat?.scene.facingLeft, true)
        XCTAssertEqual(beats.last!.scene.position, IslandChoreography.feedSpot, accuracy: 0.001)
    }

    func testAlreadyAtTheButtonReactsInPlace() {
        let start = IslandScene(position: IslandChoreography.petSpot)
        let beats = IslandChoreography.reaction(to: .pet, reactionMood: .loving, isSleeping: false, from: start, restNotBefore: 0)
        assertWellFormed(beats)
        XCTAssertFalse(beats.contains { $0.scene.pose == .walk })
        XCTAssertEqual(beats.first?.scene.pose, .hop)
    }

    func testSleepingCatDoesNotWalk() {
        let start = IslandScene(position: 0.3)
        let beats = IslandChoreography.reaction(to: .pet, reactionMood: nil, isSleeping: true, from: start, restNotBefore: 0)
        assertWellFormed(beats)
        XCTAssertTrue(beats.allSatisfy { $0.scene.position == 0.3 && $0.scene.pose == .rest })
        XCTAssertEqual(beats.first?.scene.effect, .hearts)
    }

    func testCompactMapping() {
        XCTAssertEqual(IslandScene(position: 0.1).compactSide, .leading)
        XCTAssertEqual(IslandScene(position: 0.5).compactSide, .trailing)
        XCTAssertEqual(IslandScene(position: 0.25).compactLocalPosition, 0.5, accuracy: 0.0001)
        XCTAssertEqual(IslandScene(position: 0.5).compactLocalPosition, 0, accuracy: 0.0001)
        XCTAssertEqual(IslandScene(position: 1).compactLocalPosition, 1, accuracy: 0.0001)
    }

    func testSpritesForPoses() {
        XCTAssertEqual(IslandScene(pose: .walk, frame: 9).sprite(for: .idle), .walk1)
        XCTAssertEqual(IslandScene(pose: .rest).sprite(for: .sleeping), .sleeping)
        XCTAssertEqual(IslandScene(pose: .hop).sprite(for: .loving), .excited)
        let resting = IslandScene(position: 0.7, facingLeft: true, pose: .walk, frame: 3, effect: .hearts, step: 4).resting()
        XCTAssertEqual(resting.pose, .rest)
        XCTAssertEqual(resting.effect, .none)
        XCTAssertEqual(resting.position, 0.7)
        XCTAssertEqual(resting.step, 5)
    }

    // MARK: Payload

    func testContentWithSceneFitsPayloadAndRoundTrips() throws {
        var content = MurzikAttributes.ContentState(state: PetState(lastUpdated: t0), now: t0)
        content.stage = IslandSceneStore.withTrail(
            IslandScene(position: 0.33, facingLeft: true, pose: .walk, frame: 5, effect: .hearts, step: 123_456),
            hungryAt: content.hungryAt
        )
        let data = try JSONEncoder().encode(content)
        XCTAssertLessThan(data.count, 4096)
        XCTAssertLessThan(data.count, 600, "keep updates tiny")
        XCTAssertEqual(try JSONDecoder().decode(MurzikAttributes.ContentState.self, from: data), content)
    }

    func testContentFromOlderBuildsWithoutSceneDecodes() throws {
        let content = MurzikAttributes.ContentState(state: PetState(lastUpdated: t0), now: t0)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(content)) as? [String: Any])
        json.removeValue(forKey: "stage")
        let old = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(MurzikAttributes.ContentState.self, from: old)
        XCTAssertNil(decoded.stage)
        XCTAssertEqual(decoded.scene, .home)
    }

    func testTrailEndsAtHungerAndDoesNotDependOnUpdateTime() {
        let s1 = PetState(fullness: 0.6, lastUpdated: t0)
        let c1 = MurzikAttributes.ContentState(state: s1, now: t0)
        let later = t0.addingTimeInterval(1800)
        let c2 = MurzikAttributes.ContentState(state: PersonalityEngine.advance(s1, to: later), now: later)
        let trail1 = IslandSceneStore.withTrail(.home, hungryAt: c1.hungryAt)
        let trail2 = IslandSceneStore.withTrail(.home, hungryAt: c2.hungryAt)
        XCTAssertEqual(trail1.trailTo, c1.hungryAt)
        XCTAssertNotNil(trail1.trailRange)
        XCTAssertEqual(trail1.trailFrom!.timeIntervalSince1970, trail2.trailFrom!.timeIntervalSince1970, accuracy: 1)
    }
}
