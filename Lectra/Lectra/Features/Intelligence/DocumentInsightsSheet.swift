//
//  DocumentInsightsSheet.swift
//  Lectra
//
//  The in-editor "Intelligence" surface: summarize the document, ask
//  questions about it, and generate flashcards + a practice quiz — all
//  running privately on-device via Apple Foundation Models.
//
//  All generated output lives in a single `InsightsStore` owned by the sheet,
//  so switching between the Summary / Ask / Cards / Quiz tabs keeps prior
//  results visible. Output is only cleared when the user regenerates it.
//
//  The sheet is available on every OS Lectra supports; the model-backed
//  content lives in an @available(iOS 26) inner view, so older devices and
//  devices without Apple Intelligence see a friendly explanation instead.
//

import SwiftUI
import Combine

struct DocumentInsightsSheet: View {
    let documentTitle: String
    let pdfURL: URL
    /// Page the editor is currently on (0-based) for "summarize this page".
    let currentPage: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if #available(iOS 26.0, *), LectraIntelligence.isReady {
                    IntelligenceContentView(
                        documentTitle: documentTitle,
                        pdfURL: pdfURL,
                        currentPage: currentPage
                    )
                } else {
                    IntelligenceUnavailableView(status: LectraIntelligence.status)
                }
            }
            .background(LectraGradient.appBackdrop.ignoresSafeArea())
            .navigationTitle("Intelligence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        LectraHaptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(LectraColor.textTertiary)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .toolbarBackground(LectraColor.surfaceOverlay, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Unavailable state

private struct IntelligenceUnavailableView: View {
    let status: LectraIntelligenceStatus

    var body: some View {
        VStack(spacing: LectraSpacing.md) {
            ZStack {
                Circle()
                    .fill(LectraColor.accent.opacity(0.14))
                    .frame(width: 96, height: 96)
                Image(systemName: status.systemImage)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(LectraColor.accentSoft)
            }
            Text(status.headline)
                .font(LectraTypography.title)
                .foregroundStyle(LectraColor.textPrimary)
            Text(status.message)
                .font(LectraTypography.body)
                .foregroundStyle(LectraColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LectraSpacing.xl)
            if status == .appleIntelligenceOff,
               let url = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: url) {
                    Text("Open Settings")
                }
                .buttonStyle(LectraSecondaryButtonStyle())
                .padding(.top, LectraSpacing.sm)
            }
            Spacer()
        }
        .padding(.top, LectraSpacing.xxl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Persistent store (survives tab switches; cleared only on regenerate)

@available(iOS 26.0, *)
@MainActor
private final class InsightsStore: ObservableObject {
    struct AskTurn: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
    }

    private let summarizer = DocumentSummarizer()
    private let generator = StudyAidGenerator()

    /// Whole-document text, loaded once.
    @Published var documentText = ""
    @Published var isTextReady = false

    // Summary
    @Published var summary = ""
    @Published var summaryScope: DocumentSummarizer.Scope = .document
    @Published var summaryLoading = false
    @Published var summaryError: String?

    // Ask
    @Published var askTurns: [AskTurn] = []
    @Published var askLoading = false
    @Published var askError: String?
    private var askPrimed = false

    // Flashcards
    @Published var cards: [LectraFlashcard] = []
    @Published var cardsLoading = false
    @Published var cardsError: String?

    // Quiz
    @Published var quiz: [LectraQuizQuestion] = []
    @Published var quizLoading = false
    @Published var quizError: String?

    func loadText(from url: URL) async {
        guard !isTextReady else { return }
        let text = await Task.detached(priority: .userInitiated) {
            PDFTextExtractor.fullText(at: url)
        }.value
        documentText = text
        isTextReady = true
    }

    /// How the whole document will be handled, so the UI can show an honest cue
    /// (full extended context vs. only the first portion). Only meaningful for
    /// whole-document features; page summaries are always short.
    var documentContextHandling: LectraModelRouter.ContextHandling {
        LectraModelRouter.shared.contextHandling(forChars: documentText.count)
    }

    func summarize(pageText: String) async {
        summaryLoading = true
        summaryError = nil
        defer { summaryLoading = false }
        let text = summaryScope == .page ? pageText : documentText
        do {
            summary = try await summarizer.summarize(text: text, scope: summaryScope)
        } catch {
            summaryError = "Couldn't generate a summary. \(error.localizedDescription)"
        }
    }

    func ask(_ question: String) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        if !askPrimed { summarizer.beginConversation(documentText: documentText); askPrimed = true }
        askLoading = true
        askError = nil
        defer { askLoading = false }
        do {
            let answer = try await summarizer.ask(q)
            askTurns.append(AskTurn(question: q, answer: answer))
        } catch {
            askError = "Couldn't answer that. \(error.localizedDescription)"
        }
    }

    func makeFlashcards() async {
        cardsLoading = true
        cardsError = nil
        defer { cardsLoading = false }
        do {
            cards = try await generator.flashcards(from: documentText)
        } catch {
            cardsError = "Couldn't generate flashcards. \(error.localizedDescription)"
        }
    }

    func makeQuiz() async {
        quizLoading = true
        quizError = nil
        defer { quizLoading = false }
        do {
            quiz = try await generator.quiz(from: documentText)
        } catch {
            quizError = "Couldn't generate a quiz. \(error.localizedDescription)"
        }
    }
}

