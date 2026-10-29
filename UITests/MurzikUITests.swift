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
        // Hungry, and away for 9 hours: he greets her ("I missed you").
        app.launchArguments = ["-uitest-hungry", "-uitest-missed"]
        app.launch()

        let feed = app.buttons["action.feed"]
        XCTAssertTrue(feed.waitForExistence(timeout: 15), "Feed button not found")
        let greeting = app.descendants(matching: .any)["moment.greeting"]
        XCTAssertTrue(greeting.waitForExistence(timeout: 5), "Greeting not shown")
        sleep(1)
        snapshot("0-greeting")
        // The greeting goes away by itself.
        sleep(7)
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

        // Wake him up and play: toy mode with the feather, then the laser.
        app.activate()
        XCTAssertTrue(app.buttons["action.wake"].waitForExistence(timeout: 10))
        app.buttons["action.wake"].tap()
        XCTAssertTrue(app.buttons["action.play"].waitForExistence(timeout: 5))
        app.buttons["action.play"].tap()
        let toyDone = app.buttons["toy.done"]
        XCTAssertTrue(toyDone.waitForExistence(timeout: 5), "Toy mode did not open")
        drag(app, from: CGVector(dx: 0.78, dy: 0.25), to: CGVector(dx: 0.3, dy: 0.3))
        sleep(1)
        snapshot("10-toy-feather")
        app.buttons["toy.laser"].tap()
        drag(app, from: CGVector(dx: 0.3, dy: 0.3), to: CGVector(dx: 0.58, dy: 0.47))
        snapshot("11-toy-laser")
        toyDone.tap()
        XCTAssertTrue(app.buttons["action.pet"].waitForExistence(timeout: 5))

        // Settings sheet.
        app.buttons["settings.open"].tap()
        let settingsDone = app.buttons["settings.done"]
        XCTAssertTrue(settingsDone.waitForExistence(timeout: 5), "Settings did not open")
        XCTAssertTrue(app.switches["settings.walker"].exists)
        XCTAssertTrue(app.switches["settings.island"].exists)
        sleep(1)
        snapshot("12-settings")
        app.swipeUp()
        sleep(1)
        snapshot("13-settings-us")
        if !settingsDone.isHittable { app.swipeDown() }
        if settingsDone.waitForExistence(timeout: 2), settingsDone.isHittable { settingsDone.tap() }
        XCTAssertTrue(app.buttons["action.feed"].waitForExistence(timeout: 5))
        sleep(2)
        snapshot("14-main")

        // The room at night.
        app.terminate()
        app.launchArguments = ["-uitest-phase", "night", "-uitest-gift"]
        app.launch()
        XCTAssertTrue(app.buttons["action.feed"].waitForExistence(timeout: 15))
        sleep(3)
        snapshot("15-main-night")

        // A surprise: he brings her a gift (forced ~9 s after launch).
        let surprise = app.descendants(matching: .any)["moment.surprise"]
        XCTAssertTrue(surprise.waitForExistence(timeout: 12), "Gift surprise not shown")
        sleep(1)
        snapshot("16-surprise-gift")
        app.buttons["surprise.thanks"].firstMatch.tap()
    }

    private func drag(_ app: XCUIApplication, from: CGVector, to: CGVector) {
        let start = app.coordinate(withNormalizedOffset: from)
        let end = app.coordinate(withNormalizedOffset: to)
        start.press(forDuration: 0.15, thenDragTo: end)
    }
}
