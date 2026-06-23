import XCTest
@testable import Lectra

/// Exercises the on-disk `.ipynb` (nbformat v4) Codable layer: line splitting,
/// output builders, full-notebook round-trips, and the deliberately lenient
/// decoding that lets Lectra re-open its own (and others') notebooks.
final class JupyterNotebookCodecTests: XCTestCase {

    // MARK: splitKeepingNewlines

    func testSplitEmptyStringYieldsNoLines() {
        XCTAssertEqual(JupyterOutput.splitKeepingNewlines(""), [])
    }

    func testSplitSingleLineWithoutNewline() {
        XCTAssertEqual(JupyterOutput.splitKeepingNewlines("hello"), ["hello"])
    }

    func testSplitKeepsTrailingNewlineOnEachLine() {
        XCTAssertEqual(JupyterOutput.splitKeepingNewlines("a\nb"), ["a\n", "b"])
    }

    func testSplitTrailingNewlineProducesNoEmptyTail() {
        XCTAssertEqual(JupyterOutput.splitKeepingNewlines("a\n"), ["a\n"])
    }

    func testSplitMultipleTrailingNewlines() {
        XCTAssertEqual(JupyterOutput.splitKeepingNewlines("a\nb\n"), ["a\n", "b\n"])
    }

    func testSplitBareNewline() {
        XCTAssertEqual(JupyterOutput.splitKeepingNewlines("\n"), ["\n"])
    }

    func testSplitBlankLinesPreserved() {
        XCTAssertEqual(JupyterOutput.splitKeepingNewlines("a\n\nb"), ["a\n", "\n", "b"])
    }

    // MARK: Output builders

    func testStreamBuilder() {
        let out = JupyterOutput.stream("stdout", "line\n")
        XCTAssertEqual(out.output_type, "stream")
        XCTAssertEqual(out.name, "stdout")
        XCTAssertEqual(out.text, ["line\n"])
        XCTAssertNil(out.data)
    }

    func testResultBuilderCarriesTextPlainAndExecutionCount() {
        let out = JupyterOutput.result("42", executionCount: 7)
        XCTAssertEqual(out.output_type, "execute_result")
        XCTAssertEqual(out.execution_count, 7)
        XCTAssertEqual(out.data?.textPlain, ["42"])
        XCTAssertNil(out.data?.imagePng)
    }

    func testErrorBuilder() {
        let out = JupyterOutput.error(name: "ValueError",
                                      value: "bad",
                                      traceback: ["Traceback", "ValueError: bad"])
        XCTAssertEqual(out.output_type, "error")
        XCTAssertEqual(out.ename, "ValueError")
        XCTAssertEqual(out.evalue, "bad")
        XCTAssertEqual(out.traceback, ["Traceback", "ValueError: bad"])
    }

    func testImageBuilderProducesDisplayDataWithPNG() {
        let out = JupyterOutput.image(base64: "QUJD")
        XCTAssertEqual(out.output_type, "display_data")
        XCTAssertEqual(out.data?.imagePng, "QUJD")
        XCTAssertNil(out.data?.textPlain)
    }

    // MARK: Full notebook round-trip

    func testNotebookSetsNbformatVersion() {
        let nb = makeNotebook(cells: [])
        XCTAssertEqual(nb.nbformat, 4)
        XCTAssertEqual(nb.nbformat_minor, 5)
    }

    func testEncodeDecodePreservesCellStructure() throws {
        let nb = makeNotebook(cells: [
            JupyterCell(id: "md1", cellType: "markdown", source: ["# Title\n"]),
            JupyterCell(id: "code1", cellType: "code",
                        source: ["print(1)\n"],
                        outputs: [.stream("stdout", "1\n")],
                        executionCount: 1),
        ])
        let data = try nb.encodeIPYNB()
        let decoded = try JupyterNotebook(data: data)

        XCTAssertEqual(decoded.cells.count, 2)
        XCTAssertEqual(decoded.cells[0].cell_type, "markdown")
        XCTAssertEqual(decoded.cells[0].source, ["# Title\n"])
        XCTAssertEqual(decoded.cells[1].cell_type, "code")
        XCTAssertEqual(decoded.cells[1].execution_count, 1)
        XCTAssertEqual(decoded.cells[1].outputs?.first?.name, "stdout")
    }

    func testEncodeProducesSortedKeyJSON() throws {
        let data = try makeNotebook(cells: []).encodeIPYNB()
        let json = String(decoding: data, as: UTF8.self)
        // sortedKeys puts cells before metadata before nbformat.
        let cellsIdx = try XCTUnwrap(json.range(of: "\"cells\""))
        let nbformatIdx = try XCTUnwrap(json.range(of: "\"nbformat\""))
        XCTAssertLessThan(cellsIdx.lowerBound, nbformatIdx.lowerBound)
    }

