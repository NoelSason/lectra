import XCTest
@testable import Lectra

final class LectraAnnotationStoreTests: XCTestCase {
    func testMigratesInkDrawingStoreToSemanticAnnotationsWithoutChangingStrokePayloads() throws {
        let documentId = UUID()
        let inkStroke = makeStroke(blendMode: .normal)
        let highlightStroke = makeStroke(
            color: InkColorComponents(red: 1, green: 0.9, blue: 0.1, alpha: 0.4),
            blendMode: .multiply
        )
        let drawingStore = InkDrawingStore(
            version: 1,
            pages: [
                0: InkPageDrawing(strokes: [inkStroke, highlightStroke])
            ]
        )

        let encoded = try JSONEncoder().encode(drawingStore)
        let decodedOldStore = try JSONDecoder().decode(InkDrawingStore.self, from: encoded)
        let annotationStore = LectraAnnotationStore(
            documentId: documentId,
            migrating: decodedOldStore,
            migratedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(annotationStore.version, LectraAnnotationStore.currentVersion)
        XCTAssertEqual(annotationStore.documentId, documentId)
        XCTAssertTrue(annotationStore.schemaMigratedFromInkDrawingStore)
        XCTAssertEqual(annotationStore.pages[0]?.map(\.kind), [.inkStroke, .highlightStroke])
        XCTAssertEqual(annotationStore.inkDrawingStore().pages, drawingStore.pages)
    }

    func testSemanticAnnotationObjectsRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 200)
        let metadata = LectraAnnotationMetadata(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            pageIndex: 2,
            bounds: LectraNormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            style: LectraAnnotationStyle(fontName: "Helvetica", fontSize: 14),
            createdAt: now,
            updatedAt: now,
            author: "Lectra",
            layer: "review",
            exportBehavior: .editableAndFlattened
        )

        let objects: [LectraAnnotationObject] = [
            .textBox(
                LectraTextBoxAnnotation(
                    metadata: metadata,
                    text: "Key theorem",
                    rotationDegrees: 0
                )
            ),
            .shape(
                LectraShapeAnnotation(
                    metadata: metadata,
                    shapeKind: .rectangle,
                    points: [InkPoint(x: 0.1, y: 0.2, force: 1), InkPoint(x: 0.4, y: 0.6, force: 1)],
                    rawSourceStroke: makeStroke()
                )
            ),
            .stamp(
                LectraStampAnnotation(
                    metadata: metadata,
                    assetId: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
                    title: "Approved",
                    annotations: []
                )
            ),
            .comment(
                LectraCommentAnnotation(
                    metadata: metadata,
                    text: "Clarify this proof.",
                    resolvedAt: nil
                )
            ),
        ]
        let store = LectraAnnotationStore(
            documentId: UUID(),
            pages: [2: objects],
            createdAt: now,
            updatedAt: now
        )

        let data = try JSONEncoder().encode(store)
        let decoded = try JSONDecoder().decode(LectraAnnotationStore.self, from: data)

        XCTAssertEqual(decoded, store)
    }

    private func makeStroke(
        color: InkColorComponents = InkColorComponents(red: 0, green: 0, blue: 0, alpha: 1),
        blendMode: InkBlendMode = .normal
    ) -> InkStroke {
        InkStroke(
            points: [
                InkPoint(x: 0.2, y: 0.3, force: 1),
                InkPoint(x: 0.4, y: 0.5, force: 1),
            ],
            width: 1.4,
            color: color,
            blendMode: blendMode
        )
    }
}
