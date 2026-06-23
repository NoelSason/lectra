//
//  CrossDocumentAskSheet.swift
//  Lectra
//
//  Ask questions across several selected documents at once. Presented from the
//  library's selection mode when two or more documents are chosen. The heavy
//  lifting (combining text, routing to the larger context) lives in
//  `CrossDocumentAsk`; this view is the chat surface around it.
//

import SwiftUI
import Combine

/// Input passed from the library: the documents to reason across. Identifiable
/// so the library can present the sheet with `.sheet(item:)`.
struct CrossAskInput: Identifiable {
    let id = UUID()
    let documents: [Document]

    struct Document: Identifiable {
        let id: UUID
        let title: String
        let url: URL
    }
}

struct CrossDocumentAskSheet: View {
    let input: CrossAskInput

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if #available(iOS 26.0, *), LectraIntelligence.isReady {
                    CrossAskContentView(documents: input.documents)
                } else {
                    CrossAskUnavailableView(status: LectraIntelligence.status)
                }
            }
            .background(LectraGradient.appBackdrop.ignoresSafeArea())
            .navigationTitle("Ask across documents")
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

private struct CrossAskUnavailableView: View {
    let status: LectraIntelligenceStatus

    var body: some View {
        VStack(spacing: LectraSpacing.md) {
            Image(systemName: status.systemImage)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(LectraColor.accentSoft)
            Text(status.headline)
                .font(LectraTypography.title)
                .foregroundStyle(LectraColor.textPrimary)
            Text(status.message)
                .font(LectraTypography.body)
                .foregroundStyle(LectraColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LectraSpacing.xl)
            Spacer()
        }
        .padding(.top, LectraSpacing.xxl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Store

@available(iOS 26.0, *)
@MainActor
private final class CrossAskStore: ObservableObject {
    struct Turn: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
    }

    private let engine = CrossDocumentAsk()

    @Published var isPreparing = true
    @Published var turns: [Turn] = []
    @Published var asking = false
    @Published var error: String?
    /// Total characters loaded across all documents, for the context cue.
    @Published var totalChars = 0

    func prepare(documents: [CrossAskInput.Document]) async {
        guard isPreparing else { return }
        let sources = await Task.detached(priority: .userInitiated) {
            documents.map { doc in
                CrossDocumentAsk.Source(
                    title: doc.title,
                    text: PDFTextExtractor.fullText(at: doc.url)
                )
            }
        }.value
        totalChars = sources.reduce(0) { $0 + $1.text.count }
        engine.begin(sources: sources)
        isPreparing = false
    }

    var contextHandling: LectraModelRouter.ContextHandling {
        LectraModelRouter.shared.contextHandling(forChars: totalChars)
    }

    func ask(_ question: String) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        asking = true
        error = nil
        defer { asking = false }
        do {
            let answer = try await engine.ask(q)
            turns.append(Turn(question: q, answer: answer))
        } catch {
            self.error = "Couldn't answer that. \(error.localizedDescription)"
        }
    }
}

// MARK: - Content

@available(iOS 26.0, *)
private struct CrossAskContentView: View {
    let documents: [CrossAskInput.Document]

    @StateObject private var store = CrossAskStore()
    @State private var question = ""

    var body: some View {
        VStack(spacing: 0) {
            documentChips
            Divider().overlay(LectraColor.edgeStroke)
            if !store.isPreparing {
                ContextCue(handling: store.contextHandling, count: documents.count)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: LectraSpacing.md) {
                    if store.isPreparing {
                        HStack(spacing: 8) {
                            ProgressView().tint(LectraColor.accentSoft)
                            Text("Reading your documents…")
                                .font(LectraTypography.body)
                                .foregroundStyle(LectraColor.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let error = store.error { errorBox(error) }

                    if store.turns.isEmpty && !store.isPreparing && !store.asking {
                        Text("Ask anything that spans these documents — “compare their main arguments”, “where is X covered?”, or “what do they agree on?”")
                            .font(LectraTypography.body)
                            .foregroundStyle(LectraColor.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if store.asking {
                        ProgressView().tint(LectraColor.accentSoft).frame(maxWidth: .infinity)
                    }

                    ForEach(store.turns.reversed()) { turn in
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
                .padding(LectraSpacing.lg)
            }
            inputBar
        }
        .task { await store.prepare(documents: documents) }
    }

    private var documentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LectraSpacing.sm) {
                ForEach(documents) { doc in
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11, weight: .semibold))
                        Text(doc.title)
                            .font(LectraTypography.footnoteBold)
                            .lineLimit(1)
                    }
                    .foregroundStyle(LectraColor.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(LectraColor.surfaceFloating.opacity(0.8))
                    )
                }
            }
            .padding(.horizontal, LectraSpacing.lg)
            .padding(.vertical, LectraSpacing.sm)
        }
    }

    private var inputBar: some View {
        HStack(spacing: LectraSpacing.sm) {
            TextField("Ask across these documents…", text: $question, axis: .vertical)
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
            .disabled(isSendDisabled)
            .opacity(isSendDisabled ? 0.5 : 1)
        }
        .padding(LectraSpacing.lg)
    }

    private var isSendDisabled: Bool {
        store.isPreparing || store.asking || question.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func errorBox(_ message: String) -> some View {
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

// MARK: - Context cue

@available(iOS 26.0, *)
private struct ContextCue: View {
    let handling: LectraModelRouter.ContextHandling
    let count: Int

    var body: some View {
        switch handling {
        case .standard, .extended:
            cue(
                icon: "sparkles",
                tint: LectraColor.accentSoft,
                text: "Reading across \(count) documents."
            )
        case .truncated:
            cue(
                icon: "doc.text.magnifyingglass",
                tint: LectraColor.warning,
                text: "These documents are long — only the beginning of each is used right now."
            )
        }
    }

    private func cue(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 8) {
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
