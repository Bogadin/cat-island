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
        sleep(2)
        snapshot("1-app-hungry")

        // Home screen: the Live Activity shows a hungry Murzik in the Dynamic Island.
        XCUIDevice.shared.press(.home)
        sleep(2)
        snapshot("2-island-hungry")

        // Feed him, leave immediately: the island shows the excited reaction…
        app.activate()
        XCTAssertTrue(feed.waitForExistence(timeout: 10))
        feed.tap()
        XCUIDevice.shared.press(.home)
        sleep(1)
        snapshot("3-island-fed-excited")

        // …then settles back to his base mood once the reaction is over.
        sleep(8)
        snapshot("4-island-settled")

        // Pet him: hearts in the island.
        app.activate()
        XCTAssertTrue(app.buttons["action.pet"].waitForExistence(timeout: 10))
        app.buttons["action.pet"].tap()
        sleep(1)
        snapshot("5-app-after-pet")
        XCUIDevice.shared.press(.home)
        sleep(1)
        snapshot("6-island-loving")

        // Put him to sleep.
        app.activate()
        XCTAssertTrue(app.buttons["action.sleep"].waitForExistence(timeout: 10))
        app.buttons["action.sleep"].tap()
        XCTAssertTrue(app.buttons["action.wake"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        sleep(2)
        snapshot("7-island-sleeping")
    }
}
