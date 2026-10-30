import SwiftUI
import XCTest
@testable import Murzik

/// Geometry, choreography continuity and fallback-pose renders of the in-app island walker.
@MainActor
final class IslandWalkerTests: XCTestCase {
    /// iPhone 17 Pro Max (portrait).
    private let proMax = IslandGeometry(screen: CGSize(width: 440, height: 956), safeTop: 62)
    /// iPhone 14 Pro.
    private let pro14 = IslandGeometry(screen: CGSize(width: 393, height: 852), safeTop: 59)
    /// iPhone 13 (notch).
    private let notch = IslandGeometry(screen: CGSize(width: 390, height: 844), safeTop: 47)

    // MARK: Geometry

    func testIslandDetection() {
        XCTAssertTrue(proMax.hasIsland)
        XCTAssertTrue(pro14.hasIsland)
        XCTAssertFalse(notch.hasIsland)
        XCTAssertFalse(IslandGeometry(screen: CGSize(width: 375, height: 667), safeTop: 20).hasIsland)
        XCTAssertFalse(IslandGeometry(screen: CGSize(width: 820, height: 1180), safeTop: 24, isPhone: false).hasIsland)
    }

    func testPillRect() {
        XCTAssertEqual(proMax.pill.width, 126, accuracy: 0.01)
        XCTAssertEqual(proMax.pill.height, 37.33, accuracy: 0.01)
        XCTAssertEqual(proMax.pill.midX, 220, accuracy: 0.01)
        XCTAssertEqual(proMax.pill.minY, 14.33, accuracy: 0.05)
        XCTAssertEqual(pro14.pill.minY, 11.33, accuracy: 0.05)
        XCTAssertEqual(pro14.pill.midX, 196.5, accuracy: 0.01)
        // Without an island the virtual pill ends at the bottom of the status bar.
        XCTAssertEqual(notch.pill.maxY, 47, accuracy: 0.01)
    }

    func testFloorsAndSurfaces() {
        let g = proMax
        XCTAssertGreaterThan(g.underFloorY - IslandGeometry.catHeight, g.pill.maxY, "standing under the island he must not overlap it")
        XCTAssertEqual(g.surface(at: CGPoint(x: 200, y: g.underFloorY)), .under)
        XCTAssertEqual(g.surface(at: CGPoint(x: g.leftLedgeX, y: g.ledgeY)), .ledgeLeft)
        XCTAssertEqual(g.surface(at: CGPoint(x: g.rightLedgeX, y: g.ledgeY)), .ledgeRight)
        XCTAssertEqual(g.surface(at: CGPoint(x: g.insideLeftX, y: g.ledgeY)), .inside)
        XCTAssertEqual(g.surface(at: CGPoint(x: g.pill.midX, y: g.insideFeetY)), .inside)
        XCTAssertEqual(g.surface(at: CGPoint(x: 100, y: 300)), .air)
        // Ledges sit between the status-bar clock / icons and the island.
        XCTAssertLessThan(g.leftLedgeX + 12, g.pill.minX)
        XCTAssertGreaterThan(g.rightLedgeX - 12, g.pill.maxX)
        XCTAssertLessThan(g.rightLedgeX + 12, g.screen.width - 100)
        // Hidden positions are fully covered by the island.
        XCTAssertTrue(g.pill.contains(g.catRect(feet: CGPoint(x: g.insideLeftX, y: g.ledgeY))))
        XCTAssertTrue(g.pill.contains(g.catRect(feet: CGPoint(x: g.insideRightX, y: g.ledgeY))))
        XCTAssertTrue(g.pill.contains(g.catRect(feet: CGPoint(x: g.pill.midX, y: g.insideFeetY))))
    }

    // MARK: Motion

    func testTrapezoidEasing() {
        XCTAssertEqual(WalkerMotion.trapezoid(0), 0, accuracy: 1e-9)
        XCTAssertEqual(WalkerMotion.trapezoid(1), 1, accuracy: 1e-9)
        XCTAssertEqual(WalkerMotion.trapezoid(0.5), 0.5, accuracy: 1e-9)
        var last = 0.0
        for i in 1...100 {
            let v = WalkerMotion.trapezoid(Double(i) / 100)
            XCTAssertGreaterThanOrEqual(v, last)
            last = v
        }
    }

    func testWalkCycleFramesFollowDistance() {
        let from = CGPoint(x: 100, y: proMax.underFloorY)
        let to = CGPoint(x: 300, y: proMax.underFloorY)
        let duration = WalkerMotion.walkDuration(distance: 200, speed: 40)
        let segment = WalkerSegment(kind: .walk(from: from, to: to, speed: 40), duration: duration, end: to, endSurface: .under, endFacingLeft: false)
        var frames = Set<Int>()
        var t = 0.0
        while t < duration {
            let f = WalkerMotion.sample(segment, at: t, clock: t, geometry: proMax)
            frames.insert(f.walkFrame)
            XCTAssertEqual(f.feet.y, from.y)
            XCTAssertFalse(f.facingLeft)
            t += 1.0 / 30
        }
        XCTAssertEqual(frames, Set(0..<8), "all 8 walk frames are used")
        let end = WalkerMotion.sample(segment, at: duration, clock: duration, geometry: proMax)
        XCTAssertEqual(end.feet.x, to.x, accuracy: 0.01)
        // ~11 sprite frames per second at cruising speed.
        let fps = (200 / WalkerMotion.stride(speed: 40)) / duration
        XCTAssertTrue((8...12).contains(fps), "walk fps \(fps)")
    }

