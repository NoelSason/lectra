//
//  IntelligenceModels.swift
//  Lectra
//
//  Guided-generation (`@Generable`) value types the on-device model fills in.
//  Keeping them in one place lets the feature services and SwiftUI views share
//  a single contract.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@available(iOS 26.0, *)
@Generable(description: "A single study flashcard with a question on the front and the answer on the back.")
struct LectraFlashcard: Equatable, Identifiable {
    var id: String { front }

    @Guide(description: "A concise question, term, or prompt for the front of the card.")
    var front: String

    @Guide(description: "The clear, correct answer or definition for the back of the card.")
    var back: String
}

@available(iOS 26.0, *)
@Generable(description: "A set of study flashcards covering the most important ideas in the material.")
struct LectraFlashcardSet {
    @Guide(description: "Between 5 and 12 flashcards, ordered from most to least important.")
    var cards: [LectraFlashcard]
}

@available(iOS 26.0, *)
@Generable(description: "A multiple-choice quiz question with four options and the correct answer.")
struct LectraQuizQuestion: Equatable, Identifiable {
    var id: String { prompt }

    @Guide(description: "The question text.")
    var prompt: String

    @Guide(description: "Exactly four answer options. Only one is correct.")
    var options: [String]

    @Guide(description: "The zero-based index (0–3) of the correct option in 'options'.")
    var correctIndex: Int

    @Guide(description: "A one-sentence explanation of why the correct answer is right.")
    var explanation: String
}

@available(iOS 26.0, *)
@Generable(description: "A short practice quiz generated from the material.")
struct LectraQuiz {
    @Guide(description: "Between 4 and 8 multiple-choice questions covering the key concepts.")
    var questions: [LectraQuizQuestion]
}

@available(iOS 26.0, *)
@Generable(description: "A suggested title and topic tags for a document, inferred from its contents.")
struct LectraDocumentLabels {
    @Guide(description: "A specific, human-readable document title of at most six words. No file extension.")
    var title: String

    @Guide(description: "Two to four short lowercase topic tags (e.g. 'thermodynamics', 'derivatives').")
    var tags: [String]
}

@available(iOS 26.0, *)
@Generable(description: "An enriched explanation of a single course concept.")
struct LectraConceptInsight {
    @Guide(description: "A one- or two-sentence plain-language definition of the concept.")
    var definition: String

    @Guide(description: "One concrete key takeaway a student should remember about this concept.")
    var keyTakeaway: String
}
