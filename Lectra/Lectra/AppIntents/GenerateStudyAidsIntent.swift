//
//  GenerateStudyAidsIntent.swift
//  Lectra
//
//  "Make flashcards from ⟨document⟩" — generates on-device flashcards and
//  reports how many were created.
//

import AppIntents

struct GenerateStudyAidsIntent: AppIntent {
    static var title: LocalizedStringResource = "Generate Flashcards"
    static var description = IntentDescription(
        "Create on-device study flashcards from a Lectra document.",
        categoryName: "Intelligence"
    )

    @Parameter(title: "Document")
    var document: LectraDocumentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Make flashcards from \(\.$document)")
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
            return .result(dialog: "That document doesn't have any readable text to study from.")
        }

        let cards = try await StudyAidGenerator().flashcards(from: text)
        guard let first = cards.first else {
            return .result(dialog: "I couldn't generate flashcards from that document.")
        }

        let dialog = "I made \(cards.count) flashcards. The first one asks: \(first.front)"
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}
