import XCTest

/// The goal form's small flows: the keyboard gets out of the way of the calendar,
/// and picking today (already selected) as the start still moves on to race day.
final class GoalFormUITests: XCTestCase {
    @MainActor
    func testStartTodayMovesOnToRaceDay() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoScreen", "welcome"]
        app.launch()

        let setGoal = app.buttons["Set your goal"]
        XCTAssertTrue(setGoal.waitForExistence(timeout: 10))
        setGoal.tap()

        let name = app.textFields["Goal name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Hamburg")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "the keyboard is up")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Start training'")).firstMatch.tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        wait(for: [gone], timeout: 3)

        // Today is already selected; tapping it again moves on to race day.
        let today = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Today'")).firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 3), "the start calendar shows today")
        today.tap()
        let raceCalendarOpen = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: today)
        wait(for: [raceCalendarOpen], timeout: 3)
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 3), "the race day calendar is open")
    }
}
