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
        app.launch()

        let pet = app.buttons["action.pet"]
        XCTAssertTrue(pet.waitForExistence(timeout: 15), "Pet button not found")
        XCTAssertTrue(app.buttons["action.feed"].exists)
        XCTAssertTrue(app.buttons["action.play"].exists)
        sleep(2)
        snapshot("1-app")

        pet.tap()
        sleep(1)
        snapshot("2-app-after-pet")

        // Leave the app: the Live Activity should now be in the Dynamic Island.
        XCUIDevice.shared.press(.home)
        sleep(3)
        snapshot("3-home-island")

        // Back in the app, feed him; the island should follow.
        app.activate()
        XCTAssertTrue(app.buttons["action.feed"].waitForExistence(timeout: 10))
        app.buttons["action.feed"].tap()
        XCUIDevice.shared.press(.home)
        sleep(2)
        snapshot("4-home-island-after-feed")

        // After the reaction window the island settles back to the base mood.
        sleep(8)
        snapshot("5-home-island-settled")
    }
}
