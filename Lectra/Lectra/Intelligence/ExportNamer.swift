//
//  ExportNamer.swift
//  Lectra
//
//  Builds descriptive, filesystem-safe filenames for exported PDFs so shared
//  and Canvascope-delivered files are named after what they contain instead of
//  a generic "annotated.pdf". Prefers the document's own title when it's
//  specific; otherwise asks the on-device model to name it from the contents.
//

import Foundation

@MainActor
enum ExportNamer {

    /// Max characters in a base filename (before the extension). Keeps names
    /// readable and well under filesystem limits.
    private static let maxBaseNameLength = 60

    /// Returns a URL to a uniquely-located temp copy of `sourceURL`, named after
    /// the document. The path is guaranteed unique while the visible filename
    /// stays clean (e.g. "Thermodynamics Lecture 3.pdf"), so the share sheet and
    /// Canvascope upload show a meaningful name. Falls back to `sourceURL` itself
    /// if the copy can't be made.
    static func preparedExportURL(source sourceURL: URL, documentTitle: String) async -> URL {
        let baseName = await descriptiveBaseName(for: documentTitle, pdfURL: sourceURL)
        return tempCopy(of: sourceURL, baseName: baseName) ?? sourceURL
    }

    /// A descriptive, sanitized base filename (no extension) for the document.
    /// Uses the existing title when it's specific; only asks the model when the
    /// title is empty or a generic placeholder ("Untitled", "Scan…", etc.).
    static func descriptiveBaseName(for title: String, pdfURL: URL?) async -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)

        if #available(iOS 26.0, *),
           let url = pdfURL,
           trimmed.isEmpty || DocumentAutoTagger.looksGeneric(trimmed),
           LectraIntelligence.isReady {
            if let labels = try? await DocumentAutoTagger().labels(forFirstPagesOf: url) {
                let cleaned = sanitize(labels.title)
                if !cleaned.isEmpty { return cleaned }
            }
        }

        let cleaned = sanitize(trimmed)
        return cleaned.isEmpty ? "Document" : cleaned
    }

    // MARK: - Helpers

    /// Strips characters that are illegal or awkward in filenames and clamps
    /// length on a word boundary.
    static func sanitize(_ raw: String) -> String {
        var name = raw
        // Drop any extension the model might have echoed back.
        if name.lowercased().hasSuffix(".pdf") { name = String(name.dropLast(4)) }

        // Replace path separators and reserved characters with spaces.
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        name = name.components(separatedBy: illegal).joined(separator: " ")

        // Collapse runs of whitespace and trim.
        name = name.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Avoid a leading dot (would create a hidden file).
        while name.hasPrefix(".") { name.removeFirst() }

        if name.count > maxBaseNameLength {
            let slice = name.prefix(maxBaseNameLength)
            if let lastSpace = slice.lastIndex(of: " ") {
                name = String(slice[..<lastSpace])
            } else {
                name = String(slice)
            }
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Copies `sourceURL` into a unique temp subdirectory as `baseName.pdf` so the
    /// filename stays clean while the path is guaranteed unique. Returns nil if
    /// the copy fails.
    private static func tempCopy(of sourceURL: URL, baseName: String) -> URL? {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        let dest = dir.appendingPathComponent("\(baseName).pdf")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.copyItem(at: sourceURL, to: dest)
            return dest
        } catch {
            return nil
        }
    }
}
