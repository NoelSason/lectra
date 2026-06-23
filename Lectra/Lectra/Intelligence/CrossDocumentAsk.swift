//
//  CrossDocumentAsk.swift
//  Lectra
//
//  Answers questions that span several documents at once — "compare these two
//  readings", "where do my notes cover X". Multiple documents together easily
//  overflow the on-device window, so this leans on the larger Private Cloud
//  Compute context when it's available (iOS 27+) and degrades gracefully to a
//  per-document excerpt on-device otherwise.
//

import Foundation
import Combine
#if canImport(FoundationModels)
import FoundationModels
#endif

@available(iOS 26.0, *)
@MainActor
final class CrossDocumentAsk: ObservableObject {

    /// One document's extracted text, labeled by title so the model can cite it.
    struct Source: Identifiable {
        let id = UUID()
        let title: String
        let text: String
    }

    private var session: LanguageModelSession?

    private static let instructions = """
    You are a study assistant answering a student's questions across several of \
    their documents. Use only the content of the provided documents. When a point \
    comes from a specific document, name that document's title so the student knows \
    where it's from. If the documents disagree, or none of them cover something, say \
    so plainly. Be concise and concrete.
    """

    /// Primes the session with the combined, title-labeled text of all sources.
    /// Each document gets a fair share of the active context budget so later
    /// documents aren't crowded out by earlier ones.
    func begin(sources: [Source]) {
        let budget = LectraModelRouter.shared.documentCharBudget()
        let perDoc = max(2_000, budget / max(1, sources.count))

        let blocks = sources.map { source -> String in
            let clamped = PDFTextExtractor.clamp(source.text, toChars: perDoc)
            return """
            ===== DOCUMENT: \(source.title) =====
            \(clamped)
            """
        }

        let primed = """
        \(Self.instructions)

        Here are the documents the student is asking about:

        \(blocks.joined(separator: "\n\n"))
        """

        let approxTokens = LectraModelRouter.estimatedTokens(forChars: primed.count)
        session = LectraModelRouter.shared.makeSession(instructions: primed, approxTokens: approxTokens)
    }

    func ask(_ question: String) async throws -> String {
        let active = session ?? {
            let fresh = LectraModelRouter.shared.makeSession(instructions: Self.instructions)
            session = fresh
            return fresh
        }()
        let response = try await active.respond(
            to: question,
            options: GenerationOptions(maximumResponseTokens: 700)
        )
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func reset() { session = nil }
}