    func testHopLandsWithSquash() {
        let from = CGPoint(x: 120, y: proMax.underFloorY)
        let to = CGPoint(x: proMax.leftLedgeX, y: proMax.ledgeY)
        var s = WalkerScript(geometry: proMax, point: from, surface: .under, facingLeft: false)
        s.hop(to: to, surface: .ledgeLeft)
        XCTAssertEqual(s.segments.count, 2)
        let hop = s.segments[0]
        let apex = stride(from: 0.0, through: hop.duration, by: 0.01)
            .map { WalkerMotion.sample(hop, at: $0, clock: 0, geometry: proMax).feet.y }
            .min() ?? 0
        XCTAssertLessThan(apex, to.y - 5, "hop rises above the ledge")
        let land = WalkerMotion.sample(s.segments[1], at: 0, clock: 0, geometry: proMax)
        XCTAssertLessThan(land.scaleY, 0.8)
        XCTAssertGreaterThan(land.scaleX, 1.1)
        XCTAssertEqual(s.surface, .ledgeLeft)
    }

    /// Every plan, for every mood and many seeds, is continuous and well formed.
    func testPlansAreContinuous() {
        for geo in [proMax, pro14, notch] {
            for mood in MurzikMood.allCases {
                for seed in UInt64(1)...25 {
                    var planner = WalkerPlanner(geometry: geo, seed: seed)
                    var frame = planner.startFrame
                    for round in 0..<4 {
                        let plan = planner.plan(mood: mood, from: frame, showcase: round == 0 && seed % 2 == 0)
                        XCTAssertFalse(plan.isEmpty)
                        var previous: WalkerFrame?
                        var previousKind: WalkerSegment.Kind?
                        for segment in plan {
                            XCTAssertGreaterThan(segment.duration, 0)
                            let start = WalkerMotion.sample(segment, at: 0, clock: 0, geometry: geo)
                            let end = WalkerMotion.sample(segment, at: segment.duration, clock: 0, geometry: geo)
                            for f in [start, end] {
                                XCTAssertTrue(f.feet.x.isFinite && f.feet.y.isFinite)
                                XCTAssertGreaterThan(f.feet.x, 0)
                                XCTAssertLessThan(f.feet.x, geo.screen.width)
                            }
                            if let previous, Self.shouldBeContinuous(previous, previousKind, start, segment.kind) {
                                let gap = hypot(previous.feet.x - start.feet.x, previous.feet.y - start.feet.y)
                                XCTAssertLessThan(gap, 1.5, "jump of \(gap) pt in \(mood) seed \(seed): \(String(describing: previousKind)) → \(segment.kind)")
                            }
                            if case let .hold(pose, at, _, _) = segment.kind, pose == .hidden {
                                XCTAssertTrue(geo.pill.contains(geo.catRect(feet: at)), "hidden but visible at \(at)")
                            }
                            previous = end
                            previousKind = segment.kind
                        }
                        // Continue from where the plan ended (the simulation re-plans the same way).
                        if let last = plan.last {
                            frame = WalkerMotion.sample(last, at: last.duration, clock: 0, geometry: geo)
                        }
                    }
                }
            }
        }
    }

    private static func shouldBeContinuous(_ a: WalkerFrame, _ aKind: WalkerSegment.Kind?, _ b: WalkerFrame, _ bKind: WalkerSegment.Kind) -> Bool {
        if a.pose == .hidden || b.pose == .hidden || a.upsideDown || b.upsideDown { return false }
        if case .drop = bKind { return false }
        if case .peekSide = bKind { return false }
        if let aKind, case .chase = aKind { return false }
        return true
    }

    func testSleepingEndsCurledBesideTheIsland() {
        var planner = WalkerPlanner(geometry: proMax, seed: 3)
        let plan = planner.plan(mood: .sleeping, from: planner.startFrame)
        guard let last = plan.last, case let .hold(pose, at, _, _) = last.kind else {
            return XCTFail("sleeping plan should end with a hold")
        }
        XCTAssertEqual(pose, .sleep)
        XCTAssertEqual(at.y, proMax.ledgeY, accuracy: 0.5)
        XCTAssertLessThan(at.x, proMax.pill.minX)
    }

    func testHungryPlanMeows() {
        var planner = WalkerPlanner(geometry: proMax, seed: 5)
        let start = WalkerFrame(feet: CGPoint(x: 200, y: proMax.underFloorY), pose: .sitFront)
        let plan = planner.plan(mood: .hungry, from: start)
        let meows = plan.filter {
            if case let .hold(_, _, _, bubble) = $0.kind { return bubble == WalkerPlanner.meow }
            return false
        }
        XCTAssertGreaterThanOrEqual(meows.count, 2)
    }

