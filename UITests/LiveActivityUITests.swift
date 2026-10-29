import UIKit
import XCTest

/// Captures the real Dynamic Island in the simulator over time to prove Murzik's walk sequences
/// (leaving the app, island buttons) and the real-time paw trail. Crops go to $RENDER_DIR/island/.
/// Island updates in the simulator can lag a little, so frames are taken densely over the sequence.
@MainActor
final class LiveActivityUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    private var islandDir: URL? {
        guard let path = ProcessInfo.processInfo.environment["RENDER_DIR"] else { return nil }
        let url = URL(fileURLWithPath: path).appendingPathComponent("island")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Saves the top `fraction` of the screen (where the island is).
    private func capture(_ name: String, fraction: CGFloat) {
        let shot = XCUIScreen.main.screenshot()
        var image = shot.image
        if let cg = image.cgImage {
            let rect = CGRect(x: 0, y: 0, width: cg.width, height: Int(CGFloat(cg.height) * fraction))
            if let cropped = cg.cropping(to: rect) {
                image = UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
            }
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = islandDir, let data = image.pngData() {
            try? data.write(to: dir.appendingPathComponent("\(name).png"))
        }
    }

    private func pause(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Takes `count` compact-island frames about `every` seconds apart.
    private func film(_ prefix: String, count: Int, every: Double, fraction: CGFloat = 0.075) {
        for i in 0..<count {
            capture(String(format: "%@-%02d", prefix, i), fraction: fraction)
            pause(every)
        }
    }

    private func launchFed() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-fast-trail"]
        app.launch()
        let feed = app.buttons["action.feed"]
        XCTAssertTrue(feed.waitForExistence(timeout: 15), "Feed button not found")
        feed.tap()
        // Let the in-app reaction finish so the sequence below starts from a calm cat.
        pause(7)
        return app
    }

    private func expandIsland() {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).press(forDuration: 1.2)
        pause(1.5)
    }

    /// Leaving the app: Murzik stretches, walks across the island through the camera area and sits.
    /// Leaving again: he walks back.
    func testWalkAcrossTheIslandWhenLeavingTheApp() throws {
        continueAfterFailure = true
        let app = launchFed()

        XCUIDevice.shared.press(.home)
        film("walk", count: 12, every: 0.9)
        pause(2)
        capture("walk-settled", fraction: 0.075)

        app.activate()
        XCTAssertTrue(app.buttons["action.feed"].waitForExistence(timeout: 10))
        pause(2)
        XCUIDevice.shared.press(.home)
        film("walkback", count: 12, every: 0.9)
        pause(2)
        capture("walkback-settled", fraction: 0.075)
    }

    /// Expanded island: the stage, the real-time paw trail (two shots seconds apart), and the
    /// Pet / Feed buttons making him walk to the button and react.
    func testExpandedStageTrailAndButtons() throws {
        continueAfterFailure = true
        _ = launchFed()
        XCUIDevice.shared.press(.home)
        // Let the leaving-the-app walk finish.
        pause(12)
        capture("compact-rest", fraction: 0.075)

        expandIsland()
        capture("expanded-trail-a", fraction: 0.32)
        pause(6)
        capture("expanded-trail-b", fraction: 0.32)

        let pet = springboard.buttons["ליטוף"].firstMatch
        if pet.waitForExistence(timeout: 3) {
            pet.tap()
            film("pet", count: 9, every: 0.8, fraction: 0.32)
        } else {
            XCTContext.runActivity(named: "Expanded island Pet button not reachable") { _ in }
        }
        pause(3)

        expandIsland()
        let feed = springboard.buttons["אוכל"].firstMatch
        if feed.waitForExistence(timeout: 3) {
            feed.tap()
            film("feed", count: 9, every: 0.8, fraction: 0.32)
        } else {
            XCTContext.runActivity(named: "Expanded island Feed button not reachable") { _ in }
        }
        pause(3)
        capture("after-buttons", fraction: 0.32)
    }
}
