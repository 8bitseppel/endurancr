import XCTest

/// Drives the plan screen's drag-to-swap with a real long press and drag in the
/// Simulator, using the demo plan.
final class PlanDragUITests: XCTestCase {
    private func day(_ offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: .now)!
        return date.formatted(.dateTime.weekday(.abbreviated).day().month())
    }

    private func element(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
            .firstMatch
    }

    private func save(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? FileManager.default.createDirectory(atPath: "/tmp/drag", withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: "/tmp/drag/\(name).png"))
    }

    @MainActor
    func testDragSwapsTwoDays() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demoScreen", "plan"]
        app.launch()

        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 10)
        // Scroll until tomorrow and two days later are both on screen.
        let window = app.windows.firstMatch
        // Slow swipes: a fast one can fling the rows past the screen, and rows
        // off screen aren't in the list at all.
        for _ in 0..<30 {
            let t = element(app, startingWith: day(3))
            if t.exists, t.isHittable, t.frame.maxY < window.frame.maxY - 200 { break }
            app.swipeUp(velocity: .slow)
        }
        let fromRow = element(app, startingWith: day(4))
        // A nearby day with a different session, so the swap shows (two identical
        // easy runs would look the same swapped).
        func content(_ e: XCUIElement) -> String { e.label.components(separatedBy: ", ").dropFirst().joined(separator: ", ") }
        let toOffset = [3, 5, 2, 6].first { element(app, startingWith: day($0)).exists
            && content(element(app, startingWith: day($0))) != content(fromRow) } ?? 3
        let toRow = element(app, startingWith: day(toOffset))
        XCTAssertTrue(toRow.waitForExistence(timeout: 5), "a nearby row with a different session")
        let before = (fromRow.label, toRow.label)
        save("1-before")

        fromRow.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(forDuration: 0.8,
                   thenDragTo: toRow.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)),
                   withVelocity: .slow,
                   thenHoldForDuration: 0.6)
        sleep(1)
        save("2-after")

        let after = (element(app, startingWith: day(4)).label, element(app, startingWith: day(toOffset)).label)
        print("DRAG before: \(before)\nDRAG after: \(after)")
        XCTAssertNotEqual(before.0, after.0, "the dragged day changed")
    }
}
