//
//  AnnotationTool.swift
//  Lectra
//
//  An enum representing the selected drawing tool.
//

import SwiftUI
import PencilKit

enum AnnotationInkColor: String, CaseIterable, Hashable, Codable {
    case black
    case white
    case accent
    case yellow
    case blue
    case green

    var swatchColor: Color {
        Color(inkUIColor)
    }

    var inkUIColor: UIColor {
        switch self {
        case .black:   return LectraInkPalette.black
        case .white:   return LectraInkPalette.white
        case .accent:  return LectraInkPalette.accent
        case .yellow:  return LectraInkPalette.yellow
        case .blue:    return LectraInkPalette.blue
        case .green:   return LectraInkPalette.green
        }
    }
}

enum AnnotationTool: String, Equatable, Codable {
    case hand
    case pen
    case highlighter
    case eraser
    case lasso

    var isAnnotationTool: Bool {
        switch self {
        case .hand:
            return false
        case .pen, .highlighter, .eraser, .lasso:
            return true
        }
    }

    func pkTool(
        color: AnnotationInkColor,
        width: CGFloat,
        highlighterOpacity: CGFloat = 0.35
    ) -> PKTool {
        switch self {
        case .hand:
            return PKInkingTool(.monoline, color: UIColor.clear, width: 0.1)
        case .pen:
            // Use a pressure-independent ink model for crisp, predictable annotation strokes.
            let clampedWidth = min(max(width, 0.5), 2.0)
            return PKInkingTool(.monoline, color: color.inkUIColor, width: clampedWidth)
        case .highlighter:
            // Keep highlight behavior visually distinct without marker feathering/pressure variation.
            return PKInkingTool(
                .monoline,
                color: color.inkUIColor.withAlphaComponent(min(max(highlighterOpacity, 0.1), 0.85)),
                width: width * 1.8
            )
        case .eraser:
            return PKEraserTool(.vector)
        case .lasso:
            return PKLassoTool()
        }
    }
}

enum EraserMode: String, CaseIterable, Hashable, Codable {
    case stroke
    case classic

    var title: String {
        switch self {
        case .stroke:
            return "Stroke"
        case .classic:
            return "Classic"
        }
    }
}