    func testProvenanceMetadataRoundTrips() throws {
        let meta = NBMetadata(lectra: .init(version: 1,
                                            notebookID: "ABC-123",
                                            title: "My Notebook",
                                            sourceDocument: "src.pdf",
                                            generatedAt: "2026-06-23T00:00:00Z"))
        let nb = JupyterNotebook(cells: [], metadata: meta)
        let decoded = try JupyterNotebook(data: nb.encodeIPYNB())
        XCTAssertEqual(decoded.metadata.lectra?.notebookID, "ABC-123")
        XCTAssertEqual(decoded.metadata.lectra?.title, "My Notebook")
        XCTAssertEqual(decoded.metadata.lectra?.sourceDocument, "src.pdf")
    }

    func testKernelspecDefaultsArePython3() {
        let meta = NBMetadata(lectra: nil)
        XCTAssertEqual(meta.kernelspec.name, "python3")
        XCTAssertEqual(meta.language_info.name, "python")
    }

    // MARK: Lenient decoding

    func testDecodeSourceAsSingleStringSplitsIntoLines() throws {
        let nb = try decodeNotebook(cellsJSON: """
        [{"id":"c","cell_type":"markdown","source":"a\\nb"}]
        """)
        XCTAssertEqual(nb.cells.first?.source, ["a\n", "b"])
    }

    func testDecodeSourceAsArrayIsKept() throws {
        let nb = try decodeNotebook(cellsJSON: """
        [{"id":"c","cell_type":"code","source":["x = 1\\n","y = 2"]}]
        """)
        XCTAssertEqual(nb.cells.first?.source, ["x = 1\n", "y = 2"])
    }

    func testDecodeMissingIdGeneratesNonEmptyID() throws {
        let nb = try decodeNotebook(cellsJSON: """
        [{"cell_type":"code","source":"x"}]
        """)
        XCTAssertFalse(nb.cells.first?.id.isEmpty ?? true)
    }

    func testDecodeMissingCellTypeDefaultsToCode() throws {
        let nb = try decodeNotebook(cellsJSON: """
        [{"id":"c","source":"x"}]
        """)
        XCTAssertEqual(nb.cells.first?.cell_type, "code")
    }

    func testDecodeSkipsOutputMissingRequiredType() throws {
        // One valid stream output and one malformed entry (no output_type).
        let nb = try decodeNotebook(cellsJSON: """
        [{"id":"c","cell_type":"code","source":"x","outputs":[
          {"output_type":"stream","name":"stdout","text":"hi"},
          {"name":"stdout","text":"oops"}
        ]}]
        """)
        XCTAssertEqual(nb.cells.first?.outputs?.count, 1)
        XCTAssertEqual(nb.cells.first?.outputs?.first?.name, "stdout")
    }

    func testDecodeStreamTextAsSingleString() throws {
        let nb = try decodeNotebook(cellsJSON: """
        [{"id":"c","cell_type":"code","source":"x","outputs":[
          {"output_type":"stream","name":"stdout","text":"one\\ntwo"}
        ]}]
        """)
        XCTAssertEqual(nb.cells.first?.outputs?.first?.text, ["one\n", "two"])
    }

    func testDecodeExecuteResultTextPlain() throws {
        let nb = try decodeNotebook(cellsJSON: """
        [{"id":"c","cell_type":"code","source":"x","outputs":[
          {"output_type":"execute_result","execution_count":3,"data":{"text/plain":["42"]}}
        ]}]
        """)
        let out = nb.cells.first?.outputs?.first
        XCTAssertEqual(out?.execution_count, 3)
        XCTAssertEqual(out?.data?.textPlain, ["42"])
    }

    func testDecodeDisplayDataImagePNG() throws {
        let nb = try decodeNotebook(cellsJSON: """
        [{"id":"c","cell_type":"code","source":"x","outputs":[
          {"output_type":"display_data","data":{"image/png":"QUJD"}}
        ]}]
        """)
        XCTAssertEqual(nb.cells.first?.outputs?.first?.data?.imagePng, "QUJD")
    }

    func testDecodeUnknownTopLevelKeysIgnored() throws {
        let nb = try decodeNotebook(cellsJSON: """
        [{"id":"c","cell_type":"code","source":"x","collapsed":true,"foo":{"bar":1}}]
        """)
        XCTAssertEqual(nb.cells.first?.source, ["x"])
    }

    // MARK: Helpers

    private func makeNotebook(cells: [JupyterCell]) -> JupyterNotebook {
        JupyterNotebook(cells: cells, metadata: NBMetadata(lectra: nil))
    }

    /// Wraps a cells JSON fragment in a minimal valid notebook envelope and
    /// decodes it through the real `JupyterNotebook` decoder.
    private func decodeNotebook(cellsJSON: String) throws -> JupyterNotebook {
        let json = """
        {
          "cells": \(cellsJSON),
          "metadata": {
            "kernelspec": {"display_name":"Python 3","language":"python","name":"python3"},
            "language_info": {"name":"python"}
          },
          "nbformat": 4,
          "nbformat_minor": 5
        }
        """
        return try JupyterNotebook(data: Data(json.utf8))
    }
}
