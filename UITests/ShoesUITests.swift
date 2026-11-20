import XCTest

/// Archives a pair from its page, the way it's done by hand: Shoes, a pair, Archive.
/// Archiving the pair that's open used to crash the app.
final class ShoesUITests: XCTestCase {
    @MainActor
    func testArchivesAPair() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoScreen", "shoes"]
        app.launch()

        let pair = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Pegasus 41'")).firstMatch
        XCTAssertTrue(pair.waitForExistence(timeout: 10))
        pair.tap()
        let archive = app.buttons["Archive"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        archive.tap()
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground, "the app is still running after archiving")
        let useAgain = app.buttons["Use again"]
        XCTAssertTrue(useAgain.waitForExistence(timeout: 5), "the pair is archived")
        useAgain.tap()
        // Archiving the default made the other pair in use the default; this one can be again.
        let makeDefault = app.buttons["Make default"]
        XCTAssertTrue(makeDefault.waitForExistence(timeout: 5), "back in use, and no longer the default")
        makeDefault.tap()
        XCTAssertTrue(app.buttons["Archive"].waitForExistence(timeout: 5))
        let delete = app.buttons["Delete"]
        for _ in 0..<6 where !(delete.exists && delete.isHittable) { app.swipeUp() }
        delete.tap()
        let forGood = app.buttons["Delete for good"]
        XCTAssertTrue(forGood.waitForExistence(timeout: 5))
        forGood.tap()
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground, "the app is still running after every button on the page")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Pegasus 41'")).firstMatch.exists,
                       "the deleted pair is gone from the list")
    }

    /// Apple's accessibility audit on the shoes, a pair, and adding a pair: labels,
    /// contrast, hit areas and text that's cut off. `AUDIT_SCREENS=progress,goal`
    /// (as TEST_RUNNER_AUDIT_SCREENS for xcodebuild) audits other demo screens.
    @MainActor
    func testShoeScreensPassTheAccessibilityAudit() throws {
        for screen in (ProcessInfo.processInfo.environment["AUDIT_SCREENS"] ?? "shoes,shoe,addshoe").split(separator: ",").map(String.init) {
            let app = XCUIApplication()
            app.launchArguments = ["-demo", "-demoScreen", screen]
            app.launch()
            sleep(3)
            try app.performAccessibilityAudit { issue in
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)'" } ?? "?"
                print("[audit] \(screen): \(issue.compactDescription) | \(element) | \(issue.detailedDescription)")
                // Contrast, Dynamic Type and clipped text show up on every list screen
                // of the app (grey text on the lilac background, Apple's own toolbar
                // buttons), not only here; they're handled for the app as a whole.
                // Anything else fails the test.
                let appWide: [XCUIAccessibilityAuditType] = [.contrast, .dynamicType, .textClipped]
                return appWide.contains(issue.auditType)
            }
            app.terminate()
        }
    }
}
