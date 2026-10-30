import SwiftUI
import XCTest
@testable import Murzik

/// Renders Murzik and the real Live Activity views to PNG files so the design can be reviewed
/// without a device. Output directory: $RENDER_DIR (set via TEST_RUNNER_RENDER_DIR), or tmp.
@MainActor
final class RenderTests: XCTestCase {
    private var outputDir: URL {
        let path = ProcessInfo.processInfo.environment["RENDER_DIR"]
        let url = path.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("murzik-renders")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func save<V: View>(_ view: V, name: String, scale: CGFloat = 3) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.uiImage, "render failed: \(name)")
        let data = try XCTUnwrap(image.pngData())
        XCTAssertGreaterThan(image.size.width, 0)
        try data.write(to: outputDir.appendingPathComponent("\(name).png"))
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private let t0 = Date.now

    private func content(for mood: MurzikMood) -> MurzikAttributes.ContentState {
        var state = PetState(fullness: 0.62, energy: 0.7, happiness: 0.85, lastUpdated: t0)
        switch mood {
        case .sleeping, .sleepy: state.isSleeping = mood == .sleeping; state.energy = 0.2
        case .hungry: state.fullness = 0.12
        default: break
        }
        var content = MurzikAttributes.ContentState(state: state, now: t0)
        content.mood = mood
        return content
    }

    // MARK: Character sheet

