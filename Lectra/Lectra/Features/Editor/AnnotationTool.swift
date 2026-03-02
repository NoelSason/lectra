//
//  AnnotationTool.swift
//  Lectra
//
//  An enum representing the selected drawing tool.
//

import SwiftUI
import PencilKit

enum AnnotationInkColor: String, CaseIterable, Hashable {
    case black
    case white
    case accent
    case blue
    case green

    var swatchColor: Color {
        Color(inkUIColor)
    }

    var inkUIColor: UIColor {
        switch self {
        case .black:
            return UIColor(white: 0.0, alpha: 1.0)
        case .white:
            return UIColor(white: 1.0, alpha: 1.0)
        case .accent:
            return UIColor(red: 224.0 / 255.0, green: 37.0 / 255.0, blue: 32.0 / 255.0, alpha: 1.0)
        case .blue:
            return UIColor(red: 0.0 / 255.0, green: 122.0 / 255.0, blue: 255.0 / 255.0, alpha: 1.0)
        case .green:
            return UIColor(red: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0, alpha: 1.0)
        }
    }
}

enum AnnotationTool: Equatable {
    case pen
    case highlighter
    case eraser
    case lasso
    
    func pkTool(color: AnnotationInkColor, width: CGFloat) -> PKTool {
        switch self {
        case .pen:
            // Use a pressure-independent ink model for crisp, predictable annotation strokes.
            let clampedWidth = min(max(width, 0.5), 2.0)
            return PKInkingTool(.monoline, color: color.inkUIColor, width: clampedWidth)
        case .highlighter:
            // Keep highlight behavior visually distinct without marker feathering/pressure variation.
            return PKInkingTool(.monoline, color: color.inkUIColor.withAlphaComponent(0.35), width: width * 1.8)
        case .eraser:
            return PKEraserTool(.vector)
        case .lasso:
            return PKLassoTool()
        }
    }
}
