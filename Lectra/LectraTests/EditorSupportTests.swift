import SwiftUI
import UIKit
import XCTest
@testable import Lectra

final class EditorSupportTests: XCTestCase {
    func testAccentTokensStayInSync() {
        assertColorsMatch(UIColor(LectraColor.accent), LectraColor.accentUIColor)
        assertColorsMatch(AnnotationInkColor.accent.inkUIColor, LectraColor.accentUIColor)
    }

    func testLassoTranslationAndDuplicationOffsetPointGroups() {
        let points = [CGPoint(x: 10, y: 12), CGPoint(x: 18, y: 22)]
        let translated = LassoGeometry.translated(points: points, by: CGSize(width: 5, height: -2))

        XCTAssertEqual(translated, [CGPoint(x: 15, y: 10), CGPoint(x: 23, y: 20)])

        let duplicated = LassoGeometry.duplicated(pointGroups: [points])
        XCTAssertEqual(duplicated.first, [CGPoint(x: 34, y: 36), CGPoint(x: 42, y: 46)])
    }

    func testLassoResizePreservesAspectRatioAndMinimumSize() {
        let original = CGRect(x: 20, y: 20, width: 100, height: 50)
        let resized = LassoGeometry.proportionalResizeRect(
            from: original,
            handle: .bottomRight,
            location: CGPoint(x: 200, y: 120)
        )

        XCTAssertEqual(resized.width / resized.height, 2.0, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(resized.width, 100)
        XCTAssertGreaterThanOrEqual(resized.height, 50)
    }

    func testLassoDeletionRemovesSelectedIndexes() {
        let values = ["a", "b", "c", "d", "e"]
        let remaining = LassoGeometry.removing(items: values, at: [1, 3])

        XCTAssertEqual(remaining, ["a", "c", "e"])
    }

    func testBlankPageUndoGuardRejectsTouchedOrNonTerminalPages() {
        XCTAssertTrue(
            AutoAppendedBlankPageUndoGuard.canUndo(
                candidateIndex: 4,
                totalPageCount: 5,
                isTerminalBlankPage: true,
                isPageEmpty: true,
                hasHistory: false
            )
        )

        XCTAssertFalse(
            AutoAppendedBlankPageUndoGuard.canUndo(
                candidateIndex: 3,
                totalPageCount: 5,
                isTerminalBlankPage: true,
                isPageEmpty: true,
                hasHistory: false
            )
        )

        XCTAssertFalse(
            AutoAppendedBlankPageUndoGuard.canUndo(
                candidateIndex: 4,
                totalPageCount: 5,
                isTerminalBlankPage: true,
                isPageEmpty: false,
                hasHistory: false
            )
        )

        XCTAssertFalse(
            AutoAppendedBlankPageUndoGuard.canUndo(
                candidateIndex: 4,
                totalPageCount: 5,
                isTerminalBlankPage: true,
                isPageEmpty: true,
                hasHistory: true
            )
        )
    }

    private func assertColorsMatch(_ lhs: UIColor, _ rhs: UIColor, file: StaticString = #filePath, line: UInt = #line) {
        let lhsComponents = rgbaComponents(for: lhs)
        let rhsComponents = rgbaComponents(for: rhs)

        XCTAssertEqual(lhsComponents.red, rhsComponents.red, accuracy: 0.005, file: file, line: line)
        XCTAssertEqual(lhsComponents.green, rhsComponents.green, accuracy: 0.005, file: file, line: line)
        XCTAssertEqual(lhsComponents.blue, rhsComponents.blue, accuracy: 0.005, file: file, line: line)
        XCTAssertEqual(lhsComponents.alpha, rhsComponents.alpha, accuracy: 0.005, file: file, line: line)
    }

    private func rgbaComponents(for color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return (red, green, blue, alpha)
    }
}
