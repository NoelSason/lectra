//
//  NotebookView.swift
//  Lectra
//
//  The in-app notebook editor: a Jupyter-like surface where cells run real
//  Python on-device via PyodideRuntime. Add / edit / reorder / delete cells,
//  run them (state persists across cells, like a kernel), and share the result
//  as a valid `.ipynb`. Styled with Lectra design tokens.
//

import SwiftUI

struct NotebookView: View {
    @StateObject private var document: NotebookDocument
    @StateObject private var runtime = PyodideRuntime()
    @ObservedObject private var store = NotebookStore.shared

    @Environment(\.dismiss) private var dismiss
    @State private var sharePayload: SharePayload?

    init(document: NotebookDocument) {
        _document = StateObject(wrappedValue: document)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: LectraSpacing.md) {
                    titleField
                    ForEach(document.cells) { cell in
                        NotebookCellView(
                            cell: cell,
                            onRun: { run(cell) },
                            onDelete: { withAnimation(LectraMotion.quick) { document.delete(cell) } },
                            onMoveUp: { withAnimation(LectraMotion.quick) { document.move(cell, by: -1) } },
                            onMoveDown: { withAnimation(LectraMotion.quick) { document.move(cell, by: 1) } },
                            onChangeType: { document.changeType(cell, to: $0) })
                    }
                    addCellBar
                }
                .padding(LectraSpacing.lg)
            }
            .background(LectraGradient.appBackdrop.ignoresSafeArea())
            .navigationTitle("Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbarBackground(LectraColor.surfaceOverlay, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { kernelBar }
        }
        .preferredColorScheme(.dark)
        .task {
            store.save(document)
            try? await runtime.start()
        }
        .onDisappear {
            store.save(document)
            runtime.shutdown()
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheetView(items: payload.urls)
        }
    }

    // MARK: Header

    private var titleField: some View {
        TextField("Notebook title", text: $document.title)
            .font(LectraTypography.title)
            .foregroundStyle(LectraColor.textPrimary)
            .textFieldStyle(.plain)
            .padding(.bottom, LectraSpacing.xs)
    }

    private var kernelBar: some View {
        HStack(spacing: 8) {
            switch runtime.status {
            case .ready:
                Circle().fill(LectraColor.success).frame(width: 8, height: 8)
                Text("Python ready").foregroundStyle(LectraColor.textSecondary)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(LectraColor.warning)
                Text("Python unavailable").foregroundStyle(LectraColor.textSecondary)
            default:
                ProgressView().controlSize(.mini).tint(LectraColor.accentSoft)
                Text("Starting Python…").foregroundStyle(LectraColor.textSecondary)
            }
            Spacer()
        }
        .font(LectraTypography.footnoteBold)
        .padding(.horizontal, LectraSpacing.lg)
        .padding(.vertical, LectraSpacing.sm)
        .background(LectraColor.surfaceOverlay.opacity(0.95))
        .overlay(alignment: .bottom) {
            Rectangle().fill(LectraColor.edgeStroke).frame(height: 1)
        }
    }

    private var addCellBar: some View {
        HStack(spacing: LectraSpacing.sm) {
            addButton(title: "Code", icon: "chevron.left.forwardslash.chevron.right") {
                document.addCell(.code, after: document.cells.last)
            }
            addButton(title: "Markdown", icon: "text.alignleft") {
                document.addCell(.markdown, after: document.cells.last)
            }
        }
        .padding(.top, LectraSpacing.sm)
    }

    private func addButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            LectraHaptics.tap()
            withAnimation(LectraMotion.quick) { action() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(LectraTypography.footnoteBold)
            .foregroundStyle(LectraColor.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                    .stroke(LectraColor.edgeStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        }
        .buttonStyle(.plain)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                LectraHaptics.tap()
                dismiss()
            } label: {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(LectraColor.textTertiary)
            }
            .accessibilityLabel("Close")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { runAll() } label: {
                Image(systemName: "play.fill").foregroundStyle(LectraColor.accentSoft)
            }
            .accessibilityLabel("Run all cells")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { share() } label: { Label("Share Notebook (.ipynb)", systemImage: "square.and.arrow.up") }
                Button { restart() } label: { Label("Restart Kernel", systemImage: "arrow.clockwise") }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(LectraColor.textSecondary)
            }
        }
    }

    // MARK: Actions

    private func run(_ cell: NotebookCell) {
        guard cell.type == .code, !cell.isRunning else { return }
        cell.isRunning = true
        Task {
            let result = await runtime.run(cell.source, cellID: cell.id)
            cell.output = CellOutput(result)
            cell.executionCount = document.nextExecutionCount()
            cell.isRunning = false
            if result.error != nil { LectraHaptics.warning() } else { LectraHaptics.success() }
            store.save(document)
        }
    }

    private func runAll() {
        LectraHaptics.tap()
        Task {
            for cell in document.cells where cell.type == .code {
                cell.isRunning = true
                let result = await runtime.run(cell.source, cellID: cell.id)
                cell.output = CellOutput(result)
                cell.executionCount = document.nextExecutionCount()
                cell.isRunning = false
            }
            store.save(document)
        }
    }

    private func restart() {
        LectraHaptics.tap()
        runtime.restart()
    }

    private func share() {
        guard let url = store.exportURL(for: document) else { return }
        LectraHaptics.tap()
        sharePayload = SharePayload(urls: [url])
    }
}
