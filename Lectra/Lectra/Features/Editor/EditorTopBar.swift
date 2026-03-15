import SwiftUI

struct EditorSyncStatusDescriptor {
    let title: String
    let color: Color
    var action: (() -> Void)? = nil
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
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(backgroundView)
    }

    private var expandedLayout: some View {
        HStack(spacing: 12) {
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
        HStack(spacing: 12) {
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
        Button(action: onBack) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                Text("Vault")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
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
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.13))
                    )
                    .frame(maxWidth: 380, minHeight: LectraSizing.minHitTarget)
                    .focused(isTitleFocused)
                    .submitLabel(.done)
                    .onSubmit(onCommitRename)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .accessibilityIdentifier("editor.titleField")
            } else {
                Button(action: onBeginRename) {
                    VStack(spacing: 2) {
                        Text(documentTitle)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .foregroundColor(.white)
                        Text("Tap title to rename")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
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
        .accessibilityIdentifier("editor.more")
    }

    private var canvascopeButton: some View {
        Button(action: onExportCanvascope) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 15, weight: .bold))
                Text("Canvascope")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .frame(height: LectraSizing.minHitTarget)
            .background(buttonBackground)
        }
        .buttonStyle(.plain)
        .disabled(isSaving || isExportingToCanvascope)
        .accessibilityIdentifier("editor.canvascope")
    }

    private var gradescopeButton: some View {
        Button(action: onShowGradescope) {
            HStack(spacing: 6) {
                Image(systemName: "graduationcap")
                    .font(.system(size: 15, weight: .bold))
                Text("Gradescope")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .frame(height: LectraSizing.minHitTarget)
            .background(buttonBackground)
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
        Button("Search This PDF", systemImage: "magnifyingglass", action: onShowSearch)

        if hasOutline {
            Button("Document Outline", systemImage: "list.bullet.indent", action: onShowOutline)
        }

        Divider()

        Menu("Handedness") {
            ForEach(EditorHandedness.allCases, id: \.self) { value in
                Button(value == .left ? "Left-Handed" : "Right-Handed") {
                    onSetHandedness(value)
                }
            }
        }

        Menu("Pencil Squeeze") {
            ForEach(PencilSqueezeAction.allCases, id: \.self) { action in
                Button(label(for: action)) {
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
        Button(action: action) {
            iconButtonLabel(symbol: symbol)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func iconButtonLabel(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
            .background(buttonBackground)
    }

    private func statusChip(title: String, color: Color, action: (() -> Void)?) -> some View {
        Group {
            if let action {
                Button(action: action) {
                    statusChipLabel(title: title, color: color)
                }
                .buttonStyle(.plain)
            } else {
                statusChipLabel(title: title, color: color)
            }
        }
    }

    private func statusChipLabel(title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(color)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(color.opacity(0.13))
            .clipShape(Capsule())
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
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.12))
    }

    private var backgroundView: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color(hex: 0x1B2A48),
                    Color(hex: 0x101A2D)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LectraGradient.spotlight.opacity(0.28)
            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 1)
        }
        .ignoresSafeArea(edges: .top)
    }
}
