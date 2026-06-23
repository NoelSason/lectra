import CoreGraphics
import Foundation

nonisolated enum LectraAnnotationKind: String, Codable, CaseIterable, Sendable {
    case inkStroke
    case highlightStroke
    case textBox
    case shape
    case stamp
    case comment
}

nonisolated enum LectraAnnotationExportBehavior: String, Codable, CaseIterable, Sendable {
    case editableAndFlattened
    case editableOnly
    case flattenedOnly
    case hidden
}

nonisolated struct LectraNormalizedRect: Codable, Equatable, Sendable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    static let zero = LectraNormalizedRect(x: 0, y: 0, width: 0, height: 0)

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
        self.width = min(max(width, 0), 1 - self.x)
        self.height = min(max(height, 0), 1 - self.y)
    }

    init(points: [InkPoint]) {
        guard let first = points.first else {
            self = .zero
            return
        }

        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y

        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        self.init(
            x: minX,
            y: minY,
            width: max(maxX - minX, 0),
            height: max(maxY - minY, 0)
        )
    }
}

nonisolated struct LectraAnnotationStyle: Codable, Equatable, Sendable {
    var color: InkColorComponents?
    var lineWidth: CGFloat?
    var opacity: CGFloat?
    var blendMode: InkBlendMode?
    var fontName: String?
    var fontSize: CGFloat?

    init(
        color: InkColorComponents? = nil,
        lineWidth: CGFloat? = nil,
        opacity: CGFloat? = nil,
        blendMode: InkBlendMode? = nil,
        fontName: String? = nil,
        fontSize: CGFloat? = nil
    ) {
        self.color = color
        self.lineWidth = lineWidth
        self.opacity = opacity
        self.blendMode = blendMode
        self.fontName = fontName
        self.fontSize = fontSize
    }

    init(stroke: InkStroke) {
        self.init(
            color: stroke.color,
            lineWidth: stroke.width,
            opacity: stroke.color.alpha,
            blendMode: stroke.blendMode
        )
    }
}

