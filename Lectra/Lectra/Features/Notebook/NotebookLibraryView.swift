//
//  NotebookLibraryView.swift
//  Lectra
//
//  Lists saved notebooks and opens or creates them. Reachable from the library
//  so notebooks can be reopened later, and so a blank Python notebook can be
//  created on any device — notebook execution doesn't depend on Apple
//  Intelligence (only study-aid seeding does).
//

import SwiftUI

struct NotebookLibraryView: View {
    @ObservedObject private var store = NotebookStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var openDoc: NotebookDocument?

    var body: some View {
        NavigationStack {
            Group {
                if store.summaries.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(LectraGradient.appBackdrop.ignoresSafeArea())
            .navigationTitle("Notebooks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3).foregroundStyle(LectraColor.textTertiary)
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { create() } label: {
                        Image(systemName: "square.and.pencil").foregroundStyle(LectraColor.accentSoft)
                    }
                    .accessibilityLabel("New notebook")
                }
            }
            .toolbarBackground(LectraColor.surfaceOverlay, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear { store.refresh() }
        .fullScreenCover(item: $openDoc) { doc in
            NotebookView(document: doc)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: LectraSpacing.sm) {
                ForEach(store.summaries) { summary in
                    Button { open(summary) } label: { row(summary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(LectraSpacing.lg)
        }
    }

    private func row(_ summary: NotebookSummary) -> some View {
        HStack(spacing: LectraSpacing.md) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 18))
                .foregroundStyle(LectraColor.accentSoft)
                .frame(width: 40, height: 40)
                .background(Circle().fill(LectraColor.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(LectraTypography.bodyEmphasis)
                    .foregroundStyle(LectraColor.textPrimary)
                Text(summary.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(LectraTypography.footnote)
                    .foregroundStyle(LectraColor.textTertiary)
            }
            Spacer()
            Button {
                LectraHaptics.tap()
                store.delete(id: summary.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(LectraColor.textTertiary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(LectraSpacing.md)
        .lectraCard()
    }

    private var emptyState: some View {
        VStack(spacing: LectraSpacing.md) {
            Spacer()
            Image(systemName: "book.closed")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(LectraColor.accentSoft)
            Text("No notebooks yet")
                .font(LectraTypography.title)
                .foregroundStyle(LectraColor.textPrimary)
            Text("Create a Python notebook, or make one from a document's study tools in Intelligence.")
                .font(LectraTypography.body)
                .foregroundStyle(LectraColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LectraSpacing.xl)
            Button { create() } label: { Label("New Notebook", systemImage: "square.and.pencil") }
                .buttonStyle(LectraSecondaryButtonStyle())
                .padding(.top, LectraSpacing.sm)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func open(_ summary: NotebookSummary) {
        LectraHaptics.tap()
        openDoc = store.load(id: summary.id)
    }

    private func create() {
        LectraHaptics.tap()
        let doc = store.newEmpty()
        store.save(doc)
        openDoc = doc
    }
}
