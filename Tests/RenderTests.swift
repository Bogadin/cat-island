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

    func testRenderDynamicIslandPresentations() throws {
        let moods: [MurzikMood] = [.idle, .happy, .hungry, .sleeping, .loving]
        let view = VStack(spacing: 22) {
            ForEach(moods, id: \.self) { mood in
                HStack(spacing: 28) {
                    // Compact: leading + camera gap + trailing (62.33 + 126 + 62.33 on a 15 Pro Max)
                    HStack(spacing: 0) {
                        CompactLeadingView(mood: mood).frame(width: 62, alignment: .leading)
                        Spacer().frame(width: 126)
                        CompactTrailingView(mood: mood).frame(width: 62, alignment: .trailing)
                    }
                    .frame(height: 37)
                    .background(Capsule().fill(Color.black))

                    MinimalView(mood: mood)
                        .frame(width: 37, height: 37)
                        .background(Circle().fill(Color.black))
                }
            }
        }
        .padding(30)
        .background(LinearGradient(colors: [Color(red: 0.55, green: 0.62, blue: 0.85), Color(red: 0.85, green: 0.6, blue: 0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
        try save(view, name: "island-compact-minimal")
    }

    func testRenderExpandedIsland() throws {
        let views = VStack(spacing: 20) {
            ForEach([MurzikMood.loving, .hungry, .playful], id: \.self) { mood in
                let state = content(for: mood)
                VStack(spacing: 6) {
                    HStack(alignment: .top) {
                        ExpandedLeadingView(mood: mood)
                        Spacer()
                        ExpandedCenterView(name: Strings.name, mood: mood)
                        Spacer()
                        ExpandedTrailingView(mood: mood)
                    }
                    ExpandedBottomView(state: state, isStale: false)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(width: 408)
                .background(RoundedRectangle(cornerRadius: 44, style: .continuous).fill(Color.black))
            }
        }
        .padding(24)
        .background(Color(white: 0.85))
        try save(views, name: "island-expanded")
    }

    func testRenderLockScreen() throws {
        let views = VStack(spacing: 16) {
            LockScreenView(name: Strings.name, state: content(for: .happy), isStale: false)
                .frame(width: 408)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.82)))
            LockScreenView(name: Strings.name, state: content(for: .idle), isStale: true)
                .frame(width: 408)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.82)))
        }
        .padding(24)
        .background(LinearGradient(colors: [Color(red: 0.2, green: 0.25, blue: 0.45), Color(red: 0.55, green: 0.35, blue: 0.5)], startPoint: .top, endPoint: .bottom))
        try save(views, name: "lock-screen")
    }
}