nonisolated struct LectraAnnotationMetadata: Codable, Equatable, Sendable {
    var id: UUID
    var pageIndex: Int
    var bounds: LectraNormalizedRect
    var style: LectraAnnotationStyle
    var createdAt: Date
    var updatedAt: Date
    var author: String?
    var layer: String?
    var exportBehavior: LectraAnnotationExportBehavior

    init(
        id: UUID = UUID(),
        pageIndex: Int,
        bounds: LectraNormalizedRect,
        style: LectraAnnotationStyle = LectraAnnotationStyle(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        author: String? = nil,
        layer: String? = nil,
        exportBehavior: LectraAnnotationExportBehavior = .editableAndFlattened
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.bounds = bounds
        self.style = style
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.author = author
        self.layer = layer
        self.exportBehavior = exportBehavior
    }
}

nonisolated struct LectraStrokeAnnotation: Codable, Equatable, Sendable {
    var metadata: LectraAnnotationMetadata
    var stroke: InkStroke
}

nonisolated struct LectraTextBoxAnnotation: Codable, Equatable, Sendable {
    var metadata: LectraAnnotationMetadata
    var text: String
    var rotationDegrees: CGFloat
}

nonisolated enum LectraShapeKind: String, Codable, CaseIterable, Sendable {
    case line
    case rectangle
    case ellipse
    case polygon
    case freeform
}

nonisolated struct LectraShapeAnnotation: Codable, Equatable, Sendable {
    var metadata: LectraAnnotationMetadata
    var shapeKind: LectraShapeKind
    var points: [InkPoint]
    var rawSourceStroke: InkStroke?
}

nonisolated struct LectraStampAnnotation: Codable, Equatable, Sendable {
    var metadata: LectraAnnotationMetadata
    var assetId: UUID?
    var title: String
    var annotations: [LectraAnnotationObject]
}

nonisolated struct LectraCommentAnnotation: Codable, Equatable, Sendable {
    var metadata: LectraAnnotationMetadata
    var text: String
    var resolvedAt: Date?
}

nonisolated enum LectraAnnotationObject: Equatable, Sendable, Identifiable {
    case inkStroke(LectraStrokeAnnotation)
    case highlightStroke(LectraStrokeAnnotation)
    case textBox(LectraTextBoxAnnotation)
    case shape(LectraShapeAnnotation)
    case stamp(LectraStampAnnotation)
    case comment(LectraCommentAnnotation)

    var id: UUID {
        metadata.id
    }

    var kind: LectraAnnotationKind {
        switch self {
        case .inkStroke:
            return .inkStroke
        case .highlightStroke:
            return .highlightStroke
        case .textBox:
            return .textBox
        case .shape:
            return .shape
        case .stamp:
            return .stamp
        case .comment:
            return .comment
        }
    }

    var metadata: LectraAnnotationMetadata {
        switch self {
        case .inkStroke(let annotation), .highlightStroke(let annotation):
            return annotation.metadata
        case .textBox(let annotation):
            return annotation.metadata
        case .shape(let annotation):
            return annotation.metadata
        case .stamp(let annotation):
            return annotation.metadata
        case .comment(let annotation):
            return annotation.metadata
        }
    }

    var pageIndex: Int {
        metadata.pageIndex
    }

    var strokeAnnotation: LectraStrokeAnnotation? {
        switch self {
        case .inkStroke(let annotation), .highlightStroke(let annotation):
            return annotation
        case .textBox, .shape, .stamp, .comment:
            return nil
        }
    }

    init(stroke: InkStroke, pageIndex: Int, createdAt: Date = Date()) {
        let metadata = LectraAnnotationMetadata(
            pageIndex: pageIndex,
            bounds: LectraNormalizedRect(points: stroke.points),
            style: LectraAnnotationStyle(stroke: stroke),
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let annotation = LectraStrokeAnnotation(metadata: metadata, stroke: stroke)
        if stroke.blendMode == .multiply || stroke.color.alpha < 0.95 {
            self = .highlightStroke(annotation)
        } else {
            self = .inkStroke(annotation)
        }
    }
}

extension LectraAnnotationObject: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(LectraAnnotationKind.self, forKey: .type)

        switch type {
        case .inkStroke:
            self = .inkStroke(try container.decode(LectraStrokeAnnotation.self, forKey: .payload))
        case .highlightStroke:
            self = .highlightStroke(try container.decode(LectraStrokeAnnotation.self, forKey: .payload))
        case .textBox:
            self = .textBox(try container.decode(LectraTextBoxAnnotation.self, forKey: .payload))
        case .shape:
            self = .shape(try container.decode(LectraShapeAnnotation.self, forKey: .payload))
        case .stamp:
            self = .stamp(try container.decode(LectraStampAnnotation.self, forKey: .payload))
        case .comment:
            self = .comment(try container.decode(LectraCommentAnnotation.self, forKey: .payload))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)

        switch self {
        case .inkStroke(let annotation):
            try container.encode(annotation, forKey: .payload)
        case .highlightStroke(let annotation):
            try container.encode(annotation, forKey: .payload)
        case .textBox(let annotation):
            try container.encode(annotation, forKey: .payload)
        case .shape(let annotation):
            try container.encode(annotation, forKey: .payload)
        case .stamp(let annotation):
            try container.encode(annotation, forKey: .payload)
        case .comment(let annotation):
            try container.encode(annotation, forKey: .payload)
        }
    }
}

nonisolated struct LectraAnnotationStore: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var documentId: UUID
    var pages: [Int: [LectraAnnotationObject]]
    var schemaMigratedFromInkDrawingStore: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        version: Int = LectraAnnotationStore.currentVersion,
        documentId: UUID,
        pages: [Int: [LectraAnnotationObject]] = [:],
        schemaMigratedFromInkDrawingStore: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.documentId = documentId
        self.pages = pages
        self.schemaMigratedFromInkDrawingStore = schemaMigratedFromInkDrawingStore
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(
        documentId: UUID,
        migrating drawingStore: InkDrawingStore,
        migratedAt: Date = Date()
    ) {
        var migratedPages: [Int: [LectraAnnotationObject]] = [:]

        for (pageIndex, drawing) in drawingStore.pages {
            let objects = drawing.strokes.map {
                LectraAnnotationObject(stroke: $0, pageIndex: pageIndex, createdAt: migratedAt)
            }
            if !objects.isEmpty {
                migratedPages[pageIndex] = objects
            }
        }

        self.init(
            documentId: documentId,
            pages: migratedPages,
            schemaMigratedFromInkDrawingStore: true,
            createdAt: migratedAt,
            updatedAt: migratedAt
        )
    }

    func inkDrawingStore() -> InkDrawingStore {
        InkDrawingStore(version: 1, pages: inkDrawingsByPage())
    }

    func inkDrawingsByPage() -> [Int: InkPageDrawing] {
        var drawings: [Int: InkPageDrawing] = [:]

        for (pageIndex, objects) in pages {
            let strokes = objects.compactMap { object in
                object.strokeAnnotation?.stroke
            }
            if !strokes.isEmpty {
                drawings[pageIndex] = InkPageDrawing(strokes: strokes)
            }
        }

        return drawings
    }
}
