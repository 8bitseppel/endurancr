import XCTest

/// Sets a goal through the goal form the way a runner would: a marathon on
/// 25 Apr 2027, a 4:30:00 target, and a 12.2 km run at 5:36/km picked from
/// Health (the demo Health holds only that run). Saves screenshots of the result.
final class PlanFromRecentRunUITests: XCTestCase {
    private func save(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? FileManager.default.createDirectory(atPath: "/tmp/plan-4-30", withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: "/tmp/plan-4-30/\(name).png"))
    }

    private func first(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    @MainActor
    func testMarathonAt430FromRecentRun() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoScreen", "welcome", "-demoRecentRun", "12200,4099"]
        app.launch()

        let setGoal = app.buttons["Set your goal"]
        XCTAssertTrue(setGoal.waitForExistence(timeout: 10))
        setGoal.tap()

        let name = app.textFields["Goal name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Hamburg Marathon\n")

        // Race day: the default is six months out (March 2027); move to 25 April.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Race day'")).firstMatch.tap()
        let nextMonth = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'next month' OR identifier CONTAINS[c] 'next'")).firstMatch
        if !nextMonth.waitForExistence(timeout: 5) { save("x-no-next"); print(app.debugDescription) }
        for _ in 0..<12 where !first(app, containing: "April 2027").exists { nextMonth.tap(); sleep(1) }
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "25", "April")).firstMatch.tap()
        sleep(1)

        let target = app.switches["Set a target time"]
        scrollTo(target, in: app)
        target.switches.firstMatch.tap()
        for (current, wanted) in [("0h", "4h"), ("00m", "30m")] {
            let menu = app.buttons.matching(NSPredicate(format: "label == %@ OR label ENDSWITH %@ OR value == %@", current, ", " + current, current)).firstMatch
            scrollTo(menu, in: app)
            if !menu.exists { save("x-no-\(current)"); print(app.debugDescription) }
            sleep(1)
            menu.tap()
            sleep(1)
            save("x-open-\(current)")
            let option = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", wanted)).firstMatch
            _ = option.waitForExistence(timeout: 3)
            for _ in 0..<8 where !(option.exists && option.isHittable) {
                let window = app.windows.firstMatch
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.8))
                    .press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)))
                sleep(1)
            }
            if !option.exists { save("x-no-\(wanted)"); print(app.debugDescription) }
            option.tap()
        }

        let fromHealth = app.buttons["Use a recent run from Health"]
        scrollTo(fromHealth, in: app)
        fromHealth.tap()
        let run = first(app, containing: "12.2")
        XCTAssertTrue(run.waitForExistence(timeout: 10), "the 12.2 km run in Health")
        save("0-recent-runs")
        run.tap()
        sleep(1)
        app.swipeDown()
        save("1-goal-form")

        app.buttons["Save"].tap()
        sleep(3)
        save("2-today")

        for (tab, file) in [("Plan", "3-plan"), ("Progress", "4-progress")] {
            let button = app.tabBars.buttons[tab]
            if button.waitForExistence(timeout: 5) { button.tap() }
            sleep(2)
            save(file)
            for i in 1...3 { app.swipeUp(); sleep(1); save("\(file)-\(i)") }
        }
    }
}
