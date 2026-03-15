import SwiftUI
import UIKit

enum EditorToolbarDockEdge: String, CaseIterable, Codable {
    case left
    case right
    case top
    case bottom

    var isVertical: Bool {
        self == .left || self == .right
    }

    static func defaultEdge(for handedness: EditorHandedness) -> EditorToolbarDockEdge {
        handedness == .left ? .right : .left
    }
}

enum EditorDockProfile: String, CaseIterable, Codable {
    case portraitRegular
    case portraitCompact
    case landscapeRegular
    case landscapeCompact

    static func resolve(for size: CGSize) -> EditorDockProfile {
        let isPortrait = size.height >= size.width
        let compactWidthThreshold: CGFloat = 820
        let isCompact = size.width < compactWidthThreshold

        switch (isPortrait, isCompact) {
        case (true, true):
            return .portraitCompact
        case (true, false):
            return .portraitRegular
        case (false, true):
            return .landscapeCompact
        case (false, false):
            return .landscapeRegular
        }
    }
}

enum LassoSelectionHandle: CaseIterable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:
            return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:
            return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomRight:
            return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottomLeft:
            return CGPoint(x: rect.minX, y: rect.maxY)
        }
    }

    var opposite: LassoSelectionHandle {
        switch self {
        case .topLeft:
            return .bottomRight
        case .topRight:
            return .bottomLeft
        case .bottomRight:
            return .topLeft
        case .bottomLeft:
            return .topRight
        }
    }
}

enum LassoGeometry {
    static func contains(point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }

        var contains = false
        var previous = polygon[polygon.count - 1]

        for current in polygon {
            let intersects = ((current.y > point.y) != (previous.y > point.y))
                && (
                    point.x < ((previous.x - current.x) * (point.y - current.y) / max(previous.y - current.y, .leastNonzeroMagnitude)) + current.x
                )
            if intersects {
                contains.toggle()
            }
            previous = current
        }

        return contains
    }

    static func strokeIntersectsPolygon(stroke: [CGPoint], polygon: [CGPoint]) -> Bool {
        guard !stroke.isEmpty, polygon.count >= 3 else { return false }

        if stroke.contains(where: { contains(point: $0, polygon: polygon) }) {
            return true
        }

        let polygonEdges = edges(for: polygon)
        let strokeEdges = edges(for: stroke)

        for strokeEdge in strokeEdges {
            if polygonEdges.contains(where: { intersects($0, strokeEdge) }) {
                return true
            }
        }

        if let firstPolygonPoint = polygon.first,
           contains(point: firstPolygonPoint, polygon: stroke) {
            return true
        }

        return false
    }

    static func boundingRect(for pointGroups: [[CGPoint]]) -> CGRect? {
        let allPoints = pointGroups.flatMap { $0 }
        guard let first = allPoints.first else { return nil }

        var rect = CGRect(origin: first, size: .zero)
        for point in allPoints.dropFirst() {
            rect = rect.union(CGRect(origin: point, size: .zero))
        }
        return rect.standardized
    }

    static func translated(points: [CGPoint], by translation: CGSize) -> [CGPoint] {
        points.map { point in
            CGPoint(x: point.x + translation.width, y: point.y + translation.height)
        }
    }

    static func duplicated(
        pointGroups: [[CGPoint]],
        translation: CGSize = CGSize(width: 24, height: 24)
    ) -> [[CGPoint]] {
        pointGroups.map { translated(points: $0, by: translation) }
    }

    static func scaled(
        points: [CGPoint],
        from sourceRect: CGRect,
        to targetRect: CGRect
    ) -> [CGPoint] {
        guard sourceRect.width > 0, sourceRect.height > 0 else { return points }

        return points.map { point in
            let normalizedX = (point.x - sourceRect.minX) / sourceRect.width
            let normalizedY = (point.y - sourceRect.minY) / sourceRect.height
            return CGPoint(
                x: targetRect.minX + normalizedX * targetRect.width,
                y: targetRect.minY + normalizedY * targetRect.height
            )
        }
    }

    static func proportionalResizeRect(
        from rect: CGRect,
        handle: LassoSelectionHandle,
        location: CGPoint,
        minimumSize: CGFloat = 28
    ) -> CGRect {
        guard rect.width > 0, rect.height > 0 else { return rect }

        let anchor = handle.opposite.point(in: rect)
        let aspectRatio = rect.width / rect.height

        let deltaX = location.x - anchor.x
        let deltaY = location.y - anchor.y
        let widthSign: CGFloat = handle == .topLeft || handle == .bottomLeft ? -1 : 1
        let heightSign: CGFloat = handle == .topLeft || handle == .topRight ? -1 : 1

        let candidateWidth = max(abs(deltaX), minimumSize)
        let candidateHeight = max(abs(deltaY), minimumSize)

        let widthFromHeight = candidateHeight * aspectRatio
        let heightFromWidth = candidateWidth / aspectRatio

        let finalWidth: CGFloat
        let finalHeight: CGFloat
        if widthFromHeight >= candidateWidth {
            finalWidth = widthFromHeight
            finalHeight = candidateHeight
        } else {
            finalWidth = candidateWidth
            finalHeight = heightFromWidth
        }

        let origin = CGPoint(
            x: anchor.x + (widthSign < 0 ? -finalWidth : 0),
            y: anchor.y + (heightSign < 0 ? -finalHeight : 0)
        )

        return CGRect(origin: origin, size: CGSize(width: finalWidth, height: finalHeight)).standardized
    }

    static func removing<T>(items: [T], at indexes: [Int]) -> [T] {
        let indexesToRemove = Set(indexes)
        return items.enumerated()
            .filter { !indexesToRemove.contains($0.offset) }
            .map(\.element)
    }

    private static func edges(for points: [CGPoint]) -> [(CGPoint, CGPoint)] {
        guard points.count > 1 else { return [] }
        return zip(points, points.dropFirst()).map { ($0.0, $0.1) }
    }

    private static func intersects(_ lhs: (CGPoint, CGPoint), _ rhs: (CGPoint, CGPoint)) -> Bool {
        ccw(lhs.0, rhs.0, rhs.1) != ccw(lhs.1, rhs.0, rhs.1)
            && ccw(lhs.0, lhs.1, rhs.0) != ccw(lhs.0, lhs.1, rhs.1)
    }

    private static func ccw(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        (c.y - a.y) * (b.x - a.x) > (b.y - a.y) * (c.x - a.x)
    }
}

enum AutoAppendedBlankPageUndoGuard {
    static func canUndo(
        candidateIndex: Int?,
        totalPageCount: Int,
        isTerminalBlankPage: Bool,
        isPageEmpty: Bool,
        hasHistory: Bool
    ) -> Bool {
        guard let candidateIndex else { return false }
        guard candidateIndex == totalPageCount - 1 else { return false }
        guard isTerminalBlankPage, isPageEmpty, !hasHistory else { return false }
        return true
    }
}

func postAccessibilityAnnouncement(_ message: String) {
    #if canImport(UIKit)
    DispatchQueue.main.async {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
    #endif
}
