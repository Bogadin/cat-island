import XCTest

/// Runs the real app in the iOS Simulator and captures screenshots of the app and of the
/// home screen with the Live Activity in the Dynamic Island.
@MainActor
final class MurzikUITests: XCTestCase {
    private var outputDir: URL? {
        guard let path = ProcessInfo.processInfo.environment["RENDER_DIR"] else { return nil }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func snapshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = outputDir {
            try? shot.pngRepresentation.write(to: dir.appendingPathComponent("sim-\(name).png"))
        }
    }

    private func goHome(wait seconds: UInt32) {
        XCUIDevice.shared.press(.home)
        sleep(seconds)
    }

    func testAppAndDynamicIsland() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-hungry"]
        app.launch()

        let feed = app.buttons["action.feed"]
        XCTAssertTrue(feed.waitForExistence(timeout: 15), "Feed button not found")
        XCTAssertTrue(app.buttons["action.pet"].exists)
        XCTAssertTrue(app.buttons["action.play"].exists)
        XCTAssertTrue(app.buttons["action.sleep"].exists)
        sleep(3)
        snapshot("1-app-hungry")

        // Home screen: the Live Activity shows a hungry Murzik in the Dynamic Island.
        goHome(wait: 5)
        snapshot("2-island-hungry")

        // Feed him: the island shows the excited reaction…
        app.activate()
        XCTAssertTrue(feed.waitForExistence(timeout: 10))
        feed.tap()
        sleep(1)
        goHome(wait: 2)
        snapshot("3-island-fed-excited")

        // …then settles back to his base mood once the reaction is over.
        sleep(8)
        snapshot("4-island-settled")

        // Long-press the island to expand it, then use its Pet button (runs the LiveActivityIntent).
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).press(forDuration: 1.2)
        sleep(2)
        snapshot("5-island-expanded")
        let islandPet = springboard.buttons["ליטוף"].firstMatch
        if islandPet.waitForExistence(timeout: 3) {
            islandPet.tap()
            sleep(2)
            snapshot("6-island-expanded-after-pet")
        } else {
            XCTContext.runActivity(named: "Expanded island Pet button not reachable from UI test") { _ in }
        }
        goHome(wait: 1)

        // Pet him in the app: hearts in the island.
        app.activate()
        XCTAssertTrue(app.buttons["action.pet"].waitForExistence(timeout: 10))
        app.buttons["action.pet"].tap()
        snapshot("7-app-after-pet")
        sleep(1)
        goHome(wait: 2)
        snapshot("8-island-loving")

        // Put him to sleep.
        app.activate()
        XCTAssertTrue(app.buttons["action.sleep"].waitForExistence(timeout: 10))
        app.buttons["action.sleep"].tap()
        XCTAssertTrue(app.buttons["action.wake"].waitForExistence(timeout: 5))
        goHome(wait: 3)
        snapshot("9-island-sleeping")
    }
}
