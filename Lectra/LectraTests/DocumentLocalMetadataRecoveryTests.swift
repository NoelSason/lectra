import XCTest
@testable import Lectra

final class DocumentLocalMetadataRecoveryTests: XCTestCase {
    func testRecoverySnapshotUpdatesPageAndDirtyIndexesWithoutChangingSyncState() {
        let original = DocumentLocalMetadata(
            syncState: .queuedUpload,
            syncErrorMessage: "Will retry",
            dirtyPageIndexes: [1],
            lastLocalEditAt: Date(timeIntervalSince1970: 100),
            lastRemoteSyncAt: Date(timeIntervalSince1970: 200),
            lastOpenedPage: 2,
            thumbnailRevision: 4,
            searchIndexRevision: 7
        )

        let updated = original.updatingForRecoverySnapshot(
            lastOpenedPage: 9,
            dirtyPageIndexes: [3, 8],
            editedAt: Date(timeIntervalSince1970: 300)
        )

        XCTAssertEqual(updated.syncState, .queuedUpload)
        XCTAssertEqual(updated.syncErrorMessage, "Will retry")
        XCTAssertEqual(updated.lastRemoteSyncAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(updated.lastOpenedPage, 9)
        XCTAssertEqual(updated.dirtyPageIndexes, [3, 8])
        XCTAssertEqual(updated.lastLocalEditAt, Date(timeIntervalSince1970: 300))
        XCTAssertEqual(updated.thumbnailRevision, 4)
        XCTAssertEqual(updated.searchIndexRevision, 7)
    }

    func testRecoverySnapshotCanUpdatePageWithoutChangingLastEditDate() {
        let original = DocumentLocalMetadata(
            syncState: .synced,
            syncErrorMessage: nil,
            dirtyPageIndexes: [],
            lastLocalEditAt: Date(timeIntervalSince1970: 100),
            lastRemoteSyncAt: Date(timeIntervalSince1970: 200),
            lastOpenedPage: 1,
            thumbnailRevision: 0,
            searchIndexRevision: 0
        )

        let updated = original.updatingForRecoverySnapshot(
            lastOpenedPage: 5,
            dirtyPageIndexes: [],
            editedAt: nil
        )

        XCTAssertEqual(updated.syncState, .synced)
        XCTAssertEqual(updated.lastOpenedPage, 5)
        XCTAssertEqual(updated.dirtyPageIndexes, [])
        XCTAssertEqual(updated.lastLocalEditAt, Date(timeIntervalSince1970: 100))
    }
}
