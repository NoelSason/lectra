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
    /// Width available to the bar, used to decide whether there's room to truly
    /// center the title (landscape) or whether it should flow inline (portrait).
    let barWidth: CGFloat
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
    let onShare: () -> Void
    let onShowIntelligence: () -> Void
    var isTitleFocused: FocusState<Bool>.Binding

    var body: some View {
        ViewThatFits(in: .horizontal) {
            expandedLayout
            compactLayout
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 9)
        .background(backgroundView)
        .onChange(of: syncStatus?.title) { _, newTitle in
            if let newTitle {
                postAccessibilityAnnouncement(newTitle)
            }
        }
    }

    private var expandedLayout: some View {
        HStack(spacing: 10) {
            backButton(showsLabel: true)
            undoButton
            redoButton
            titleSection
            Spacer(minLength: 4)
            statusSection
            settingsMenu
            intelligenceButton
            canvascopeButton
            shareButton
        }
    }

    // iPhone uses the compact layout in both orientations. A truly centered
    // title only fits when the bar is wide (landscape); in the narrow portrait
    // bar there isn't room for back+undo+redo, a centered title, and the
    // trailing controls without overlap, so the title flows inline instead.
    @ViewBuilder
    private var compactLayout: some View {
        if barWidth >= 600 {
            wideCompactLayout
        } else {
            narrowCompactLayout
        }
    }

    // Wide (landscape): title centered across the full bar. It renders behind
    // the edge controls and is only tappable in the clear central band; the
    // horizontal padding keeps it clear of the leading/trailing clusters.
    private var wideCompactLayout: some View {
        ZStack {
            titleSection
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 160)
            HStack(spacing: 10) {
                backButton(showsLabel: false)
                undoButton
                redoButton
                Spacer(minLength: 8)
                statusSection
                compactOverflowMenu
            }
        }
    }

    // Narrow (portrait): inline flow so nothing overlaps; the flexible title
    // centers in the space between the button clusters and truncates as needed.
    private var narrowCompactLayout: some View {
        HStack(spacing: 10) {
            backButton(showsLabel: false)
            undoButton
            redoButton
            titleSection
            Spacer(minLength: 4)
            statusSection
            compactOverflowMenu
        }
    }

    private func backButton(showsLabel: Bool) -> some View {
        Button {
            LectraHaptics.selection()
            onBack()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.left")
                    .font(LectraTypography.headline)
                Image("LaunchMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 19, height: 19)
                    .accessibilityHidden(true)
                if showsLabel {
                    Text("Workspace")
                        .font(LectraTypography.bodyEmphasis)
                }
            }
            .foregroundColor(LectraColor.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: LectraSizing.minHitTarget)
            .background(buttonBackground)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel("Workspace")
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
                            .fill(LectraColor.surfaceFloating.opacity(0.92))
                            .overlay(
                                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
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
                            .foregroundColor(LectraColor.textPrimary)
                        Text(isReadMode ? "Touch navigation" : "Pencil markup active")
                            .font(LectraTypography.footnote)
                            .foregroundColor(LectraColor.textTertiary)
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

    private var intelligenceButton: some View {
        Button {
            LectraHaptics.tap()
            onShowIntelligence()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(LectraTypography.bodyEmphasis)
                Text("Intelligence")
                    .font(LectraTypography.caption)
            }
            .foregroundColor(LectraColor.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: LectraSizing.minHitTarget)
            .background(integrationBackground(tint: LectraColor.accent))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("editor.intelligence")
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
            .foregroundColor(LectraColor.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: LectraSizing.minHitTarget)
            .background(integrationBackground(tint: LectraColor.accentSoft))
        }
        .buttonStyle(.plain)
        .disabled(isSaving || isExportingToCanvascope)
        .accessibilityLabel("Export to Canvascope")
        .accessibilityIdentifier("editor.canvascope")
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
        Button("Document Intelligence", systemImage: "sparkles", action: onShowIntelligence)
        Button("Export to Canvascope", systemImage: "arrow.up.forward.app", action: onExportCanvascope)
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
            .foregroundColor(LectraColor.textSecondary)
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
            .fill(LectraColor.surfaceFloating.opacity(0.88))
            .background(
                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
    }

    private func integrationBackground(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
            .fill(tint.opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                LectraColor.paper.opacity(0.06),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                    .stroke(tint.opacity(0.50), lineWidth: 1)
            )
    }

    private var backgroundView: some View {
        ZStack {
            Rectangle()
                .fill(LectraColor.surfaceOverlay.opacity(0.96))
            LinearGradient(
                colors: [
                    LectraColor.paper.opacity(0.05),
                    LectraColor.accent.opacity(0.10),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Rectangle()
                .fill(LectraColor.edgeStroke)
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(edges: .top)
    }
}