// MARK: - Tabs

private enum InsightTab: String, CaseIterable, Identifiable {
    case summary, ask, flashcards, quiz
    var id: String { rawValue }
    var title: String {
        switch self {
        case .summary: return "Summary"
        case .ask: return "Ask"
        case .flashcards: return "Cards"
        case .quiz: return "Quiz"
        }
    }
    var icon: String {
        switch self {
        case .summary: return "text.alignleft"
        case .ask: return "bubble.left.and.text.bubble.right"
        case .flashcards: return "rectangle.on.rectangle.angled"
        case .quiz: return "checklist"
        }
    }
}

// MARK: - Model-backed content

@available(iOS 26.0, *)
private struct IntelligenceContentView: View {
    let documentTitle: String
    let pdfURL: URL
    let currentPage: Int

    @State private var tab: InsightTab = .summary
    @StateObject private var store = InsightsStore()
    @State private var notebookDoc: NotebookDocument?

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().overlay(LectraColor.edgeStroke)
            if store.isTextReady, tab != .summary || store.summaryScope == .document {
                ContextBanner(handling: store.documentContextHandling)
            }
            ScrollView {
                Group {
                    switch tab {
                    case .summary:    SummaryTabView(store: store, pageText: pageText)
                    case .ask:        AskTabView(store: store)
                    case .flashcards: FlashcardsTabView(store: store)
                    case .quiz:       QuizTabView(store: store)
                    }
                }
                .padding(LectraSpacing.lg)
            }
        }
        .safeAreaInset(edge: .bottom) { createNotebookBar }
        .task { await store.loadText(from: pdfURL) }
        .fullScreenCover(item: $notebookDoc) { doc in
            NotebookView(document: doc)
        }
    }

    /// Turns the document's study aids into a runnable Lectra notebook. Works
    /// with whatever has been generated so far (and seeds a starter cell if
    /// nothing has).
    private var createNotebookBar: some View {
        Button {
            LectraHaptics.tap()
            notebookDoc = NotebookStore.shared.makeStudyNotebook(
                title: documentTitle,
                sourceDocument: documentTitle,
                summary: store.summary,
                cards: store.cards,
                quiz: store.quiz)
        } label: {
            Label("Create Notebook", systemImage: "book.closed")
        }
        .buttonStyle(LectraPrimaryButtonStyle())
        .padding(.horizontal, LectraSpacing.lg)
        .padding(.vertical, LectraSpacing.sm)
        .background(.ultraThinMaterial)
    }

    private var pageText: String {
        PDFTextExtractor.text(at: pdfURL, pageIndex: currentPage)
    }

    private var tabBar: some View {
        HStack(spacing: LectraSpacing.sm) {
            ForEach(InsightTab.allCases) { item in
                Button {
                    LectraHaptics.selection()
                    withAnimation(LectraMotion.tabSwitch) { tab = item }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 15, weight: .semibold))
                        Text(item.title)
                            .font(LectraTypography.footnoteBold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(tab == item ? LectraColor.textPrimary : LectraColor.textTertiary)
                    .background(
                        RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                            .fill(tab == item ? LectraColor.accent.opacity(0.18) : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                                    .stroke(tab == item ? LectraColor.accent.opacity(0.45) : Color.clear, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(LectraSpacing.md)
    }
}

// MARK: - Context banner (honest cue about how much of the document is used)

@available(iOS 26.0, *)
private struct ContextBanner: View {
    let handling: LectraModelRouter.ContextHandling

    var body: some View {
        switch handling {
        case .standard:
            EmptyView()
        case .extended:
            banner(
                icon: "sparkles",
                tint: LectraColor.accentSoft,
                text: "This is a long document — it's being read in full."
            )
        case .truncated:
            banner(
                icon: "doc.text.magnifyingglass",
                tint: LectraColor.warning,
                text: "This document is long, so only the beginning is used for now. Summaries and study tools cover the first part."
            )
        }
    }

    private func banner(icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(LectraTypography.footnoteBold)
                .foregroundStyle(LectraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LectraSpacing.lg)
        .padding(.vertical, LectraSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
    }
}

// MARK: - Shared async result scaffolding

@available(iOS 26.0, *)
private struct GenerateButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(LectraColor.textPrimary)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(isLoading ? "Thinking…" : title)
            }
        }
        .buttonStyle(LectraPrimaryButtonStyle(disabled: isLoading))
        .disabled(isLoading)
    }
}

@available(iOS 26.0, *)
private struct InsightErrorView: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(LectraColor.warning)
            Text(message)
                .font(LectraTypography.body)
                .foregroundStyle(LectraColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LectraSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous)
                .fill(LectraColor.warning.opacity(0.10))
        )
    }
}