    func testShowcaseGoesInAndOutOfTheIsland() {
        var planner = WalkerPlanner(geometry: proMax, seed: 1)
        let plan = planner.plan(mood: .idle, from: planner.startFrame, showcase: true)
        var kinds: [String] = []
        for segment in plan {
            switch segment.kind {
            case .peekDown: kinds.append("peekDown")
            case .drop: kinds.append("drop")
            case .peekSide: kinds.append("peekSide")
            case let .hold(pose, _, _, _) where pose == .hidden: kinds.append("hidden")
            default: break
            }
        }
        XCTAssertEqual(kinds, ["peekDown", "drop", "hidden", "peekSide"])
    }

    // MARK: Simulation

    func testSimulationRunsAndReactsToPetAndDrag() {
        let sim = WalkerSimulation(seed: 9)
        sim.forcedMood = .idle
        var visited = Set<WalkerSurface>()
        for _ in 0..<(30 * 40) {
            sim.step(mood: .idle, geometry: proMax, dt: 1.0 / 30)
            let f = sim.currentFrame
            visited.insert(proMax.surface(at: f.feet, hidden: f.pose == .hidden))
        }
        XCTAssertTrue(visited.contains(.under))
        XCTAssertTrue(visited.contains(.inside))
        XCTAssertTrue(visited.contains(.ledgeLeft) || visited.contains(.ledgeRight))

        // Drag him somewhere and let go: he falls back to the floor under the island.
        sim.drag(to: CGPoint(x: 300, y: 400))
        sim.step(mood: .idle, geometry: proMax, dt: 1.0 / 30)
        XCTAssertEqual(sim.currentFrame.pose, .dangle)
        sim.release()
        for _ in 0..<60 { sim.step(mood: .idle, geometry: proMax, dt: 1.0 / 30) }
        XCTAssertEqual(sim.currentFrame.feet.y, proMax.underFloorY, accuracy: 1)

        // Pet: hop + heart.
        sim.pet()
        sim.step(mood: .idle, geometry: proMax, dt: 1.0 / 30)
        var minY = CGFloat.infinity
        for _ in 0..<30 {
            sim.step(mood: .idle, geometry: proMax, dt: 1.0 / 30)
            minY = min(minY, sim.currentFrame.feet.y)
        }
        XCTAssertLessThan(minY, proMax.underFloorY - 8)
        XCTAssertFalse(sim.advance(to: .now, mood: .idle, geometry: proMax).effects.isEmpty)
    }

    func testPausesDoNotTeleport() {
        let sim = WalkerSimulation(seed: 2)
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        _ = sim.advance(to: t0, mood: .idle, geometry: proMax)
        _ = sim.advance(to: t0.addingTimeInterval(1.0 / 30), mood: .idle, geometry: proMax)
        let before = sim.time
        _ = sim.advance(to: t0.addingTimeInterval(600), mood: .idle, geometry: proMax)
        XCTAssertLessThan(sim.time - before, 0.1)
    }

    // MARK: Renders

    /// Renders every pose (2D fallbacks until the 3D sprites exist) for review.
    func testRenderWalkerPoses() throws {
        let poses: [(String, WalkerPose)] = [
            ("walk", .walk), ("stand", .stand), ("jump", .jump), ("pounce", .pounce),
            ("stretch", .stretch), ("dangle", .dangle), ("sit", .sitFront), ("sitSide", .sitSide),
            ("groom", .groom), ("loaf", .loaf), ("sleep", .sleep), ("peek", .peekDown),
        ]
        let sheet = VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<8, id: \.self) { i in
                    VStack(spacing: 2) {
                        WalkerCatView(frame: WalkerFrame(feet: .zero, pose: .walk, walkPhase: Double(i)), mood: .idle, time: Double(i) * 0.09, size: 88)
                            .background(Rectangle().stroke(Color.gray.opacity(0.3)))
                        Text("walk \(i)").font(.caption2)
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(Array(poses.enumerated()), id: \.offset) { item in
                    VStack(spacing: 2) {
                        WalkerCatView(frame: WalkerFrame(feet: .zero, pose: item.element.1), mood: .happy, time: 0.5, size: 88)
                            .background(Rectangle().stroke(Color.gray.opacity(0.3)))
                        Text(item.element.0).font(.caption2)
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach([MurzikMood.idle, .hungry, .loving, .playful, .sleepy, .excited], id: \.self) { mood in
                    WalkerCatView(frame: WalkerFrame(feet: .zero, pose: .sitFront), mood: mood, time: 0.5, size: 88)
                }
                WalkerCatView(frame: WalkerFrame(feet: .zero, pose: .walk, facingLeft: true, walkPhase: 2), mood: .idle, time: 0, size: 88)
            }
        }
        .padding(16)
        .background(MurzikPalette.cream)
        .environment(\.layoutDirection, .leftToRight)

        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let data = try XCTUnwrap(image.pngData())
        if let path = ProcessInfo.processInfo.environment["RENDER_DIR"] {
            let dir = URL(fileURLWithPath: path).appendingPathComponent("walker")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent("walker-poses.png"))
        }
    }
}
