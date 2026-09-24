import Foundation

/// Minimal assertion harness — a stand-in for XCTest/Swift Testing, which aren't
/// available with the standalone Command Line Tools. Tracks pass/fail counts and
/// drives the process exit code.
final class CheckHarness {
    private(set) var checks = 0
    private(set) var failures = 0
    private var currentSuite = ""

    func suite(_ name: String, _ body: () throws -> Void) {
        currentSuite = name
        print("▸ \(name)")
        do {
            try body()
        } catch {
            failures += 1
            print("  ✗ threw error: \(error)")
        }
    }

    func check(_ condition: Bool, _ message: String, line: UInt = #line) {
        checks += 1
        if condition {
            print("  ✓ \(message)")
        } else {
            failures += 1
            print("  ✗ \(message)  (line \(line))")
        }
    }

    func approx(_ a: Double, _ b: Double, tolerance: Double, _ message: String, line: UInt = #line) {
        check(abs(a - b) <= tolerance, "\(message)  [\(a) ≈ \(b) ± \(tolerance)]", line: line)
    }

    func finish() -> Never {
        print("\n\(checks - failures)/\(checks) checks passed.")
        if failures == 0 {
            print("✅ All TrainingCore checks passed.")
            exit(0)
        } else {
            print("❌ \(failures) check(s) failed.")
            exit(1)
        }
    }
}

/// Thrown by `require` when an expected value is missing.
struct RequireError: Error { let message: String }

func require<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else { throw RequireError(message: "required value missing: \(message)") }
    return value
}
