//
//  FloatingToolPickerView.swift
//  Lectra
//
//  Lectra instrument rail for Apple Pencil drawing tools.
//

import SwiftUI

struct FloatingToolPickerView: View {
    @Binding var selectedTool: AnnotationTool
    @Binding var selectedColor: AnnotationInkColor
    @Binding var selectedStrokeWidth: CGFloat
    @Binding var highlighterOpacity: CGFloat
    @Binding var selectedEraserMode: EraserMode
    var isVertical: Bool = false

    private let colors: [AnnotationInkColor] = [.yellow, .black, .white, .accent, .blue, .green]

    @State private var penStrokeWidths: [CGFloat] = [0.5, 1.0, 2.0]
    @State private var highlighterStrokeWidths: [CGFloat] = [2.0, 4.0, 7.0]
    @State private var eraserStrokeWidths: [CGFloat] = [1.5, 3.0, 6.0]
    @State private var activeWidthEditorIndex: Int? = nil

    private var strokeWidths: [CGFloat] {
        switch selectedTool {
        case .hand, .lasso:
            return []
        case .highlighter:
            return highlighterStrokeWidths
        case .eraser:
            return eraserStrokeWidths
        case .pen:
            return penStrokeWidths
        }
    }

    private var thicknessRange: ClosedRange<CGFloat>? {
        switch selectedTool {
        case .hand, .lasso:
            return nil
        case .highlighter:
            return 1.0...14.0
        case .eraser:
            return 0.8...12.0
        case .pen:
            return 0.2...6.0
        }
    }

    private var thicknessEditorTitle: String? {
        switch selectedTool {
        case .hand, .lasso:
            return nil
        case .highlighter:
            return "HIGHLIGHTER THICKNESS"
        case .eraser:
            return "ERASER SIZE"
        case .pen:
            return "PEN THICKNESS"
        }
    }

    private var showsThicknessControls: Bool {
        !strokeWidths.isEmpty
    }

    private var showsColorControls: Bool {
        switch selectedTool {
        case .pen, .highlighter, .eraser:
            return true
        case .hand, .lasso:
            return false
        }
    }

