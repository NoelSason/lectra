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
    @Binding var selectedEraserMode: EraserMode
    var isVertical: Bool = false

    private let colors: [AnnotationInkColor] = [.black, .white, .accent, .blue, .green]

    @State private var penStrokeWidths: [CGFloat] = [0.5, 1.0, 2.0]
    @State private var highlighterStrokeWidths: [CGFloat] = [2.0, 4.0, 7.0]
    @State private var eraserStrokeWidths: [CGFloat] = [1.5, 3.0, 6.0]
    @State private var activeWidthEditorIndex: Int? = nil

    private var strokeWidths: [CGFloat] {
        switch selectedTool {
        case .highlighter:
            return highlighterStrokeWidths
        case .eraser:
            return eraserStrokeWidths
        case .pen, .lasso:
            return penStrokeWidths
        }
    }

    private var thicknessRange: ClosedRange<CGFloat> {
        switch selectedTool {
        case .highlighter:
            return 1.0...14.0
        case .eraser:
            return 0.8...12.0
        case .pen, .lasso:
            return 0.2...6.0
        }
    }

    private var thicknessEditorTitle: String {
        switch selectedTool {
        case .highlighter:
            return "HIGHLIGHTER THICKNESS"
        case .eraser:
            return "ERASER SIZE"
        case .pen, .lasso:
            return "PEN THICKNESS"
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
                RoundedRectangle(cornerRadius: isVertical ? 24 : 28, style: .continuous)
                    .fill(.regularMaterial)
                    .environment(\.colorScheme, .dark)

                RoundedRectangle(cornerRadius: isVertical ? 24 : 28, style: .continuous)
                    .fill(Color(hex: 0x121B2E, opacity: 0.6))

                RoundedRectangle(cornerRadius: isVertical ? 24 : 28, style: .continuous)
                    .fill(LectraGradient.spotlight.opacity(0.25))

                RoundedRectangle(cornerRadius: isVertical ? 24 : 28, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: isVertical ? 24 : 28, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 12)
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
            sectionDivider
            strokeWidthSection
            sectionDivider
            colorSection
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var verticalLayout: some View {
        VStack(spacing: 12) {
            toolsSection
            sectionDivider
            strokeWidthSection
            sectionDivider
            colorSection
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
            ToolButton(icon: "pencil.tip", isSelected: selectedTool == .pen) {
                withAnimation(LectraMotion.quick) {
                    selectedTool = .pen
                    activeWidthEditorIndex = nil
                }
            }
            ToolButton(icon: "highlighter", isSelected: selectedTool == .highlighter) {
                withAnimation(LectraMotion.quick) {
                    selectedTool = .highlighter
                    activeWidthEditorIndex = nil
                }
            }
            ToolButton(icon: "eraser", isSelected: selectedTool == .eraser) {
                withAnimation(LectraMotion.quick) {
                    selectedTool = .eraser
                    activeWidthEditorIndex = nil
                }
            }
            ToolButton(icon: "lasso", isSelected: selectedTool == .lasso) {
                withAnimation(LectraMotion.quick) {
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
                    isSelected: abs(selectedStrokeWidth - width) < 0.1
                ) {
                    withAnimation(LectraMotion.quick) {
                        selectedStrokeWidth = width
                        if selectedTool == .lasso {
                            selectedTool = .pen
                        }
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
                        selectedColor = color
                        if selectedTool == .eraser || selectedTool == .lasso {
                            selectedTool = .pen
                        }
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
            }
        }
    }

    private var eraserModeButtons: some View {
        Group {
            ForEach(EraserMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(LectraMotion.quick) {
                        selectedEraserMode = mode
                    }
                } label: {
                    Text(mode.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(selectedEraserMode == mode ? .white : Color.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(selectedEraserMode == mode ? Color(hex: 0xD13C35) : Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.white.opacity(selectedEraserMode == mode ? 0.0 : 0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.title) eraser")
            }
        }
    }

    private func thicknessEditor(for index: Int) -> some View {
        let currentWidth = widthValue(at: index)

        return VStack(alignment: .leading, spacing: 10) {
            Text(thicknessEditorTitle)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.76))
            HStack(spacing: 12) {
                Text(String(format: "%.1f mm", currentWidth))
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 78, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { widthValue(at: index) },
                        set: { newValue in
                            updateWidth(at: index, to: newValue)
                        }
                    ),
                    in: thicknessRange
                )
                .tint(.white)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(hex: 0x0D1526, opacity: 0.95))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .frame(width: 330)
        .allowsHitTesting(true)
    }

    private func widthValue(at index: Int) -> CGFloat {
        switch selectedTool {
        case .highlighter:
            guard highlighterStrokeWidths.indices.contains(index) else { return selectedStrokeWidth }
            return highlighterStrokeWidths[index]
        case .eraser:
            guard eraserStrokeWidths.indices.contains(index) else { return selectedStrokeWidth }
            return eraserStrokeWidths[index]
        case .pen, .lasso:
            guard penStrokeWidths.indices.contains(index) else { return selectedStrokeWidth }
            return penStrokeWidths[index]
        }
    }

    private func updateWidth(at index: Int, to newValue: CGFloat) {
        let stepped = (newValue * 10).rounded() / 10
        let clamped = min(max(stepped, thicknessRange.lowerBound), thicknessRange.upperBound)

        switch selectedTool {
        case .highlighter:
            guard highlighterStrokeWidths.indices.contains(index) else { return }
            highlighterStrokeWidths[index] = clamped
        case .eraser:
            guard eraserStrokeWidths.indices.contains(index) else { return }
            eraserStrokeWidths[index] = clamped
        case .pen, .lasso:
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
        case .blue:
            return "Blue"
        case .green:
            return "Green"
        }
    }
}

private struct StrokeWidthButton: View {
    let width: CGFloat
    let isSelected: Bool
    let action: () -> Void
    private let tapSize: CGFloat = LectraSizing.minHitTarget

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.14) : Color.clear)
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
    }
}

private struct ToolButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: isSelected ? .bold : .regular))
                .foregroundColor(isSelected ? .white : Color.white.opacity(0.9))
                .frame(width: 36, height: 36)
                .background(
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [LectraColor.accent, Color(hex: 0xD13C35)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
