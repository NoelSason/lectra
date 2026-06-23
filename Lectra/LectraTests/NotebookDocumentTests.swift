import XCTest
@testable import Lectra

/// Covers the live `NotebookDocument` model: cell editing operations, the
/// execution counter, and the bridge to / from the on-disk `.ipynb` format.
@MainActor
final class NotebookDocumentTests: XCTestCase {

    // MARK: Cell insertion

    func testAddCellAppendsWhenAfterIsNil() {
        let doc = NotebookDocument(title: "t", cells: [])
        let cell = doc.addCell(.code, after: nil)
        XCTAssertEqual(doc.cells.count, 1)
        XCTAssertEqual(doc.cells.first?.id, cell.id)
        XCTAssertEqual(cell.type, .code)
        XCTAssertTrue(cell.source.isEmpty)
    }

    func testAddCellInsertsDirectlyAfterReference() {
        let doc = NotebookDocument(title: "t", cells: [])
        let first = doc.addCell(.code, after: nil)
        let second = doc.addCell(.markdown, after: nil)
        let inserted = doc.addCell(.code, after: first)

        XCTAssertEqual(doc.cells.map(\.id), [first.id, inserted.id, second.id])
        XCTAssertEqual(inserted.type, .code)
    }

    // MARK: Deletion & movement

    func testDeleteRemovesMatchingCell() {
        let doc = NotebookDocument(title: "t", cells: [])
        let a = doc.addCell(.code, after: nil)
        let b = doc.addCell(.code, after: a)
        doc.delete(a)
        XCTAssertEqual(doc.cells.map(\.id), [b.id])
    }

    func testMoveSwapsAdjacentCells() {
        let doc = NotebookDocument(title: "t", cells: [])
        let a = doc.addCell(.code, after: nil)
        let b = doc.addCell(.code, after: a)
        doc.move(b, by: -1)
        XCTAssertEqual(doc.cells.map(\.id), [b.id, a.id])
    }

    func testMoveBeyondBoundsIsNoOp() {
        let doc = NotebookDocument(title: "t", cells: [])
        let a = doc.addCell(.code, after: nil)
        let b = doc.addCell(.code, after: a)
        doc.move(a, by: -1)   // already first
        doc.move(b, by: 1)    // already last
        XCTAssertEqual(doc.cells.map(\.id), [a.id, b.id])
    }

    // MARK: Type changes

    func testChangeTypeToMarkdownClearsOutputAndCount() {
        let doc = NotebookDocument(title: "t", cells: [])
        let cell = doc.addCell(.code, after: nil)
        cell.output = CellOutput(stdout: "x")
        cell.executionCount = 5
        doc.changeType(cell, to: .markdown)
        XCTAssertEqual(cell.type, .markdown)
        XCTAssertNil(cell.output)
        XCTAssertNil(cell.executionCount)
    }

    func testChangeTypeToCodeKeepsSource() {
        let doc = NotebookDocument(title: "t", cells: [])
        let cell = doc.addCell(.markdown, after: nil)
        cell.source = "still here"
        doc.changeType(cell, to: .code)
        XCTAssertEqual(cell.type, .code)
        XCTAssertEqual(cell.source, "still here")
    }

    // MARK: Run-and-advance helpers

    func testNextCodeCellSkipsMarkdown() {
        let doc = NotebookDocument(title: "t", cells: [])
        let first = doc.addCell(.code, after: nil)
        let md = doc.addCell(.markdown, after: first)
        let last = doc.addCell(.code, after: md)
        XCTAssertEqual(doc.nextCodeCell(after: first)?.id, last.id)
        XCTAssertNil(doc.nextCodeCell(after: last))
    }

    func testExecutionCounterIncrementsMonotonically() {
        let doc = NotebookDocument(title: "t", cells: [])
        XCTAssertEqual(doc.nextExecutionCount(), 1)
        XCTAssertEqual(doc.nextExecutionCount(), 2)
        XCTAssertEqual(doc.nextExecutionCount(), 3)
    }

    // MARK: toJupyter mapping

    func testToJupyterMarkdownCellHasNoOutputs() {
        let cell = NotebookCell(type: .markdown, source: "# Hi")
        let doc = NotebookDocument(title: "t", cells: [cell])
        let jc = doc.toJupyter().cells.first
        XCTAssertEqual(jc?.cell_type, "markdown")
        XCTAssertNil(jc?.outputs)
    }

