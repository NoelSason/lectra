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

    func testCanvasStrokeEraserRemovesIntersectingStroke() {
        let canvas = VectorInkCanvasView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        canvas.setDrawing(
            InkPageDrawing(
                strokes: [
                    makeStroke(from: CGPoint(x: 0.20, y: 0.20), to: CGPoint(x: 0.40, y: 0.40)),
                    makeStroke(from: CGPoint(x: 0.75, y: 0.75), to: CGPoint(x: 0.90, y: 0.90)),
                ]
            )
        )

        var emittedDrawing: InkPageDrawing?
        canvas.onDrawingChanged = { emittedDrawing = $0 }

        canvas.testingErase(at: CGPoint(x: 50, y: 50), width: 6)

        XCTAssertEqual(canvas.currentDrawing().strokes.count, 1)
        XCTAssertEqual(canvas.currentDrawing().strokes.first?.points.first?.x, 0.75)
        XCTAssertEqual(emittedDrawing?.strokes.count, 1)
    }

    func testCanvasLassoSelectionCanDuplicateAndDeleteSelectedStroke() {
        let canvas = VectorInkCanvasView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        canvas.setDrawing(
            InkPageDrawing(
                strokes: [
                    makeStroke(from: CGPoint(x: 0.22, y: 0.22), to: CGPoint(x: 0.40, y: 0.40)),
                    makeStroke(from: CGPoint(x: 0.75, y: 0.75), to: CGPoint(x: 0.90, y: 0.90)),
                ]
            )
        )

        canvas.testingSelectWithLassoPolygon([
            CGPoint(x: 35, y: 35),
            CGPoint(x: 95, y: 35),
            CGPoint(x: 95, y: 95),
            CGPoint(x: 35, y: 95),
        ])

        XCTAssertTrue(canvas.testingHasActiveSelection)
        XCTAssertTrue(canvas.testingSelectionActionsAreVisible)

        canvas.testingDuplicateSelection()
        XCTAssertEqual(canvas.currentDrawing().strokes.count, 3)
        XCTAssertTrue(canvas.testingHasActiveSelection)

        canvas.testingDeleteSelection()
        XCTAssertEqual(canvas.currentDrawing().strokes.count, 2)
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

    private func makeStroke(from start: CGPoint, to end: CGPoint) -> InkStroke {
        InkStroke(
            points: [
                InkPoint(x: start.x, y: start.y, force: 1.0),
                InkPoint(x: end.x, y: end.y, force: 1.0),
            ],
            width: 1.2,
            color: InkColorComponents(red: 0, green: 0, blue: 0, alpha: 1),
            blendMode: .normal
        )
    }
}
