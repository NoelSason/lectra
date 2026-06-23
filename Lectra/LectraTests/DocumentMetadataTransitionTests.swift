import XCTest
@testable import Lectra

final class DocumentMetadataTransitionTests: XCTestCase {
    func testUploadMetadataTransitionsExposeCheckpointRetryAndSuccessState() {
        var metadata = DocumentLocalMetadata()
        let checkpointAt = Date(timeIntervalSince1970: 100)
        let attemptAt = Date(timeIntervalSince1970: 140)
        let retryAt = Date(timeIntervalSince1970: 220)
        let uploadedAt = Date(timeIntervalSince1970: 300)

        metadata.markLocalCheckpoint(
            editedAt: checkpointAt,
            lastOpenedPage: 4,
            dirtyPageIndexes: [1, 4]
        )
        metadata.markUploadQueued()
        metadata.markUploadAttempt(at: attemptAt)
        metadata.markUploadFailed(message: "Network timeout", nextRetryAt: retryAt)

        XCTAssertEqual(metadata.lastLocalCheckpointAt, checkpointAt)
        XCTAssertEqual(metadata.lastOpenedPage, 4)
        XCTAssertEqual(metadata.dirtyPageIndexes, [1, 4])
        XCTAssertEqual(metadata.annotationSchemaVersion, LectraAnnotationStore.currentVersion)
        XCTAssertEqual(metadata.lastUploadAttemptAt, attemptAt)
        XCTAssertEqual(metadata.syncState, .failed)
        XCTAssertEqual(metadata.syncErrorMessage, "Network timeout")
        XCTAssertEqual(metadata.nextRetryAt, retryAt)

        metadata.markUploadQueued()
        XCTAssertEqual(metadata.syncState, .queuedUpload)
        XCTAssertNil(metadata.syncErrorMessage)
        XCTAssertNil(metadata.nextRetryAt)

        metadata.markUploadSucceeded(at: uploadedAt)
        XCTAssertEqual(metadata.syncState, .synced)
        XCTAssertEqual(metadata.lastRemoteSyncAt, uploadedAt)
        XCTAssertEqual(metadata.lastSuccessfulUploadAt, uploadedAt)
        XCTAssertEqual(metadata.dirtyPageIndexes, [])
    }

    func testLegacyMetadataDecodeDefaultsNewInspectableFields() throws {
        let data = Data(
            """
            {
              "syncState": "queuedUpload",
              "dirtyPageIndexes": [2, 5],
              "thumbnailRevision": 3,
              "searchIndexRevision": 9
            }
            """.utf8
        )

        let metadata = try JSONDecoder().decode(DocumentLocalMetadata.self, from: data)

        XCTAssertEqual(metadata.syncState, .queuedUpload)
        XCTAssertEqual(metadata.dirtyPageIndexes, [2, 5])
        XCTAssertEqual(metadata.thumbnailRevision, 3)
        XCTAssertEqual(metadata.searchIndexRevision, 9)
        XCTAssertEqual(metadata.annotationSchemaVersion, 1)
        XCTAssertEqual(metadata.conflictState, .none)
        XCTAssertEqual(metadata.iCloudMirrorState, .unknown)
        XCTAssertEqual(metadata.ocrState, .unknown)
        XCTAssertEqual(metadata.ocrQueuedPageIndexes, [])
    }
}
