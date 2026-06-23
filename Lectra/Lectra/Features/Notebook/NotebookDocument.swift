//
//  NotebookDocument.swift
//  Lectra
//
//  The live, editable in-app representation of a notebook. Cells are reference
//  types so each cell view observes only its own state; the document republishes
//  when cells are added, removed, or reordered. `toJupyter()` / `init(jupyter:)`
//  bridge to the on-disk `.ipynb` format (see JupyterNotebook.swift).
//

import Foundation
import Combine

// MARK: - Cell

enum NotebookCellType: String {
    case markdown
    case code

    var jupyter: String { rawValue }
    init(jupyter: String) { self = jupyter == "markdown" ? .markdown : .code }
}

/// Captured output of one code-cell run.
struct CellOutput: Equatable {
    var stdout: String = ""
    var stderr: String = ""
    var result: String?      // repr of last expression
    var error: String?       // traceback
    var images: [String] = []  // base64-encoded PNGs (matplotlib figures)

    var isEmpty: Bool {
        stdout.isEmpty && stderr.isEmpty && (result?.isEmpty ?? true)
            && (error?.isEmpty ?? true) && images.isEmpty
    }

    init(stdout: String = "", stderr: String = "", result: String? = nil,
         error: String? = nil, images: [String] = []) {
        self.stdout = stdout
        self.stderr = stderr
        self.result = result
        self.error = error
        self.images = images
    }

    init(_ run: PyodideRunResult) {
        self.init(stdout: run.stdout, stderr: run.stderr, result: run.result,
                  error: run.error, images: run.images)
    }
}

@MainActor
final class NotebookCell: ObservableObject, Identifiable {
    let id: String
    @Published var type: NotebookCellType
    @Published var source: String
    @Published var output: CellOutput?
    @Published var isRunning: Bool = false
    @Published var executionCount: Int?

    init(id: String = UUID().uuidString,
         type: NotebookCellType,
         source: String,
         output: CellOutput? = nil,
         executionCount: Int? = nil) {
        self.id = id
        self.type = type
        self.source = source
        self.output = output
        self.executionCount = executionCount
    }
}

// MARK: - Document

@MainActor
final class NotebookDocument: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    @Published var cells: [NotebookCell]
    /// The cell whose editor should hold keyboard focus. Drives programmatic
    /// focus moves for the run shortcuts (Shift/⌥+Enter).
    @Published var focusedCellID: String?
    let sourceDocument: String?
    let createdAt: Date

    private var runCounter = 0

    init(id: UUID = UUID(),
         title: String,
         cells: [NotebookCell],
         sourceDocument: String? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.cells = cells
        self.sourceDocument = sourceDocument
        self.createdAt = createdAt
    }

    // MARK: Cell editing

    @discardableResult
    func addCell(_ type: NotebookCellType, after cell: NotebookCell?) -> NotebookCell {
        let new = NotebookCell(type: type, source: "")
        if let cell, let idx = cells.firstIndex(where: { $0.id == cell.id }) {
            cells.insert(new, at: idx + 1)
        } else {
            cells.append(new)
        }
        return new
    }

    /// The first code cell after `cell`, if any.
    func nextCodeCell(after cell: NotebookCell) -> NotebookCell? {
        guard let idx = cells.firstIndex(where: { $0.id == cell.id }) else { return nil }
        return cells[(idx + 1)...].first { $0.type == .code }
    }

    func delete(_ cell: NotebookCell) {
        cells.removeAll { $0.id == cell.id }
    }

    func move(_ cell: NotebookCell, by offset: Int) {
        guard let idx = cells.firstIndex(where: { $0.id == cell.id }) else { return }
        let target = idx + offset
        guard target >= 0, target < cells.count else { return }
        cells.swapAt(idx, target)
    }

    func changeType(_ cell: NotebookCell, to type: NotebookCellType) {
        cell.type = type
        if type == .markdown { cell.output = nil; cell.executionCount = nil }
    }

    func nextExecutionCount() -> Int {
        runCounter += 1
        return runCounter
    }

    // MARK: Bridge to / from .ipynb

    func toJupyter() -> JupyterNotebook {
        let formatter = ISO8601DateFormatter()
        let meta = NBMetadata(lectra: NBMetadata.LectraMeta(
            version: 1,
            notebookID: id.uuidString,
            title: title,
            sourceDocument: sourceDocument,
            generatedAt: formatter.string(from: createdAt)))

        let jcells: [JupyterCell] = cells.map { cell in
            let source = JupyterOutput.splitKeepingNewlines(cell.source)
            switch cell.type {
            case .markdown:
                return JupyterCell(id: cell.id, cellType: "markdown", source: source)
            case .code:
                return JupyterCell(id: cell.id, cellType: "code",
                                   source: source,
                                   outputs: Self.outputs(from: cell.output, count: cell.executionCount),
                                   executionCount: cell.executionCount)
            }
        }
        return JupyterNotebook(cells: jcells, metadata: meta)
    }

    convenience init(jupyter: JupyterNotebook) {
        let lectra = jupyter.metadata.lectra
        let id = lectra.flatMap { UUID(uuidString: $0.notebookID) } ?? UUID()
        let formatter = ISO8601DateFormatter()
        let created = lectra.flatMap { formatter.date(from: $0.generatedAt) } ?? Date()
        let cells: [NotebookCell] = jupyter.cells.map { jc in
            let type = NotebookCellType(jupyter: jc.cell_type)
            return NotebookCell(
                id: jc.id,
                type: type,
                source: jc.source.joined(),
                output: type == .code ? Self.output(from: jc.outputs) : nil,
                executionCount: jc.execution_count)
        }
        self.init(id: id,
                  title: lectra?.title ?? "Untitled Notebook",
                  cells: cells,
                  sourceDocument: lectra?.sourceDocument,
                  createdAt: created)
    }

    // MARK: Output mapping

    private static func outputs(from output: CellOutput?, count: Int?) -> [JupyterOutput] {
        guard let output, !output.isEmpty else { return [] }
        var result: [JupyterOutput] = []
        if !output.stdout.isEmpty { result.append(.stream("stdout", output.stdout)) }
        if !output.stderr.isEmpty { result.append(.stream("stderr", output.stderr)) }
        if let repr = output.result, !repr.isEmpty {
            result.append(.result(repr, executionCount: count ?? 0))
        }
        for png in output.images where !png.isEmpty {
            result.append(.image(base64: png))
        }
        if let error = output.error, !error.isEmpty {
            let lines = error.components(separatedBy: "\n")
            result.append(.error(name: "Error",
                                 value: lines.last(where: { !$0.isEmpty }) ?? "Error",
                                 traceback: lines))
        }
        return result
    }

    private static func output(from outputs: [JupyterOutput]?) -> CellOutput? {
        guard let outputs, !outputs.isEmpty else { return nil }
        var out = CellOutput()
        for o in outputs {
            switch o.output_type {
            case "stream":
                if o.name == "stderr" { out.stderr += (o.text ?? []).joined() }
                else { out.stdout += (o.text ?? []).joined() }
            case "execute_result", "display_data":
                if let png = o.data?.imagePng, !png.isEmpty {
                    out.images.append(png)
                } else if let text = o.data?.textPlain {
                    out.result = text.joined()
                }
            case "error":
                out.error = (o.traceback ?? []).joined(separator: "\n")
            default:
                break
            }
        }
        return out.isEmpty ? nil : out
    }
}