    var body: some View {
        let layout = isVertical
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 14))

        return layout {
            toolsSection
            if showsThicknessControls {
                sectionDivider
                strokeWidthSection
            }
            if showsColorControls {
                sectionDivider
                colorSection
            }
        }
        .padding(.horizontal, isVertical ? 10 : 14)
        .padding(.vertical, isVertical ? 12 : 10)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: toolbarCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)

                RoundedRectangle(cornerRadius: toolbarCornerRadius, style: .continuous)
                    .fill(LectraColor.surfaceFloating.opacity(0.92))

                RoundedRectangle(cornerRadius: toolbarCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                LectraColor.paper.opacity(0.07),
                                LectraColor.accent.opacity(0.10),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: toolbarCornerRadius, style: .continuous)
                    .stroke(LectraColor.accent.opacity(0.22), lineWidth: 0.75)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: toolbarCornerRadius, style: .continuous))
        .lectraShadow(LectraElevation.high())
        .overlay(alignment: .top) {
            if let index = activeWidthEditorIndex {
                thicknessEditor(for: index)
                    .offset(y: -92)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(LectraMotion.toolbarDock, value: isVertical)
        .animation(LectraMotion.quick, value: selectedTool)
        .animation(LectraMotion.quick, value: selectedColor)
        .animation(LectraMotion.quick, value: selectedStrokeWidth)
        .animation(LectraMotion.quick, value: activeWidthEditorIndex)
        .onChange(of: selectedTool) { _, _ in
            activeWidthEditorIndex = nil
            clampStrokeWidthToCurrentTool()
        }
        .onAppear {
            clampStrokeWidthToCurrentTool()
        }
    }

    private var toolbarCornerRadius: CGFloat {
        isVertical ? LectraRadius.panel : LectraRadius.sheet
    }

    private var toolsSection: some View {
        let layout = isVertical
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            toolButtons
        }
    }

    private var strokeWidthSection: some View {
        let layout = isVertical
            ? AnyLayout(VStackLayout(spacing: 2))
            : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            strokeWidthButtons
        }
    }

    private var colorSection: some View {
        let layout = isVertical
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            if selectedTool == .eraser {
                eraserModeButtons
            } else {
                colorButtons
            }
        }
    }

    private var sectionDivider: some View {
        Capsule()
            .fill(LectraColor.accent.opacity(0.20))
            .frame(width: isVertical ? 36 : 1, height: isVertical ? 1 : 24)
    }

    private var toolButtons: some View {
        Group {
            ToolButton(
                icon: "hand.raised.fill",
                title: "Read mode",
                isSelected: selectedTool == .hand,
                accessibilityIdentifier: "editor.tool.hand"
            ) {
                withAnimation(LectraMotion.quick) {
                    LectraHaptics.selection()
                    selectedTool = .hand
                    activeWidthEditorIndex = nil
                }
            }
            ToolButton(
                icon: "pencil.tip",
                title: "Pen",
                isSelected: selectedTool == .pen,
                accessibilityIdentifier: "editor.tool.pen"
            ) {
                withAnimation(LectraMotion.quick) {
                    LectraHaptics.selection()
                    selectedTool = .pen
                    activeWidthEditorIndex = nil
                }
            }
            ToolButton(
                icon: "highlighter",
                title: "Highlighter",
                isSelected: selectedTool == .highlighter,
                accessibilityIdentifier: "editor.tool.highlighter"
            ) {
                withAnimation(LectraMotion.quick) {
                    LectraHaptics.selection()
                    if selectedTool != .highlighter, selectedColor == .accent {
                        selectedColor = .yellow
                    }
                    selectedTool = .highlighter
                    activeWidthEditorIndex = nil
                }
            }
            ToolButton(
                icon: "eraser",
                title: "Eraser",
                isSelected: selectedTool == .eraser,
                accessibilityIdentifier: "editor.tool.eraser"
            ) {
                withAnimation(LectraMotion.quick) {
                    LectraHaptics.selection()
                    selectedTool = .eraser
                    activeWidthEditorIndex = nil
                }
            }
            ToolButton(
                icon: "lasso",
                title: "Lasso",
                isSelected: selectedTool == .lasso,
                accessibilityIdentifier: "editor.tool.lasso"
            ) {
                withAnimation(LectraMotion.quick) {
                    LectraHaptics.selection()
                    selectedTool = .lasso
                    activeWidthEditorIndex = nil
                }
            }
        }
    }

    private var strokeWidthButtons: some View {
        Group {
            ForEach(Array(strokeWidths.enumerated()), id: \.offset) { index, width in
                StrokeWidthButton(
                    width: width,
                    title: selectedTool.strokeWidthLabel(for: width),
                    isSelected: abs(selectedStrokeWidth - width) < 0.1
                ) {
                    withAnimation(LectraMotion.quick) {
                        LectraHaptics.tap()
                        selectedStrokeWidth = width
                        activeWidthEditorIndex = activeWidthEditorIndex == index ? nil : index
                    }
                }
            }
        }
    }

    private var colorButtons: some View {
        Group {
            ForEach(colors, id: \.self) { color in
                Button {
                    withAnimation(LectraMotion.quick) {
                        LectraHaptics.tap()
                        selectedColor = color
                    }
                } label: {
                    Circle()
                        .fill(color.swatchColor)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(LectraColor.textPrimary, lineWidth: selectedColor == color ? 2 : 0)
                        )
                        .shadow(color: .black.opacity(0.28), radius: 3, x: 0, y: 1)
                        .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.accessibilityLabel)
                .accessibilityHint("Select ink color")
                .accessibilityValue(selectedColor == color ? "Selected" : "Not selected")
                .accessibilityAddTraits(selectedColor == color ? [.isSelected] : [])
            }
        }
    }

    private var eraserModeButtons: some View {
        Group {
            ForEach(EraserMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(LectraMotion.quick) {
                        LectraHaptics.selection()
                        selectedEraserMode = mode
                    }
                } label: {
                    Text(mode.title)
                        .font(LectraTypography.caption)
                        .foregroundColor(selectedEraserMode == mode ? LectraColor.textPrimary : LectraColor.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                                .fill(
                                    selectedEraserMode == mode
                                    ? LectraColor.accentDark
                                    : LectraColor.surfaceElevated.opacity(0.88)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                                .stroke(selectedEraserMode == mode ? LectraColor.accentSoft.opacity(0.35) : LectraColor.edgeStroke, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.title) eraser")
                .accessibilityValue(selectedEraserMode == mode ? "Selected" : "Not selected")
                .accessibilityAddTraits(selectedEraserMode == mode ? [.isSelected] : [])
            }
        }
    }

    private func thicknessEditor(for index: Int) -> some View {
        let currentWidth = widthValue(at: index)
        let range = thicknessRange ?? 0.2...6.0

        return VStack(alignment: .leading, spacing: 10) {
            Text(thicknessEditorTitle ?? "")
                .font(LectraTypography.caption)
                .foregroundColor(LectraColor.textTertiary)
            HStack(spacing: 12) {
                Text(String(format: "%.1f mm", currentWidth))
                    .font(LectraTypography.titleSmall)
                    .foregroundColor(LectraColor.textPrimary)
                    .frame(width: 78, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { widthValue(at: index) },
                        set: { newValue in
                            updateWidth(at: index, to: newValue)
                        }
                    ),
                    in: range
                )
                .tint(LectraColor.accentSoft)
            }

            if selectedTool == .highlighter {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Opacity")
                            .font(LectraTypography.caption)
                            .foregroundColor(LectraColor.textTertiary)
                        Spacer(minLength: 0)
                        Text("\(Int((highlighterOpacity * 100).rounded()))%")
                            .font(LectraTypography.captionMedium)
                            .foregroundColor(LectraColor.textPrimary)
                    }

                    Slider(value: $highlighterOpacity, in: 0.15...0.75)
                        .tint(LectraColor.accentSoft)
                        .accessibilityLabel("Highlighter opacity")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                    .fill(LectraColor.surfaceFloating.opacity(0.97))
                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                    .fill(LectraGradient.spotlight.opacity(0.10))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: LectraRadius.element)
                .stroke(LectraColor.edgeStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: LectraRadius.element))
        .lectraShadow(LectraElevation.medium())
        .frame(width: 330)
        .allowsHitTesting(true)
    }

    private func widthValue(at index: Int) -> CGFloat {
        switch selectedTool {
        case .hand, .lasso:
            return selectedStrokeWidth
        case .highlighter:
            guard highlighterStrokeWidths.indices.contains(index) else { return selectedStrokeWidth }
            return highlighterStrokeWidths[index]
        case .eraser:
            guard eraserStrokeWidths.indices.contains(index) else { return selectedStrokeWidth }
            return eraserStrokeWidths[index]
        case .pen:
            guard penStrokeWidths.indices.contains(index) else { return selectedStrokeWidth }
            return penStrokeWidths[index]
        }
    }

    private func updateWidth(at index: Int, to newValue: CGFloat) {
        guard let thicknessRange else { return }
        let stepped = (newValue * 10).rounded() / 10
        let clamped = min(max(stepped, thicknessRange.lowerBound), thicknessRange.upperBound)

        switch selectedTool {
        case .hand, .lasso:
            return
        case .highlighter:
            guard highlighterStrokeWidths.indices.contains(index) else { return }
            highlighterStrokeWidths[index] = clamped
        case .eraser:
            guard eraserStrokeWidths.indices.contains(index) else { return }
            eraserStrokeWidths[index] = clamped
        case .pen:
            guard penStrokeWidths.indices.contains(index) else { return }
            penStrokeWidths[index] = clamped
        }

        selectedStrokeWidth = clamped
    }

    private func clampStrokeWidthToCurrentTool() {
        guard !strokeWidths.isEmpty else { return }
        let isValid = strokeWidths.contains { abs($0 - selectedStrokeWidth) < 0.1 }
        if !isValid {
            let nearest = strokeWidths.min { abs($0 - selectedStrokeWidth) < abs($1 - selectedStrokeWidth) }
            selectedStrokeWidth = nearest ?? selectedStrokeWidth
        }
    }
}

