//
//  SummarizeDocumentIntent.swift
//  Lectra
//
//  "Summarize ⟨document⟩" — runs Lectra's on-device summarizer from Siri,
//  Shortcuts, or Apple Intelligence and speaks/shows the result.
//

import AppIntents

struct SummarizeDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Summarize Document"
    static var description = IntentDescription(
        "Generate an on-device summary of a Lectra document.",
        categoryName: "Intelligence"
    )

    @Parameter(title: "Document")
    var document: LectraDocumentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Summarize \(\.$document)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let url = LectraDocumentIndex.document(for: document.id)?.url else {
            return .result(dialog: "I couldn't find that document on this device.")
        }

        guard #available(iOS 26.0, *), LectraIntelligence.isReady else {
            return .result(dialog: IntentDialog(stringLiteral: LectraIntelligence.status.message))
        }

        let text = PDFTextExtractor.fullText(at: url)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .result(dialog: "That document doesn't have any readable text to summarize.")
        }

        let summary = try await DocumentSummarizer().summarize(text: text, scope: .document)
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}