    func testRenderCharacterSheet() throws {
        let sheet = VStack(spacing: 18) {
            Text("Murzik — all moods").font(.title2.bold()).foregroundStyle(.white)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(150), spacing: 16), count: 5), spacing: 16) {
                ForEach(MurzikMood.allCases, id: \.self) { mood in
                    VStack(spacing: 8) {
                        CatFace(mood: mood).frame(width: 130, height: 130)
                        Text(mood.rawValue).font(.headline).foregroundStyle(.white)
                    }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(60), spacing: 10), count: 10), spacing: 10) {
                ForEach(MurzikMood.allCases, id: \.self) { mood in
                    CatFace(mood: mood, detail: .compact).frame(width: 30, height: 30)
                        .frame(width: 60, height: 44)
                        .background(Capsule().fill(Color.black))
                }
            }
        }
        .padding(28)
        .background(Color(white: 0.16))
        try save(sheet, name: "character-sheet", scale: 2)
    }

    func testRenderFigureOnAppBackground() throws {
        let row = HStack(spacing: 24) {
            ForEach([MurzikMood.idle, .happy, .loving, .sleeping, .playful], id: \.self) { mood in
                CatFigure(mood: mood, tailAngle: 6).frame(width: 150, height: 200)
            }
        }
        .padding(30)
        .background(LinearGradient(colors: [MurzikPalette.cream, MurzikPalette.sand], startPoint: .top, endPoint: .bottom))
        try save(row, name: "figure-row", scale: 2)
    }

    func testRenderAppIcon() throws {
        let icon = ZStack {
            LinearGradient(colors: [MurzikPalette.cream, MurzikPalette.sand], startPoint: .top, endPoint: .bottom)
            CatFace(mood: .idle)
                .frame(width: 880, height: 880)
                .offset(y: 30)
        }
        .frame(width: 1024, height: 1024)
        try save(icon, name: "app-icon-1024", scale: 1)
    }

    // MARK: Dynamic Island mock-ups (real views, simulated island frame)

    private func content(for mood: MurzikMood, scene: IslandScene) -> MurzikAttributes.ContentState {
        var c = content(for: mood)
        c.stage = IslandSceneStore.withTrail(scene, hungryAt: c.hungryAt)
        return c
    }

    /// Compact island: leading region, camera gap, trailing region.
    private func compactIsland(_ state: MurzikAttributes.ContentState, mood: MurzikMood) -> some View {
        HStack(spacing: 0) {
            CompactLeadingView(state: state, mood: mood)
            Spacer().frame(width: 126)
            CompactTrailingView(state: state, mood: mood)
        }
        .padding(.horizontal, 10)
        .frame(height: 37)
        .background(Capsule().fill(Color.black))
    }

    /// Expanded island approximation: leading / center / trailing on top, bottom region below.
    private func expandedIsland(_ state: MurzikAttributes.ContentState) -> some View {
        let mood = state.displayMood(isStale: false)
        return VStack(spacing: 4) {
            HStack(alignment: .center) {
                ExpandedTrailingView(state: state, isStale: false)
                Spacer()
                ExpandedCenterView(name: Strings.name, mood: mood)
                Spacer()
                ExpandedLeadingView(mood: mood)
            }
            ExpandedBottomView(state: state, isStale: false)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(width: 408)
        .background(RoundedRectangle(cornerRadius: 46, style: .continuous).fill(Color.black))
    }

    private var wallpaper: some View {
        LinearGradient(colors: [Color(red: 0.55, green: 0.62, blue: 0.85), Color(red: 0.85, green: 0.6, blue: 0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    func testRenderDynamicIslandPresentations() throws {
        let rows: [(MurzikMood, IslandScene)] = [
            (.idle, IslandScene(position: 0.16)),
            (.happy, IslandScene(position: 0.84, facingLeft: true)),
            (.hungry, IslandScene(position: 0.33, pose: .walk, frame: 1)),
            (.sleeping, IslandScene(position: 0.16)),
            (.loving, IslandScene(position: 0.9, pose: .hop, effect: .hearts)),
        ]
        let view = VStack(spacing: 22) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let state = self.content(for: row.0, scene: row.1)
                HStack(spacing: 28) {
                    self.compactIsland(state, mood: row.0)
                    MinimalView(state: state, mood: row.0)
                        .frame(width: 37, height: 37)
                        .background(Circle().fill(Color.black))
                }
            }
        }
        .padding(30)
        .background(wallpaper)
        try save(view, name: "island-compact-minimal")
    }

    func testRenderExpandedIsland() throws {
        let views = VStack(spacing: 20) {
            expandedIsland(content(for: .loving, scene: IslandScene(position: 0.9, pose: .hop, effect: .hearts)))
            expandedIsland(content(for: .hungry, scene: IslandScene(position: 0.45, facingLeft: true, pose: .walk, frame: 5)))
            expandedIsland(content(for: .happy, scene: IslandScene(position: 0.1, facingLeft: true, pose: .eat, effect: .food)))
            expandedIsland(content(for: .playful, scene: IslandScene(position: 0.16)))
        }
        .padding(24)
        .background(Color(white: 0.85))
        try save(views, name: "island-expanded")
    }

    func testRenderLockScreen() throws {
        let views = VStack(spacing: 16) {
            LockScreenView(name: Strings.name, state: content(for: .happy, scene: IslandScene(position: 0.62, pose: .walk, frame: 1)), isStale: false)
                .frame(width: 408)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.82)))
            LockScreenView(name: Strings.name, state: content(for: .idle, scene: IslandScene(position: 0.2)), isStale: true)
                .frame(width: 408)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.82)))
            LockScreenView(name: Strings.name, state: content(for: .sleeping, scene: IslandScene(position: 0.84)), isStale: false)
                .frame(width: 408)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.82)))
        }
        .padding(24)
        .background(LinearGradient(colors: [Color(red: 0.2, green: 0.25, blue: 0.45), Color(red: 0.55, green: 0.35, blue: 0.5)], startPoint: .top, endPoint: .bottom))
        try save(views, name: "lock-screen")
    }

    /// Every beat of a choreography: compact island + expanded stage, top to bottom.
    private func renderSequence(_ beats: [IslandBeat], mood: MurzikMood, name: String) throws {
        let view = VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(beats.enumerated()), id: \.offset) { _, beat in
                let state = self.content(for: mood, scene: beat.scene)
                HStack(spacing: 18) {
                    Text(String(format: "t=%.1fs", beat.at))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(width: 64, alignment: .leading)
                    self.compactIsland(state, mood: mood)
                    IslandSceneView(state: state, mood: mood, isStale: false, catSize: 46)
                        .frame(width: 370, height: 56)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black))
                }
            }
        }
        .padding(24)
        .background(Color(white: 0.22))
        try save(view, name: name, scale: 2)
    }

    func testRenderWalkSequences() throws {
        try renderSequence(IslandChoreography.crossing(from: IslandScene(position: 0.16)), mood: .happy, name: "island-walk-crossing")
        try renderSequence(
            IslandChoreography.reaction(to: .pet, reactionMood: .loving, isSleeping: false, from: IslandScene(position: 0.16), restNotBefore: 6),
            mood: .loving, name: "island-walk-pet"
        )
        try renderSequence(
            IslandChoreography.reaction(to: .feed, reactionMood: .excited, isSleeping: false, from: IslandScene(position: 0.84), restNotBefore: 6),
            mood: .excited, name: "island-walk-feed"
        )
    }

    func testRenderPoseSheet() throws {
        let poses: [(String, IslandScene, MurzikMood)] =
            (0..<8).map { ("walk \($0)", IslandScene(pose: .walk, frame: $0), MurzikMood.idle) } + [
                ("stretch", IslandScene(pose: .stretch), .idle),
                ("eat", IslandScene(pose: .eat), .happy),
                ("hop", IslandScene(pose: .hop), .excited),
                ("sit", IslandScene(), .idle),
                ("sleep", IslandScene(), .sleeping),
                ("left", IslandScene(facingLeft: true, pose: .walk, frame: 1), .hungry),
            ]
        let view = VStack(spacing: 16) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(110), spacing: 12), count: 7), spacing: 12) {
                ForEach(Array(poses.enumerated()), id: \.offset) { _, p in
                    VStack(spacing: 6) {
                        IslandCatPose(scene: p.1, mood: p.2, size: 96)
                        Text(p.0).font(.caption.bold()).foregroundStyle(.white)
                    }
                }
            }
            // Actual island sizes on black.
            HStack(spacing: 14) {
                ForEach(Array(poses.enumerated()), id: \.offset) { _, p in
                    IslandCatPose(scene: p.1, mood: p.2, size: 32)
                }
            }
            .padding(10)
            .background(Capsule().fill(Color.black))
        }
        .padding(24)
        .background(Color(white: 0.18))
        try save(view, name: "island-pose-sheet", scale: 2)
    }
}
