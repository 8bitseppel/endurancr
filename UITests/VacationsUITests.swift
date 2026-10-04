import XCTest

/// Adds two vacations in a row from the goal form. "Add time off" used to open only
/// once, because two `isPresented` destinations shared the form's navigation stack.
final class VacationsUITests: XCTestCase {
    @MainActor
    func testAddsSeveralVacationsInARow() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoScreen", "welcome"]
        app.launch()

        let setGoal = app.buttons["Set your goal"]
        XCTAssertTrue(setGoal.waitForExistence(timeout: 10))
        setGoal.tap()

        let addTimeOff = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Add time off'")).firstMatch
        for count in 1...3 {
            for _ in 0..<12 where !(addTimeOff.exists && addTimeOff.isHittable) { app.swipeUp() }
            addTimeOff.tap()
            let add = app.navigationBars.buttons["Add"]
            XCTAssertTrue(add.waitForExistence(timeout: 5), "Add Time Off opens, time \(count)")
            add.tap()
            sleep(1)
            sleep(1)
            let rows = app.staticTexts.matching(NSPredicate(format: "label == 'Vacation'"))
            XCTAssertEqual(rows.count, count, "\(count) vacations listed")
        }
    }
}
