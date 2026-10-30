import UIKit
import XCTest

/// Runs the app and captures Murzik walking around the Dynamic Island: full screenshots plus
/// crops of the top 250 pt, written to $RENDER_DIR/walker/.
@MainActor
final class IslandWalkerUITests: XCTestCase {
    private var outputDir: URL? {
        guard let path = ProcessInfo.processInfo.environment["RENDER_DIR"] else { return nil }
        let url = URL(fileURLWithPath: path).appendingPathComponent("walker")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Screen width in points (to convert screenshot pixels to points).
    private var pointWidth: CGFloat = 440

    private func snapshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = outputDir else { return }
        try? shot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
        let image = shot.image
        guard let cg = image.cgImage else { return }
        let scale = image.scale > 1 ? image.scale : CGFloat(cg.width) / max(pointWidth, 1)
        let height = min(cg.height, Int(250 * scale))
        if let top = cg.cropping(to: CGRect(x: 0, y: 0, width: cg.width, height: height)),
           let data = UIImage(cgImage: top).pngData() {
            try? data.write(to: dir.appendingPathComponent("\(name)-top.png"))
        }
    }

    private func launch(mood: String, seed: Int = 1, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-walker-mood", mood, "-walker-seed", String(seed)] + extra
        app.launch()
        XCTAssertTrue(app.buttons["action.feed"].waitForExistence(timeout: 15), "App did not start")
        let width = app.windows.firstMatch.frame.width
        if width > 0 { pointWidth = width }
        return app
    }

    /// The opening choreography: drops out of the island, hops onto the ledge, slips in, peeks out.
    func testWalkerShowcase() throws {
        let app = launch(mood: "idle")
        for i in 0..<24 {
            snapshot(String(format: "idle-%02d", i))
            usleep(600_000)
        }
        app.terminate()
    }

    func testWalkerMoods() throws {
        for mood in ["hungry", "playful", "sleeping"] {
            let app = launch(mood: mood, seed: 4)
            sleep(mood == "sleeping" ? 9 : 3)
            for i in 0..<6 {
                snapshot("\(mood)-\(i)")
                usleep(700_000)
            }
            app.terminate()
        }
    }

    /// Tap him (hop + heart) and drag him down the screen (he falls back with a bounce).
    func testWalkerInteraction() throws {
        // Long reaction so the screenshot (taken after XCUITest's idle wait) still shows it.
        let app = launch(mood: "sleeping", seed: 2, extra: ["-walker-reaction-hold", "25"])
        sleep(9)  // walks to the ledge beside the island and curls up
        let cat = app.descendants(matching: .any)["walker.cat"]
        XCTAssertTrue(cat.waitForExistence(timeout: 5), "walker cat not found")
        snapshot("touch-0-sleeping")
        // Tap the lower part of the touch target (below the status bar, which swallows touches).
        let below = cat.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        below.tap()
        snapshot("touch-1-tapped")
        usleep(300_000)
        snapshot("touch-2-tapped")
        sleep(2)
        let start = cat.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let target = app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.32))
        start.press(forDuration: 0.2, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.6)
        snapshot("touch-3-dropped")
        usleep(400_000)
        snapshot("touch-4-falling")
        sleep(2)
        snapshot("touch-5-back")
        // The app's own buttons still work under the overlay.
        app.buttons["action.pet"].tap()
        app.terminate()
    }
}
