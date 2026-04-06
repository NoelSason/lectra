//
//  FloatingToolPickerView.swift
//  Lectra
//
//  A floating pill-shaped toolbar for drawing tools.
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
        Group {
            if isVertical {
                verticalLayout
            } else {
                horizontalLayout
            }
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: isVertical ? LectraRadius.sheet : LectraRadius.hero, style: .continuous)
                    .fill(.regularMaterial)
                    .environment(\.colorScheme, .dark)

                RoundedRectangle(cornerRadius: isVertical ? LectraRadius.sheet : LectraRadius.hero, style: .continuous)
                    .fill(LectraColor.surfaceFloating.opacity(0.82))

                RoundedRectangle(cornerRadius: isVertical ? LectraRadius.sheet : LectraRadius.hero, style: .continuous)
                    .fill(LectraGradient.spotlight.opacity(0.22))

                RoundedRectangle(cornerRadius: isVertical ? LectraRadius.sheet : LectraRadius.hero, style: .continuous)
                    .stroke(Color.white.opacity(LectraOpacity.medium), lineWidth: 0.75)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: isVertical ? LectraRadius.sheet : LectraRadius.hero, style: .continuous))
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

    private var horizontalLayout: some View {
        HStack(spacing: 14) {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var verticalLayout: some View {
        VStack(spacing: 12) {
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
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
    }

    private var toolsSection: some View {
        Group {
            if isVertical {
                VStack(spacing: 10) {
                    toolButtons
                }
            } else {
                HStack(spacing: 16) {
                    toolButtons
                }
            }
        }
    }

    private var strokeWidthSection: some View {
        Group {
            if isVertical {
                VStack(spacing: 2) {
                    strokeWidthButtons
                }
            } else {
                HStack(spacing: 4) {
                    strokeWidthButtons
                }
            }
        }
    }

    private var colorSection: some View {
        Group {
            if isVertical {
                VStack(spacing: 12) {
                    if selectedTool == .eraser {
                        eraserModeButtons
                    } else {
                        colorButtons
                    }
                }
            } else {
                HStack(spacing: 12) {
                    if selectedTool == .eraser {
                        eraserModeButtons
                    } else {
                        colorButtons
                    }
                }
            }
        }
    }

    private var sectionDivider: some View {
        Capsule()
            .fill(Color.white.opacity(0.24))
            .frame(width: isVertical ? 36 : 1, height: isVertical ? 1 : 24)
    }

    private var toolButtons: some View {
        Group {
            ToolButton(
                icon: "hand.raised.fill",
                title: "Read mode",
                isSelected: selectedTool == .hand
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
                isSelected: selectedTool == .pen
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
                isSelected: selectedTool == .highlighter
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
                isSelected: selectedTool == .eraser
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
                isSelected: selectedTool == .lasso
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
                                .stroke(Color.white, lineWidth: selectedColor == color ? 2 : 0)
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
                        .foregroundColor(selectedEraserMode == mode ? .white : Color.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                                .fill(
                                    selectedEraserMode == mode
                                    ? LectraColor.accentSoft
                                    : Color.white.opacity(0.08)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                                .stroke(Color.white.opacity(selectedEraserMode == mode ? 0.0 : 0.18), lineWidth: 1)
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
                .foregroundColor(.white.opacity(0.76))
            HStack(spacing: 12) {
                Text(String(format: "%.1f mm", currentWidth))
                    .font(LectraTypography.titleSmall)
                    .foregroundColor(.white)
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
                .tint(.white)
            }

            if selectedTool == .highlighter {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Opacity")
                            .font(LectraTypography.caption)
                            .foregroundColor(.white.opacity(0.72))
                        Spacer(minLength: 0)
                        Text("\(Int((highlighterOpacity * 100).rounded()))%")
                            .font(LectraTypography.captionMedium)
                            .foregroundColor(.white)
                    }

                    Slider(value: $highlighterOpacity, in: 0.15...0.75)
                        .tint(Color.white.opacity(0.92))
                        .accessibilityLabel("Highlighter opacity")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(LectraColor.surfaceOverlay.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: LectraRadius.element)
                .stroke(Color.white.opacity(LectraOpacity.medium), lineWidth: 1)
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
                    .fill(isSelected ? LectraColor.accentCool.opacity(0.14) : Color.clear)
                    .frame(width: tapSize, height: tapSize)

                Circle()
                    .stroke(isSelected ? LectraColor.accentCool : Color.white, lineWidth: width)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: isSelected ? .bold : .regular))
                .foregroundColor(isSelected ? .white : Color.white.opacity(0.9))
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
                                .fill(Color.white.opacity(LectraOpacity.faint))
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                        .stroke(Color.white.opacity(isSelected ? 0.0 : LectraOpacity.medium), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous))
                .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
