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

    private func launchFed(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
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
        pause(1)
    }

    /// Leaving the app: Murzik stretches, walks across the island through the camera area and sits.
    /// Leaving again: he walks back. (A screenshot takes ~1–3 s in CI, so frames are back to back.)
    func test1WalkAcrossTheIslandWhenLeavingTheApp() throws {
        continueAfterFailure = true
        let app = launchFed()

        XCUIDevice.shared.press(.home)
        film("walk", count: 8, every: 0)
        pause(3)
        capture("walk-settled", fraction: 0.075)

        app.activate()
        XCTAssertTrue(app.buttons["action.feed"].waitForExistence(timeout: 10))
        pause(2)
        XCUIDevice.shared.press(.home)
        film("walkback", count: 8, every: 0)
        pause(3)
        capture("walkback-settled", fraction: 0.075)
    }

    /// Real-time experiment: the paw-print trail is a `ProgressView(timerInterval:)` mask. With a
    /// 75 s debug interval, shots a few seconds apart must differ without any content update.
    func test2RealTimePawTrail() throws {
        continueAfterFailure = true
        _ = launchFed(["-uitest-fast-trail"])
        XCUIDevice.shared.press(.home)
        pause(14)
        expandIsland()
        capture("trail-a", fraction: 0.3)
        pause(5)
        capture("trail-b", fraction: 0.3)
        pause(5)
        capture("trail-c", fraction: 0.3)
    }

    /// The island buttons' intents (run by the app after the leaving walk, exactly as a tap would):
    /// Feed → he walks to the bowl, eats and hops; Pet → he walks to the cushion with hearts.
    func test3FeedIntentWalksToTheBowl() throws {
        continueAfterFailure = true
        _ = launchFed(["-uitest-intent-after-walk", "feed"])
        XCUIDevice.shared.press(.home)
        film("intent-feed", count: 14, every: 0)
        pause(3)
        capture("intent-feed-settled", fraction: 0.075)
        expandIsland()
        capture("intent-feed-expanded", fraction: 0.3)
    }

    func test4PetIntentWalksToTheCushion() throws {
        continueAfterFailure = true
        _ = launchFed(["-uitest-intent-after-walk", "pet"])
        XCUIDevice.shared.press(.home)
        film("intent-pet", count: 14, every: 0)
        pause(3)
        capture("intent-pet-settled", fraction: 0.075)
    }

    /// Real taps on the expanded island's buttons (may not reach the intent in the simulator).
    func test5TapExpandedIslandButtons() throws {
        continueAfterFailure = true
        _ = launchFed()
        XCUIDevice.shared.press(.home)
        pause(14)
        expandIsland()
        capture("expanded", fraction: 0.3)
        let pet = springboard.buttons["ליטוף"].firstMatch
        if pet.waitForExistence(timeout: 3) {
            pet.tap()
            film("tap-pet", count: 5, every: 0, fraction: 0.3)
        } else {
            XCTContext.runActivity(named: "Expanded island Pet button not reachable") { _ in }
        }
        // Give any running intent time to finish before the next test relaunches the app.
        pause(15)
        capture("tap-pet-settled", fraction: 0.3)
    }
}
