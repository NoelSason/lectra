//
//  ConceptEnricher.swift
//  Lectra
//
//  Layers LLM-generated definitions and takeaways on top of the existing
//  rule-based Course Brain concept clusters. The rule-based extractor
//  (`CourseBrainConceptExtractor`) still produces the graph instantly; this
//  enriches individual concepts on demand, so Course Brain works unchanged
//  on devices without Apple Intelligence.
//

import Foundation
import Combine
#if canImport(FoundationModels)
import FoundationModels
#endif

@available(iOS 26.0, *)
@MainActor
final class ConceptEnricher: ObservableObject {

    private static let instructions = """
    You explain academic concepts to a college student in plain language. Given a \
    concept name and some surrounding course text, write a short definition and one \
    key takeaway. Stay grounded in the supplied context; don't invent specifics.
    """

    /// Enrich a single concept. `context` is nearby text from the sources the
    /// concept was extracted from (kept short to fit the on-device window).
    func insight(forConcept concept: String, context: String) async throws -> LectraConceptInsight {
        let clamped = PDFTextExtractor.clamp(context, toChars: 6_000)
        let prompt = """
        Concept: "\(concept)"

        Surrounding course text:
        \(clamped)

        Explain this concept for the student.
        """
        return try await LectraModelRouter.shared.generate(
            LectraConceptInsight.self,
            prompt: prompt,
            instructions: Self.instructions,
            maxResponseTokens: 200
        )
    }
}
