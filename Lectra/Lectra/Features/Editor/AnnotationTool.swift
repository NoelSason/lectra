//
//  AnnotationTool.swift
//  Lectra
//
//  An enum representing the selected drawing tool.
//

import SwiftUI
import PencilKit

struct AnnotationInkColor: RawRepresentable, Hashable, Codable, Equatable {
    var rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let black = AnnotationInkColor(rawValue: "black")
    static let white = AnnotationInkColor(rawValue: "white")
    static let accent = AnnotationInkColor(rawValue: "accent")
    static let blue = AnnotationInkColor(rawValue: "blue")
    static let green = AnnotationInkColor(rawValue: "green")

    static var allCases: [AnnotationInkColor] {
        [.black, .white, .accent, .blue, .green]
    }

    var swatchColor: Color {
        Color(inkUIColor)
    }

    var inkUIColor: UIColor {
        switch rawValue {
        case "black":
            return UIColor(white: 0.0, alpha: 1.0)
        case "white":
            return UIColor(white: 1.0, alpha: 1.0)
        case "accent":
            return UIColor(red: 224.0 / 255.0, green: 37.0 / 255.0, blue: 32.0 / 255.0, alpha: 1.0)
        case "blue":
            return UIColor(red: 0.0 / 255.0, green: 122.0 / 255.0, blue: 255.0 / 255.0, alpha: 1.0)
        case "green":
            return UIColor(red: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0, alpha: 1.0)
        default:
            var hexString = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if hexString.hasPrefix("#") {
                hexString.remove(at: hexString.startIndex)
            }
            if hexString.count == 6 {
                var rgbValue: UInt64 = 0
                Scanner(string: hexString).scanHexInt64(&rgbValue)
                return UIColor(
                    red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
                    green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
                    blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
                    alpha: 1.0
                )
            }
            return UIColor.black
        }
    }
}

extension UIColor {
    func toHexString() -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let rgb: Int = (Int)(r * 255) << 16 | (Int)(g * 255) << 8 | (Int)(b * 255) << 0
        return String(format: "#%06x", rgb)
    }
}

enum AnnotationTool: String, Equatable, Codable {
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
