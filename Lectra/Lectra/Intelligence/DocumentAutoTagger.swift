//
//  DocumentAutoTagger.swift
//  Lectra
//
//  Suggests a human-readable title and topic tags for an incoming document
//  whose title is generic (e.g. "Untitled Notebook", "Scan 2026-06-14").
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@available(iOS 26.0, *)
@MainActor
final class DocumentAutoTagger {

    private static let instructions = """
    You name and tag a student's lecture or homework PDF from its opening text. \
    Produce a specific, concise title (no file extensions, no dates unless they're \
    part of the topic) and a few lowercase topic tags. Base everything strictly on \
    the provided text.
    """

    /// Phrases that signal a placeholder title worth replacing.
    static let genericTitleMarkers = ["untitled", "scan", "document", "new notebook", "imported", "image"]

    static func looksGeneric(_ title: String) -> Bool {
        let lowered = title.lowercased()
        return genericTitleMarkers.contains { lowered.contains($0) } || lowered.count <= 2
    }

    func labels(forFirstPagesOf url: URL) async throws -> LectraDocumentLabels {
        // Only the first couple of pages are needed to infer a title.
        let text = PDFTextExtractor.fullText(at: url, pageLimit: 2)
        let clamped = PDFTextExtractor.clamp(text, toChars: 4_000)
        let prompt = """
        Suggest a title and topic tags for this document based on its opening text.

        --- OPENING TEXT ---
        \(clamped)
        """
        return try await LectraModelRouter.shared.generate(
            LectraDocumentLabels.self,
            prompt: prompt,
            instructions: Self.instructions,
            maxResponseTokens: 120
        )
    }
}
