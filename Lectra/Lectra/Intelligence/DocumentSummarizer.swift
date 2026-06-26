//
//  DocumentSummarizer.swift
//  Lectra
//
//  Summarizes a document or page, and answers follow-up questions about it
//  over a persistent session (multiturn "Ask this document").
//

import Foundation
import Combine
#if canImport(FoundationModels)
import FoundationModels
#endif

@available(iOS 26.0, *)
@MainActor
final class DocumentSummarizer: ObservableObject {

    enum Scope { case page, document }

    /// Persistent chat session, kept alive so follow-up questions retain context.
    private var chatSession: LanguageModelSession?

    private static let summaryInstructions = """
    You are a study assistant for a college student. Summarize lecture and reading \
    material clearly and accurately. Use plain language. Prefer short paragraphs and \
    tight bullet points. Never invent facts that aren't in the provided text.
    """

    private static let askInstructions = """
    You are a study assistant answering questions about a specific document the \
    student is reading. Answer only from the document's content. If the answer \
    isn't in the document, say so briefly. Be concise and direct.
    """

    // MARK: Summarize

    func summarize(text: String, scope: Scope) async throws -> String {
        let clamped = PDFTextExtractor.clamp(text, toChars: LectraModelRouter.shared.documentCharBudget())
        guard !clamped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "There's no readable text in this document to summarize."
        }

        let task: String
        switch scope {
        case .page:
            task = "Summarize this page in 2–4 sentences, then list any key terms as bullets."
        case .document:
            task = "Give a 3–5 sentence overview, then list the 4–6 most important points as bullets."
        }

        let prompt = """
        \(task)

        --- MATERIAL ---
        \(clamped)
        """
        return try await LectraModelRouter.shared.generateText(
            prompt: prompt,
            instructions: Self.summaryInstructions,
            maxResponseTokens: 600
        )
    }

    // MARK: Ask (multiturn)

    /// Primes the chat session with the document text. Call once when the
    /// "Ask" tab opens; subsequent `ask(_:)` calls reuse the context.
    func beginConversation(documentText: String) {
        let clamped = PDFTextExtractor.clamp(documentText, toChars: LectraModelRouter.shared.documentCharBudget())
        let primed = """
        \(Self.askInstructions)

        Here is the document the student is asking about:
        --- DOCUMENT ---
        \(clamped)
        """
        chatSession = LectraModelRouter.shared.makeSession(
            instructions: primed,
            approxTokens: LectraModelRouter.estimatedTokens(forChars: clamped.count)
        )
    }

    func ask(_ question: String) async throws -> String {
        try await LectraAIRateLimiter.shared.acquire()
        let session = chatSession ?? {
            let fresh = LectraModelRouter.shared.makeSession(instructions: Self.askInstructions)
            chatSession = fresh
            return fresh
        }()
        let response = try await session.respond(
            to: question,
            options: GenerationOptions(maximumResponseTokens: 500)
        )
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resetConversation() { chatSession = nil }
}
