import XCTest
@testable import Lectra

final class DocumentRepositoryPersistenceTests: XCTestCase {
    private var repository: DocumentRepository!

    override func setUp() {
        super.setUp()
        repository = DocumentRepository()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: repository.syncQueueURL())
        try? FileManager.default.removeItem(at: repository.ocrQueueURL())
        try? FileManager.default.removeItem(at: repository.assetLibraryURL())
        repository = nil
        super.tearDown()
    }

    func testLocalMetadataRoundTrips() throws {
        let documentId = UUID()
        let metadata = DocumentLocalMetadata(
            syncState: .queuedUpload,
            syncErrorMessage: "Waiting for upload",
            dirtyPageIndexes: [1, 3, 8],
            lastLocalEditAt: Date(timeIntervalSince1970: 100),
            lastRemoteSyncAt: Date(timeIntervalSince1970: 200),
            lastOpenedPage: 12,
            thumbnailRevision: 4,
            searchIndexRevision: 7
        )

        repository.saveLocalMetadata(metadata, documentId: documentId)
        let loaded = repository.loadLocalMetadata(documentId: documentId)

        XCTAssertEqual(loaded, metadata)

        try? FileManager.default.removeItem(
            at: repository.localMetadataURL(for: documentId).deletingLastPathComponent()
        )
    }

    func testPendingSyncJobsRoundTrip() {
        let jobs = [
            PendingSyncJob(
                id: UUID(),
                documentId: UUID(),
                rowId: UUID(),
                userId: UUID(),
                itemData: DocumentData(
                    title: "Biology Notes",
                    courseId: 42,
                    sourceUrl: "https://example.com/biology.pdf",
                    storagePath: "raw/biology.pdf",
                    annotatedStoragePath: "annotated/biology.pdf",
                    status: "annotated"
                ),
                annotatedFilePath: "/tmp/annotated.pdf",
                queuedAt: Date(timeIntervalSince1970: 300),
                retryCount: 2,
                nextRetryAt: Date(timeIntervalSince1970: 360),
                lastErrorMessage: "Network timeout"
            )
        ]

        repository.savePendingSyncJobs(jobs)
        let loaded = repository.loadPendingSyncJobs()

        XCTAssertEqual(loaded, jobs)
    }

    func testAnnotationStoreRoundTripsBesideDocument() throws {
        let documentId = UUID()
        let store = LectraAnnotationStore(
            documentId: documentId,
            migrating: InkDrawingStore(
                version: 1,
                pages: [
                    0: InkPageDrawing(strokes: [makeStroke()])
                ]
            ),
            migratedAt: Date(timeIntervalSince1970: 500)
        )

        try repository.saveLocalAnnotations(store, documentId: documentId)
        let loaded = repository.loadLocalAnnotations(documentId: documentId)

        XCTAssertEqual(loaded, store)

        try? FileManager.default.removeItem(
            at: repository.localAnnotationsURL(for: documentId).deletingLastPathComponent()
        )
    }

    func testAssetLibraryAndOCRQueueRoundTrip() throws {
        let asset = LectraReusableAsset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000404")!,
            kind: .stamp,
            title: "Approved",
            annotations: [],
            createdAt: Date(timeIntervalSince1970: 600),
            updatedAt: Date(timeIntervalSince1970: 700)
        )
        let library = LectraAssetLibrary(assets: [asset])
        let job = PDFOCRWorkItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000505")!,
            documentId: UUID(uuidString: "00000000-0000-0000-0000-000000000606")!,
            pageIndex: 4,
            queuedAt: Date(timeIntervalSince1970: 800),
            updatedAt: Date(timeIntervalSince1970: 800)
        )

        try repository.saveAssetLibrary(library)
        repository.mergePendingOCRJobs([job, job])

        XCTAssertEqual(repository.loadAssetLibrary(), library)
        XCTAssertEqual(repository.loadPendingOCRJobs(), [job])
    }

    private func makeStroke() -> InkStroke {
        InkStroke(
            points: [
                InkPoint(x: 0.1, y: 0.2, force: 1),
                InkPoint(x: 0.3, y: 0.4, force: 1),
            ],
            width: 1.1,
            color: InkColorComponents(red: 0, green: 0, blue: 0, alpha: 1),
            blendMode: .normal
        )
    }
}