// MARK: - Summary tab

@available(iOS 26.0, *)
private struct SummaryTabView: View {
    @ObservedObject var store: InsightsStore
    let pageText: String

    var body: some View {
        VStack(alignment: .leading, spacing: LectraSpacing.md) {
            Picker("Scope", selection: $store.summaryScope) {
                Text("Whole document").tag(DocumentSummarizer.Scope.document)
                Text("This page").tag(DocumentSummarizer.Scope.page)
            }
            .pickerStyle(.segmented)

            GenerateButton(title: store.summary.isEmpty ? "Summarize" : "Resummarize",
                           isLoading: store.summaryLoading) {
                Task { await store.summarize(pageText: pageText) }
            }

            if let error = store.summaryError { InsightErrorView(message: error) }

            if !store.summary.isEmpty {
                Text(LocalizedStringKey(store.summary))
                    .font(LectraTypography.body)
                    .foregroundStyle(LectraColor.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(LectraSpacing.md)
                    .lectraCard()
            } else if !store.summaryLoading {
                EmptyHint(text: "Generate a clear, study-ready summary of \(store.summaryScope == .page ? "the current page" : "this document").")
            }
        }
    }
}

// MARK: - Ask tab

@available(iOS 26.0, *)
private struct AskTabView: View {
    @ObservedObject var store: InsightsStore
    @State private var question = ""

