//
//  NotebookStore.swift
//  Lectra
//
//  Persists notebooks as `.ipynb` files under Documents/notebooks/ (one file per
//  notebook, keyed by UUID) and seeds new study notebooks from a document's
//  on-device study aids. Mirrors the local-file idiom used by DocumentRepository.
//

import Foundation
import Combine

/// Lightweight listing entry for the notebooks library, read from each file's
/// Lectra metadata without loading the whole notebook.
struct NotebookSummary: Identifiable, Equatable {
    let id: UUID
    let title: String
    let sourceDocument: String?
    let modifiedAt: Date
    let url: URL
}

@MainActor
final class NotebookStore: ObservableObject {
    static let shared = NotebookStore()

    @Published private(set) var summaries: [NotebookSummary] = []

    private let fileManager = FileManager.default

    private var directory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("notebooks", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).ipynb")
    }

    // MARK: Listing

    func refresh() {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []

        summaries = urls
            .filter { $0.pathExtension == "ipynb" }
            .compactMap { url -> NotebookSummary? in
                guard let data = try? Data(contentsOf: url),
                      let nb = try? JupyterNotebook(data: data),
                      let meta = nb.metadata.lectra,
                      let id = UUID(uuidString: meta.notebookID) else { return nil }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? Date.distantPast
                return NotebookSummary(id: id, title: meta.title,
                                       sourceDocument: meta.sourceDocument,
                                       modifiedAt: modified, url: url)
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: Load / save / delete

    func load(id: UUID) -> NotebookDocument? {
        guard let data = try? Data(contentsOf: fileURL(for: id)),
              let nb = try? JupyterNotebook(data: data) else { return nil }
        return NotebookDocument(jupyter: nb)
    }

    @discardableResult
    func save(_ document: NotebookDocument) -> Bool {
        guard let data = try? document.toJupyter().encodeIPYNB() else { return false }
        do {
            try data.write(to: fileURL(for: document.id), options: .atomic)
            refresh()
            return true
        } catch {
            return false
        }
    }

    func delete(id: UUID) {
        try? fileManager.removeItem(at: fileURL(for: id))
        refresh()
    }

    /// A clean temp copy named after the notebook's title, for the share sheet
    /// (so the shared file reads "Thermodynamics.ipynb", not a UUID).
    func exportURL(for document: NotebookDocument) -> URL? {
        guard let data = try? document.toJupyter().encodeIPYNB() else { return nil }
        let base = ExportNamer.sanitize(document.title)
        let name = base.isEmpty ? "Lectra Notebook" : base
        let dir = fileManager.temporaryDirectory
            .appendingPathComponent("notebook-\(UUID().uuidString)", isDirectory: true)
        let dest = dir.appendingPathComponent("\(name).ipynb")
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dest, options: .atomic)
            return dest
        } catch {
            return nil
        }
    }

    // MARK: Creation

    func newEmpty() -> NotebookDocument {
        NotebookDocument(
            title: "Untitled Notebook",
            cells: [
                NotebookCell(type: .markdown, source: "# Untitled Notebook\n\nStart writing, or add a code cell to run Python."),
                NotebookCell(type: .code, source: "")
            ])
    }

    /// Builds a Lectra study notebook from whatever study aids exist. Empty
    /// inputs are skipped, so this works even before every aid is generated.
    @available(iOS 26.0, *)
    func makeStudyNotebook(title: String,
                           sourceDocument: String?,
                           summary: String,
                           cards: [LectraFlashcard],
                           quiz: [LectraQuizQuestion]) -> NotebookDocument {
        var cells: [NotebookCell] = []

        // Branded title block.
        let date = Self.displayDate.string(from: Date())
        var header = "# 📘 \(title)\n\n"
        if let source = sourceDocument, !source.isEmpty {
            header += "*A Lectra study notebook from “\(source)” · \(date)*\n\n"
        } else {
            header += "*A Lectra study notebook · \(date)*\n\n"
        }
        header += "This notebook runs Python right here in Lectra. Run a cell to see it work."
        cells.append(NotebookCell(type: .markdown, source: header))

        // Summary.
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSummary.isEmpty {
            cells.append(NotebookCell(type: .markdown, source: "## Summary\n\n\(trimmedSummary)"))
        }

        // Flashcards as a runnable drill.
        if !cards.isEmpty {
            cells.append(NotebookCell(type: .markdown,
                source: "## Flashcards\n\nRun the cell, then call `drill()` to study."))
            cells.append(NotebookCell(type: .code, source: Self.flashcardCode(cards)))
        }

        // Quiz as a runnable, auto-graded harness.
        if !quiz.isEmpty {
            cells.append(NotebookCell(type: .markdown,
                source: "## Quiz\n\nEdit `my_answers` with letters a–d, then run `grade()`."))
            cells.append(NotebookCell(type: .code, source: Self.quizCode(quiz)))
        }

        if cells.count == 1 {
            // Only the header — give the student somewhere to start.
            cells.append(NotebookCell(type: .code, source: "print(\"Hello from Lectra!\")"))
        }

        return NotebookDocument(title: title, cells: cells, sourceDocument: sourceDocument)
    }

    // MARK: Seeded Python

    @available(iOS 26.0, *)
    private static func flashcardCode(_ cards: [LectraFlashcard]) -> String {
        let pairs = cards.map { [$0.front, $0.back] }
        return """
        # Lectra flashcards — run this cell, then call drill() to study.
        cards = \(pyLiteral(pairs))

        def drill():
            for i, (front, back) in enumerate(cards, 1):
                print(f"Card {i}: {front}")
                print(f"   ↳ {back}\\n")

        drill()
        """
    }

    @available(iOS 26.0, *)
    private static func quizCode(_ quiz: [LectraQuizQuestion]) -> String {
        let questions: [[String: Any]] = quiz.map {
            ["q": $0.prompt, "options": $0.options, "answer": $0.correctIndex, "why": $0.explanation]
        }
        return """
        # Lectra quiz — set your answers (a–d) in my_answers, then run grade().
        questions = \(pyLiteral(questions))

        my_answers = [None] * len(questions)   # e.g. my_answers[0] = "b"

        def grade():
            letters = "abcd"
            score = 0
            for i, item in enumerate(questions):
                correct = letters[item["answer"]]
                mine = (my_answers[i] or "").strip().lower()
                ok = mine == correct
                score += 1 if ok else 0
                mark = "✓" if ok else "✗"
                print(f"{mark} Q{i+1}: {item['q']}")
                for j, opt in enumerate(item["options"]):
                    print(f"     {letters[j]}) {opt}")
                if not ok:
                    print(f"   → correct answer: {correct})")
                print(f"   why: {item['why']}\\n")
            print(f"Score: {score}/{len(questions)}")

        grade()
        """
    }

    /// Renders a JSON-compatible value as Python source. The structures used
    /// here contain only strings, ints, lists, and dicts, for which JSON is also
    /// valid Python — so this is safe and keeps escaping correct.
    private static func pyLiteral(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .withoutEscapingSlashes]),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    private static let displayDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