    func testToJupyterMapsEveryOutputChannel() {
        let cell = NotebookCell(type: .code, source: "code")
        cell.executionCount = 4
        cell.output = CellOutput(stdout: "out\n",
                                 stderr: "warn\n",
                                 result: "99",
                                 error: "Traceback\nValueError: x",
                                 images: ["QUJD"])
        let doc = NotebookDocument(title: "t", cells: [cell])
        let outputs = doc.toJupyter().cells.first?.outputs ?? []

        XCTAssertEqual(outputs.filter { $0.output_type == "stream" && $0.name == "stdout" }.count, 1)
        XCTAssertEqual(outputs.filter { $0.output_type == "stream" && $0.name == "stderr" }.count, 1)
        XCTAssertEqual(outputs.filter { $0.output_type == "execute_result" }.count, 1)
        XCTAssertEqual(outputs.filter { $0.output_type == "display_data" }.count, 1)
        XCTAssertEqual(outputs.filter { $0.output_type == "error" }.count, 1)
        XCTAssertEqual(outputs.first { $0.output_type == "display_data" }?.data?.imagePng, "QUJD")
    }

    func testToJupyterEmptyOutputProducesNoOutputs() {
        let cell = NotebookCell(type: .code, source: "x")
        cell.output = CellOutput()
        let doc = NotebookDocument(title: "t", cells: [cell])
        XCTAssertEqual(doc.toJupyter().cells.first?.outputs?.count, 0)
    }

    // MARK: init(jupyter:) mapping

    func testInitFromJupyterReconstructsOutputChannels() {
        let jc = JupyterCell(id: "c", cellType: "code", source: ["x"],
                             outputs: [
                                .stream("stdout", "out\n"),
                                .stream("stderr", "warn\n"),
                                .result("99", executionCount: 2),
                                .image(base64: "QUJD"),
                             ],
                             executionCount: 2)
        let nb = JupyterNotebook(cells: [jc], metadata: NBMetadata(lectra: nil))
        let doc = NotebookDocument(jupyter: nb)
        let out = doc.cells.first?.output

        XCTAssertEqual(out?.stdout, "out\n")
        XCTAssertEqual(out?.stderr, "warn\n")
        XCTAssertEqual(out?.result, "99")
        XCTAssertEqual(out?.images, ["QUJD"])
    }

    func testInitFromJupyterDefaultsTitleWhenNoProvenance() {
        let nb = JupyterNotebook(cells: [], metadata: NBMetadata(lectra: nil))
        let doc = NotebookDocument(jupyter: nb)
        XCTAssertEqual(doc.title, "Untitled Notebook")
    }

    func testInitFromJupyterReadsProvenance() {
        let meta = NBMetadata(lectra: .init(version: 1,
                                            notebookID: UUID().uuidString,
                                            title: "Restored",
                                            sourceDocument: "doc.pdf",
                                            generatedAt: "2026-06-23T00:00:00Z"))
        let doc = NotebookDocument(jupyter: JupyterNotebook(cells: [], metadata: meta))
        XCTAssertEqual(doc.title, "Restored")
        XCTAssertEqual(doc.sourceDocument, "doc.pdf")
    }

    // MARK: Full round-trip

    func testRoundTripPreservesCellsAndOutput() throws {
        let codeCell = NotebookCell(id: "code", type: .code, source: "print(1)")
        codeCell.executionCount = 1
        codeCell.output = CellOutput(stdout: "1\n", result: "None", images: ["QUJD"])
        let mdCell = NotebookCell(id: "md", type: .markdown, source: "# Notes")
        let doc = NotebookDocument(id: UUID(), title: "Round", cells: [mdCell, codeCell],
                                   sourceDocument: "s.pdf")

        let data = try doc.toJupyter().encodeIPYNB()
        let restored = NotebookDocument(jupyter: try JupyterNotebook(data: data))

        XCTAssertEqual(restored.title, "Round")
        XCTAssertEqual(restored.sourceDocument, "s.pdf")
        XCTAssertEqual(restored.cells.map(\.type), [.markdown, .code])
        XCTAssertEqual(restored.cells.map(\.id), ["md", "code"])

        let restoredOut = restored.cells[1].output
        XCTAssertEqual(restoredOut?.stdout, "1\n")
        XCTAssertEqual(restoredOut?.result, "None")
        XCTAssertEqual(restoredOut?.images, ["QUJD"])
    }

    func testNotebookCellTypeMapsToFromJupyterStrings() {
        XCTAssertEqual(NotebookCellType(jupyter: "markdown"), .markdown)
        XCTAssertEqual(NotebookCellType(jupyter: "code"), .code)
        XCTAssertEqual(NotebookCellType(jupyter: "raw"), .code)  // unknown defaults to code
        XCTAssertEqual(NotebookCellType.markdown.jupyter, "markdown")
        XCTAssertEqual(NotebookCellType.code.jupyter, "code")
    }
}