private extension AnnotationInkColor {
    var accessibilityLabel: String {
        switch self {
        case .black:
            return "Black"
        case .white:
            return "White"
        case .accent:
            return "Red"
        case .yellow:
            return "Yellow"
        case .blue:
            return "Blue"
        case .green:
            return "Green"
        }
    }
}

private extension AnnotationTool {
    func strokeWidthLabel(for width: CGFloat) -> String {
        switch self {
        case .pen:
            return "Pen thickness \(String(format: "%.1f", width)) millimeters"
        case .highlighter:
            return "Highlighter thickness \(String(format: "%.1f", width)) millimeters"
        case .eraser:
            return "Eraser size \(String(format: "%.1f", width)) millimeters"
        case .hand:
            return "Read mode"
        case .lasso:
            return "Lasso"
        }
    }
}

private struct StrokeWidthButton: View {
    let width: CGFloat
    let title: String
    let isSelected: Bool
    let action: () -> Void
    private let tapSize: CGFloat = LectraSizing.minHitTarget

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isSelected ? LectraColor.accent.opacity(0.14) : LectraColor.paper.opacity(0.04))
                    .frame(width: tapSize, height: tapSize)

                Circle()
                    .stroke(isSelected ? LectraColor.accentSoft : LectraColor.textSecondary.opacity(0.78), lineWidth: width)
                    .frame(width: 14, height: 14)
            }
            .frame(width: tapSize, height: tapSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: tapSize, height: tapSize)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct ToolButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: isSelected ? .bold : .regular))
                .foregroundColor(isSelected ? LectraColor.textPrimary : LectraColor.textSecondary)
                .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
                .background(
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [LectraColor.accentSoft, LectraColor.accentDark],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        } else {
                            RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                                .fill(LectraColor.surfaceElevated.opacity(0.76))
                                .overlay(
                                    RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                                        .fill(LectraColor.paper.opacity(0.03))
                                )
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                        .stroke(isSelected ? LectraColor.paper.opacity(0.16) : LectraColor.edgeStroke, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous))
                .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
