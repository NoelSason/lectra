import SwiftUI
import UIKit

struct EditorSyncStatusDescriptor: Equatable {
    let title: String
    let color: Color
    var action: (() -> Void)? = nil

    static func == (lhs: EditorSyncStatusDescriptor, rhs: EditorSyncStatusDescriptor) -> Bool {
        lhs.title == rhs.title
    }
}

struct EditorTopBar: View {
    let documentTitle: String
    @Binding var titleDraft: String
    let isRenamingTitle: Bool
    let isReadMode: Bool
    let isSaving: Bool
    let isExportingToCanvascope: Bool
    let canUndo: Bool
    let canRedo: Bool
    let syncStatus: EditorSyncStatusDescriptor?
    let hasOutline: Bool
    let handedness: EditorHandedness
    let squeezeAction: PencilSqueezeAction
    let onBack: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onBeginRename: () -> Void
    let onCommitRename: () -> Void
    let onShowSearch: () -> Void
    let onShowOutline: () -> Void
    let onSetHandedness: (EditorHandedness) -> Void
    let onSetSqueezeAction: (PencilSqueezeAction) -> Void
    let onExportCanvascope: () -> Void
    let onShowGradescope: () -> Void
    let onShare: () -> Void
    var isTitleFocused: FocusState<Bool>.Binding

    var body: some View {
        ViewThatFits(in: .horizontal) {
            expandedLayout
            compactLayout
        }
        .padding(.horizontal, LectraSpacing.lg)
        .padding(.top, LectraSpacing.sm)
        .padding(.bottom, LectraSpacing.sm)
        .background(backgroundView)
        .onChange(of: syncStatus?.title) { _, newTitle in
            if let newTitle {
                postAccessibilityAnnouncement(newTitle)
            }
        }
    }

    private var expandedLayout: some View {
        HStack(spacing: 10) {
            backButton
            undoButton
            redoButton
            titleSection
            Spacer(minLength: 4)
            statusSection
            settingsMenu
            canvascopeButton
            gradescopeButton
            shareButton
        }
    }

    private var compactLayout: some View {
        HStack(spacing: 10) {
            backButton
            undoButton
            redoButton
            titleSection
            Spacer(minLength: 4)
            statusSection
            compactOverflowMenu
        }
    }

    private var backButton: some View {
        Button {
            LectraHaptics.selection()
            onBack()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(LectraTypography.headline)
                Text("Library")
                    .font(LectraTypography.bodyEmphasis)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 13)
            .frame(height: LectraSizing.minHitTarget)
            .background(buttonBackground)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityIdentifier("editor.back")
    }

    private var undoButton: some View {
        iconButton(symbol: "arrow.uturn.backward", title: "Undo", action: onUndo)
            .disabled(!canUndo)
            .keyboardShortcut("z", modifiers: [.command])
            .accessibilityIdentifier("editor.undo")
    }

    private var redoButton: some View {
        iconButton(symbol: "arrow.uturn.forward", title: "Redo", action: onRedo)
            .disabled(!canRedo)
            .keyboardShortcut("Z", modifiers: [.command, .shift])
            .accessibilityIdentifier("editor.redo")
    }