    var body: some View {
        VStack(alignment: .leading, spacing: LectraSpacing.md) {
            HStack(spacing: LectraSpacing.sm) {
                TextField("Ask about this document…", text: $question, axis: .vertical)
                    .font(LectraTypography.body)
                    .foregroundStyle(LectraColor.textPrimary)
                    .padding(LectraSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                            .fill(LectraColor.surfaceFloating.opacity(0.85))
                            .overlay(
                                RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
                            )
                    )
                Button {
                    let q = question
                    question = ""
                    Task { await store.ask(q) }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline)
                        .foregroundStyle(LectraColor.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(LectraColor.accent))
                }
                .buttonStyle(.plain)
                .disabled(store.askLoading || question.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(store.askLoading || question.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }

            if let error = store.askError { InsightErrorView(message: error) }
            if store.askLoading { ProgressView().tint(LectraColor.accentSoft).frame(maxWidth: .infinity) }

            if store.askTurns.isEmpty && !store.askLoading {
                EmptyHint(text: "Ask anything — definitions, explanations, or “what's the main argument here?” Answers come only from this document.")
            }

            ForEach(store.askTurns.reversed()) { turn in
                VStack(alignment: .leading, spacing: 6) {
                    Text(turn.question)
                        .font(LectraTypography.bodyEmphasis)
                        .foregroundStyle(LectraColor.accentSoft)
                    Text(LocalizedStringKey(turn.answer))
                        .font(LectraTypography.body)
                        .foregroundStyle(LectraColor.textPrimary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(LectraSpacing.md)
                .lectraCard()
            }
        }
    }
}

// MARK: - Flashcards tab

@available(iOS 26.0, *)
private struct FlashcardsTabView: View {
    @ObservedObject var store: InsightsStore

    var body: some View {
        VStack(alignment: .leading, spacing: LectraSpacing.md) {
            GenerateButton(title: store.cards.isEmpty ? "Generate Flashcards" : "Regenerate",
                           isLoading: store.cardsLoading) {
                Task { await store.makeFlashcards() }
            }
            if let error = store.cardsError { InsightErrorView(message: error) }
            if store.cards.isEmpty && !store.cardsLoading {
                EmptyHint(text: "Turn this document into a deck of flashcards you can flip through.")
            }
            ForEach(store.cards) { card in FlashcardView(card: card) }
        }
    }
}

@available(iOS 26.0, *)
private struct FlashcardView: View {
    let card: LectraFlashcard
    @State private var flipped = false

    var body: some View {
        Button {
            LectraHaptics.tap()
            withAnimation(LectraMotion.bounce) { flipped.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(flipped ? "ANSWER" : "QUESTION")
                    .font(LectraTypography.footnoteBold)
                    .foregroundStyle(flipped ? LectraColor.success : LectraColor.accentSoft)
                Text(flipped ? card.back : card.front)
                    .font(LectraTypography.headlineMedium)
                    .foregroundStyle(LectraColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(LectraSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .lectraCard()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quiz tab

@available(iOS 26.0, *)
private struct QuizTabView: View {
    @ObservedObject var store: InsightsStore

    var body: some View {
        VStack(alignment: .leading, spacing: LectraSpacing.md) {
            GenerateButton(title: store.quiz.isEmpty ? "Generate Quiz" : "Regenerate",
                           isLoading: store.quizLoading) {
                Task { await store.makeQuiz() }
            }
            if let error = store.quizError { InsightErrorView(message: error) }
            if store.quiz.isEmpty && !store.quizLoading {
                EmptyHint(text: "Create a short multiple-choice quiz to test yourself on this material.")
            }
            ForEach(Array(store.quiz.enumerated()), id: \.offset) { index, question in
                QuizQuestionView(index: index, question: question)
            }
        }
    }
}

@available(iOS 26.0, *)
private struct QuizQuestionView: View {
    let index: Int
    let question: LectraQuizQuestion
    @State private var picked: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: LectraSpacing.sm) {
            Text("Question \(index + 1)")
                .font(LectraTypography.footnoteBold)
                .foregroundStyle(LectraColor.accentSoft)
            Text(question.prompt)
                .font(LectraTypography.bodyEmphasis)
                .foregroundStyle(LectraColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
                optionRow(optionIndex: optionIndex, option: option)
            }

            if let picked {
                Text(picked == question.correctIndex ? "Correct — \(question.explanation)" : "Not quite. \(question.explanation)")
                    .font(LectraTypography.captionMedium)
                    .foregroundStyle(picked == question.correctIndex ? LectraColor.success : LectraColor.textSecondary)
                    .padding(.top, 4)
            }
        }
        .padding(LectraSpacing.md)
        .lectraCard()
    }

    @ViewBuilder
    private func optionRow(optionIndex: Int, option: String) -> some View {
        let isAnswered = picked != nil
        let isCorrect = optionIndex == question.correctIndex
        let isPicked = picked == optionIndex
        let fill: Color = {
            guard isAnswered else { return LectraColor.surfaceFloating.opacity(0.7) }
            if isCorrect { return LectraColor.success.opacity(0.18) }
            if isPicked { return LectraColor.accent.opacity(0.18) }
            return LectraColor.surfaceFloating.opacity(0.7)
        }()
        Button {
            guard picked == nil else { return }
            LectraHaptics.selection()
            withAnimation(LectraMotion.quick) { picked = optionIndex }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isAnswered && isCorrect ? "checkmark.circle.fill"
                      : (isPicked ? "xmark.circle.fill" : "circle"))
                    .foregroundStyle(isAnswered && isCorrect ? LectraColor.success
                                     : (isPicked ? LectraColor.accent : LectraColor.textTertiary))
                Text(option)
                    .font(LectraTypography.body)
                    .foregroundStyle(LectraColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, LectraSpacing.md)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous).fill(fill)
            )
        }
        .buttonStyle(.plain)
        .disabled(picked != nil)
    }
}

// MARK: - Small shared pieces

private struct EmptyHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(LectraTypography.body)
            .foregroundStyle(LectraColor.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, LectraSpacing.sm)
    }
}
