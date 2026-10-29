import SwiftUI
import XCTest
@testable import Murzik

/// Renders the room in every part of the day and the moment cards, for design review.
@MainActor
final class ExperienceRenderTests: XCTestCase {
    private var outputDir: URL {
        let path = ProcessInfo.processInfo.environment["RENDER_DIR"]
        let url = (path.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("murzik-renders"))
            .appendingPathComponent("experience")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func save<V: View>(_ view: V, name: String, scale: CGFloat = 2) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.uiImage, "render failed: \(name)")
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: outputDir.appendingPathComponent("\(name).png"))
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func room(_ phase: DayPhase) -> some View {
        let size = CGSize(width: 440, height: 956)
        let stage = CGRect(x: 0, y: 130, width: 440, height: 500)
        let theme = RoomTheme.for(phase)
        return ZStack(alignment: .topLeading) {
            RoomBackdrop(phase: phase, stageFrame: stage, animated: false)
            CatFigure(mood: phase == .night ? .sleepy : .happy)
                .frame(width: 270, height: 360)
                .position(x: stage.midX, y: stage.maxY - 180 - 24)
            Text(Strings.phaseTitle(phase))
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(theme.ink)
                .position(x: 220, y: 90)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    func testRenderRoomPhases() throws {
        // One image per phase: the backdrop positions things in global coordinates, so render each alone.
        for phase in DayPhase.allCases {
            try save(room(phase), name: "room-\(phase.rawValue)", scale: 1)
        }
    }

    func testRenderMomentCards() throws {
        let cards = VStack(spacing: 16) {
            MomentCard(symbol: Strings.greetingSymbol(.missedYou(hours: 9)), tint: MurzikPalette.heart,
                       title: Strings.greetingTitle(.missedYou(hours: 9)), subtitle: Strings.greetingSubtitle(.missedYou(hours: 9))) {
                EmptyView()
            }
            MomentCard(symbol: Gift.flower.symbolName, tint: MurzikPalette.mint,
                       title: Strings.giftTitle, subtitle: Strings.giftName(.flower)) {
                Text(Strings.thanks)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(MurzikPalette.heart.gradient))
                    .padding(.top, 6)
            }
            MomentCard(symbol: "heart.text.square.fill", tint: MurzikPalette.heart,
                       title: Strings.surpriseTitle, subtitle: Strings.surpriseMessage(3)) {
                EmptyView()
            }
            HStack(spacing: 20) {
                FeatherToy().frame(width: 40, height: 84)
                SpeechBubble(text: Strings.purring, symbol: "heart.fill", tint: MurzikPalette.heart)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(MurzikPalette.cream)
        .environment(\.layoutDirection, .rightToLeft)
        try save(cards, name: "moment-cards")
    }
}
