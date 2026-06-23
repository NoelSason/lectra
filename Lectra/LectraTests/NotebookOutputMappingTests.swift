import XCTest
@testable import Lectra

/// Covers the cell-output value type and the matplotlib image plumbing: how a
/// raw `PyodideRunResult` becomes a `CellOutput`, and how inline figures survive
/// the trip through the `.ipynb` `display_data` / `image/png` representation.
final class NotebookOutputMappingTests: XCTestCase {

    // MARK: PyodideRunResult → CellOutput

    func testRunResultDefaultsToNoImages() {
        let result = PyodideRunResult(stdout: "", stderr: "", result: nil, error: nil)
        XCTAssertTrue(result.images.isEmpty)
    }

    func testCellOutputCopiesAllChannelsFromRunResult() {
        let result = PyodideRunResult(stdout: "out",
                                      stderr: "err",
                                      result: "42",
                                      error: "boom",
                                      images: ["A", "B"])
        let output = CellOutput(result)
        XCTAssertEqual(output.stdout, "out")
        XCTAssertEqual(output.stderr, "err")
        XCTAssertEqual(output.result, "42")
        XCTAssertEqual(output.error, "boom")
        XCTAssertEqual(output.images, ["A", "B"])
    }

    // MARK: CellOutput.isEmpty

    func testIsEmptyForFullyBlankOutput() {
        XCTAssertTrue(CellOutput().isEmpty)
    }

    func testIsNotEmptyWhenOnlyImagesPresent() {
        XCTAssertFalse(CellOutput(images: ["QUJD"]).isEmpty)
    }

    func testIsNotEmptyWhenOnlyStdoutPresent() {
        XCTAssertFalse(CellOutput(stdout: "x").isEmpty)
    }

    func testIsNotEmptyWhenOnlyResultPresent() {
        XCTAssertFalse(CellOutput(result: "1").isEmpty)
    }

    func testEmptyStringResultIsStillEmpty() {
        XCTAssertTrue(CellOutput(result: "").isEmpty)
    }

    // MARK: image/png round-trip through the document

    @MainActor
    func testSingleFigureSurvivesIpynbRoundTrip() throws {
        let cell = NotebookCell(type: .code, source: "plt.plot([1,2,3])")
        cell.output = CellOutput(images: ["iVBORw0KGgo="])
        let doc = NotebookDocument(title: "fig", cells: [cell])

        let restored = NotebookDocument(jupyter: try JupyterNotebook(data: doc.toJupyter().encodeIPYNB()))
        XCTAssertEqual(restored.cells.first?.output?.images, ["iVBORw0KGgo="])
    }

    @MainActor
    func testMultipleFiguresPreserveOrder() throws {
        let cell = NotebookCell(type: .code, source: "code")
        cell.output = CellOutput(images: ["one", "two", "three"])
        let doc = NotebookDocument(title: "figs", cells: [cell])

        let restored = NotebookDocument(jupyter: try JupyterNotebook(data: doc.toJupyter().encodeIPYNB()))
        XCTAssertEqual(restored.cells.first?.output?.images, ["one", "two", "three"])
    }

    @MainActor
    func testFigureCoexistsWithStdout() throws {
        let cell = NotebookCell(type: .code, source: "code")
        cell.output = CellOutput(stdout: "drawing\n", images: ["QUJD"])
        let doc = NotebookDocument(title: "mix", cells: [cell])

        let outputs = doc.toJupyter().cells.first?.outputs ?? []
        XCTAssertTrue(outputs.contains { $0.output_type == "stream" && $0.name == "stdout" })
        XCTAssertTrue(outputs.contains { $0.output_type == "display_data" && $0.data?.imagePng == "QUJD" })
    }

    @MainActor
    func testBlankImageEntriesAreNotEmitted() {
        let cell = NotebookCell(type: .code, source: "code")
        cell.output = CellOutput(images: ["", "valid"])
        let doc = NotebookDocument(title: "t", cells: [cell])
        let displayData = (doc.toJupyter().cells.first?.outputs ?? [])
            .filter { $0.output_type == "display_data" }
        XCTAssertEqual(displayData.count, 1)
        XCTAssertEqual(displayData.first?.data?.imagePng, "valid")
    }
}
