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
}
