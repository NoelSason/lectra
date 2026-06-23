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
    @FocusState private var titleFocused: Bool

    /// Called when the title is committed, so the library card can be renamed.
    private let onTitleChange: ((String) -> Void)?

    init(document: NotebookDocument, onTitleChange: ((String) -> Void)? = nil) {
        _document = StateObject(wrappedValue: document)
        self.onTitleChange = onTitleChange
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
                            onRunSelectBelow: { runSelectBelow(cell) },
                            onRunInsertBelow: { runInsertBelow(cell) },
                            onDelete: { withAnimation(LectraMotion.quick) { document.delete(cell) } },
                            onMoveUp: { withAnimation(LectraMotion.quick) { document.move(cell, by: -1) } },
                            onMoveDown: { withAnimation(LectraMotion.quick) { document.move(cell, by: 1) } },
                            onChangeType: { document.changeType(cell, to: $0) },
                            isFocused: document.focusedCellID == cell.id,
                            onFocus: { document.focusedCellID = cell.id })
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
            commitTitle()
            store.save(document)
            runtime.shutdown()
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheetView(items: payload.urls)
        }
    }

    // MARK: Header

    private var titleField: some View {
        HStack(spacing: LectraSpacing.sm) {
            TextField("Notebook title", text: $document.title)
                .font(LectraTypography.title)
                .foregroundStyle(LectraColor.textPrimary)
                .textFieldStyle(.plain)
                .focused($titleFocused)
                .submitLabel(.done)
                .onSubmit { commitTitle() }
            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(titleFocused ? LectraColor.accentSoft : LectraColor.textTertiary)
        }
        .padding(.horizontal, LectraSpacing.md)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                .fill(LectraColor.surfaceFloating.opacity(titleFocused ? 0.85 : 0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                        .stroke(titleFocused ? LectraColor.accent.opacity(0.5) : LectraColor.edgeStroke, lineWidth: 1))
        )
        .contentShape(Rectangle())
        .onTapGesture { titleFocused = true }
    }

    private func commitTitle() {
        let trimmed = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { document.title = "Untitled Notebook" }
        store.save(document)
        onTitleChange?(document.title)
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
            Text("⇧⏎ run")
                .foregroundStyle(LectraColor.textTertiary)
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

    /// Shift+Enter: run, then focus the next code cell (creating one at the end
    /// if there isn't a next code cell).
    private func runSelectBelow(_ cell: NotebookCell) {
        run(cell)
        if let next = document.nextCodeCell(after: cell) {
            document.focusedCellID = next.id
        } else {
            let new = document.addCell(.code, after: document.cells.last)
            document.focusedCellID = new.id
        }
    }

    /// Option+Enter: run, then insert and focus a new code cell directly below.
    private func runInsertBelow(_ cell: NotebookCell) {
        run(cell)
        let new = document.addCell(.code, after: cell)
        document.focusedCellID = new.id
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
