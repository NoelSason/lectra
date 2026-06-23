//
//  StudyAidGenerator.swift
//  Lectra
//
//  Turns document text into flashcards and a practice quiz using guided
//  generation so the output is always well-formed.
//

import Foundation
import Combine
#if canImport(FoundationModels)
import FoundationModels
#endif

@available(iOS 26.0, *)
@MainActor
final class StudyAidGenerator: ObservableObject {

    private static let flashcardInstructions = """
    You create study flashcards for a college student from their course material. \
    Each card tests one idea. Front = a question or term; back = the answer or \
    definition. Base every card strictly on the provided material. Order cards from \
    most to least important.
    """

    private static let quizInstructions = """
    You write fair multiple-choice practice quizzes from a student's course material. \
    Each question has exactly four plausible options with one correct answer and a \
    one-sentence explanation. Base every question strictly on the provided material.
    """

    func flashcards(from text: String) async throws -> [LectraFlashcard] {
        let clamped = PDFTextExtractor.clamp(text, toChars: LectraModelRouter.shared.documentCharBudget())
        let prompt = """
        Create study flashcards from the material below.

        --- MATERIAL ---
        \(clamped)
        """
        let set = try await LectraModelRouter.shared.generate(
            LectraFlashcardSet.self,
            prompt: prompt,
            instructions: Self.flashcardInstructions,
            maxResponseTokens: 900
        )
        return set.cards
    }

    func quiz(from text: String) async throws -> [LectraQuizQuestion] {
        let clamped = PDFTextExtractor.clamp(text, toChars: LectraModelRouter.shared.documentCharBudget())
        let prompt = """
        Write a practice quiz from the material below.

        --- MATERIAL ---
        \(clamped)
        """
        let quiz = try await LectraModelRouter.shared.generate(
            LectraQuiz.self,
            prompt: prompt,
            instructions: Self.quizInstructions,
            maxResponseTokens: 1100
        )
        // Defensive: keep only well-formed questions (4 options, valid index).
        return quiz.questions.filter { $0.options.count == 4 && $0.correctIndex >= 0 && $0.correctIndex < 4 }
    }
}