    private var titleSection: some View {
        Group {
            if isRenamingTitle {
                TextField("Document title", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(LectraTypography.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LectraSpacing.md)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                            .fill(Color.white.opacity(LectraOpacity.subtle))
                            .overlay(
                                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                                    .stroke(Color.white.opacity(LectraOpacity.medium), lineWidth: 1)
                            )
                    )
                    .frame(maxWidth: 380, minHeight: LectraSizing.minHitTarget)
                    .focused(isTitleFocused)
                    .submitLabel(.done)
                    .onSubmit(onCommitRename)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .accessibilityIdentifier("editor.titleField")
            } else {
                Button {
                    LectraHaptics.tap()
                    onBeginRename()
                } label: {
                    VStack(spacing: 3) {
                        Text(documentTitle)
                            .font(LectraTypography.headline)
                            .lineLimit(1)
                            .foregroundColor(.white)
                        Text(isReadMode ? "Read mode ready for navigation" : "Annotate with Apple Pencil")
                            .font(LectraTypography.footnote)
                            .foregroundColor(.white.opacity(0.74))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: LectraSizing.minHitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .accessibilityIdentifier("editor.titleButton")
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var statusSection: some View {
        HStack(spacing: 8) {
            if isReadMode {
                statusChip(
                    title: "Read Mode",
                    color: LectraColor.accentCool,
                    action: nil
                )
            }

            if let syncStatus {
                statusChip(
                    title: syncStatus.title,
                    color: syncStatus.color,
                    action: syncStatus.action
                )
            }
        }
    }

    private var settingsMenu: some View {
        Menu {
            utilityActions
        } label: {
            iconButtonLabel(symbol: "slider.horizontal.3")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("editor.settings")
    }

    private var compactOverflowMenu: some View {
        Menu {
            utilityActions
            Divider()
            exportActions
        } label: {
            iconButtonLabel(symbol: "ellipsis.circle")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More actions")
        .accessibilityIdentifier("editor.more")
    }

    private var canvascopeButton: some View {
        Button {
            LectraHaptics.tap()
            onExportCanvascope()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.app")
                    .font(LectraTypography.bodyEmphasis)
                Text("Canvascope")
                    .font(LectraTypography.caption)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .frame(height: LectraSizing.minHitTarget)
            .background(integrationBackground(tint: LectraColor.canvasTint))
        }
        .buttonStyle(.plain)
        .disabled(isSaving || isExportingToCanvascope)
        .accessibilityIdentifier("editor.canvascope")
    }

    private var gradescopeButton: some View {
        Button {
            LectraHaptics.tap()
            onShowGradescope()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "graduationcap")
                    .font(LectraTypography.bodyEmphasis)
                Text("Gradescope")
                    .font(LectraTypography.caption)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .frame(height: LectraSizing.minHitTarget)
            .background(integrationBackground(tint: LectraColor.gradescopeTint))
        }
        .buttonStyle(.plain)
        .disabled(isSaving || isExportingToCanvascope)
        .accessibilityIdentifier("editor.gradescope")
    }

    private var shareButton: some View {
        iconButton(symbol: "square.and.arrow.up", title: "Share", action: onShare)
            .disabled(isSaving || isExportingToCanvascope)
            .accessibilityIdentifier("editor.share")
    }

    @ViewBuilder
    private var utilityActions: some View {
        Button("Search This PDF", systemImage: "magnifyingglass") {
            LectraHaptics.selection()
            onShowSearch()
        }

        if hasOutline {
            Button("Document Outline", systemImage: "list.bullet.indent") {
                LectraHaptics.selection()
                onShowOutline()
            }
        }

        Divider()

        Menu("Handedness") {
            ForEach(EditorHandedness.allCases, id: \.self) { value in
                Button(value == .left ? "Left-Handed" : "Right-Handed") {
                    LectraHaptics.selection()
                    onSetHandedness(value)
                }
            }
        }

        Menu("Pencil Squeeze") {
            ForEach(PencilSqueezeAction.allCases, id: \.self) { action in
                Button(label(for: action)) {
                    LectraHaptics.selection()
                    onSetSqueezeAction(action)
                }
            }
        }
    }

    @ViewBuilder
    private var exportActions: some View {
        Button("Send to Canvascope", systemImage: "arrow.up.forward.app", action: onExportCanvascope)
            .disabled(isSaving || isExportingToCanvascope)
        Button("Submit to Gradescope", systemImage: "graduationcap", action: onShowGradescope)
            .disabled(isSaving || isExportingToCanvascope)
        Button("Share PDF", systemImage: "square.and.arrow.up", action: onShare)
            .disabled(isSaving || isExportingToCanvascope)
    }

    private func iconButton(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button {
            LectraHaptics.tap()
            action()
        } label: {
            iconButtonLabel(symbol: symbol)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func iconButtonLabel(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(LectraTypography.headline)
            .foregroundColor(.white)
            .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
            .background(buttonBackground)
            .clipShape(RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous))
    }

    private func statusChip(title: String, color: Color, action: (() -> Void)?) -> some View {
        Group {
            if let action {
                Button {
                    LectraHaptics.selection()
                    action()
                } label: {
                    statusChipLabel(title: title, color: color)
                }
                .buttonStyle(.plain)
            } else {
                statusChipLabel(title: title, color: color)
            }
        }
    }

    private func statusChipLabel(title: String, color: Color) -> some View {
        LectraStatusBadge(title: title, color: color, size: .large)
    }

    private func label(for action: PencilSqueezeAction) -> String {
        switch action {
        case .togglePenEraser:
            return "Toggle Pen and Eraser"
        case .undo:
            return "Undo"
        case .redo:
            return "Redo"
        }
    }

    private var buttonBackground: some View {
        RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
            .fill(Color.white.opacity(LectraOpacity.subtle))
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                    .stroke(Color.white.opacity(LectraOpacity.medium), lineWidth: 1)
            )
    }

    private func integrationBackground(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
            .fill(tint.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                    .stroke(tint.opacity(0.35), lineWidth: 1)
            )
    }

    private var backgroundView: some View {
        ZStack {
            Rectangle()
                .fill(LectraColor.surfaceElevated.opacity(0.96))
            LectraGradient.spotlight.opacity(0.18)
            Rectangle()
                .fill(Color.white.opacity(LectraOpacity.medium))
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(edges: .top)
    }
}
