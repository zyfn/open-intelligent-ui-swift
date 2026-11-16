import XCTest
@testable import SwiftLang

final class MergeBudgetTests: XCTestCase {
    func testRawArgumentsRejectBeforeWhitespaceCanMakeTheProgramSmall() {
        let oversized = String(repeating: " ", count: OpenUIRuntimeBudget.maximumSourceUTF16 + 1)
        for (existing, patch, rootId) in [
            ("root=Box(\"before\")", oversized + "root=Box(\"after\")", "root"),
            (oversized + "root=Box(\"before\")", "root=Box(\"after\")", "root"),
            ("root=Box(\"before\")", "root=Box(\"after\")", oversized),
        ] {
            XCTAssertThrowsError(try mergeStatements(existing, patch, rootId: rootId)) { error in
                XCTAssertEqual(error as? MergeStatementsError, .budgetExceeded)
            }
        }
    }

    func testRawArgumentLimitsCountUTF16InsteadOfCharacters() {
        let oversized = String(repeating: "😀", count: OpenUIRuntimeBudget.maximumSourceUTF16 / 2 + 1)
        XCTAssertLessThan(oversized.count, OpenUIRuntimeBudget.maximumSourceUTF16)
        XCTAssertThrowsError(try mergeStatements("root=Box(\"before\")", oversized)) { error in
            XCTAssertEqual(error as? MergeStatementsError, .budgetExceeded)
        }
    }

    func testExactSourceLimitAndIndependentInputCapsAllowValidReplacement() throws {
        let patch = "root=Box(\"after\")"
        let padded = String(repeating: " ", count: OpenUIRuntimeBudget.maximumSourceUTF16 - patch.utf16.count) + patch
        XCTAssertEqual(padded.utf16.count, OpenUIRuntimeBudget.maximumSourceUTF16)
        XCTAssertEqual(try mergeStatements("root=Box(\"before\")", padded), patch)

        let existing = "root=Box(\"" + String(repeating: "a", count: 600_000) + "\")"
        let replacement = "root=Box(\"" + String(repeating: "b", count: 600_000) + "\")"
        XCTAssertGreaterThan(existing.utf16.count + replacement.utf16.count,
                             OpenUIRuntimeBudget.maximumSourceUTF16)
        XCTAssertEqual(try mergeStatements(existing, replacement), replacement,
                       "Each raw source has its own cap; cumulative merge work is counted separately")
    }

    func testCumulativeDeletionWorkDoesNotReturnAPartialProgram() throws {
        let declarations = (0..<1_000).map { "$v\($0)=0" }
        let deletions = (0..<1_000).map { "$v\($0)=null" }
        let existing = (["root=Box(\"before\")"] + declarations).joined(separator: "\n")
        let patch = (["root=Box(\"after\")"] + deletions).joined(separator: "\n")
        XCTAssertTrue(OpenUIRuntimeBudget.acceptsSource(existing))
        XCTAssertTrue(OpenUIRuntimeBudget.acceptsSource(patch))
        XCTAssertThrowsError(try mergeStatements(existing, patch)) { error in
            XCTAssertEqual(error as? MergeStatementsError, .budgetExceeded)
        }
        XCTAssertEqual(try mergeStatements("root=Box(\"before\")", "root=Box(\"recovered\")"),
                       "root=Box(\"recovered\")", "A failed operation cannot poison the next merge allowance")
    }

    func testCustomRootStillUsesTheSameStatementMerge() throws {
        let merged = try mergeStatements("unused=1\nvalue=\"old\"\nscreen=Box(value)",
                                         "value=\"new\"", rootId: "screen")
        XCTAssertEqual(merged, "value=\"new\"\nscreen=Box(value)")
    }
}
