import XCTest
@testable import Lectra

@MainActor
final class DocumentBrowserViewNoticeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        LectraLocalAccountData.purgeAccountScopedData()
    }

    override func tearDown() {
        LectraLocalAccountData.purgeAccountScopedData()
        super.tearDown()
    }

    func testSuppressesPassiveBackgroundUploadRetryNotice() {
        XCTAssertTrue(
            DocumentBrowserView.shouldSuppressBlockingNotice(
                for: "Saved locally. We'll retry upload automatically."
            )
        )
    }

    func testSuppressesPassiveBackgroundICloudSyncNotice() {
        XCTAssertTrue(
            DocumentBrowserView.shouldSuppressBlockingNotice(
                for: "Saved locally, but iCloud sync did not finish: The Internet connection appears to be offline."
            )
        )
    }

    func testKeepsActionableNoticesBlocking() {
        XCTAssertFalse(
            DocumentBrowserView.shouldSuppressBlockingNotice(
                for: "Saved locally, but the upload file is missing."
            )
        )
        XCTAssertFalse(
            DocumentBrowserView.shouldSuppressBlockingNotice(
                for: "Download failed: Request timed out."
            )
        )
    }

    func testSavedLocalDocumentRequiresMatchingOwner() {
        let owner = UUID()
        let otherUser = UUID()
        let document = SavedLocalDocument(
            id: UUID(),
            title: "Owned",
            localPath: "pdfs/owned/original.pdf",
            sourceURLString: nil,
            ownerUserId: owner,
            createdAt: nil,
            updatedAt: nil,
            isFavorite: nil
        )
        let legacyDocument = SavedLocalDocument(
            id: UUID(),
            title: "Legacy",
            localPath: "pdfs/legacy/original.pdf",
            sourceURLString: nil,
            ownerUserId: nil,
            createdAt: nil,
            updatedAt: nil,
            isFavorite: nil
        )

        XCTAssertTrue(document.belongs(to: owner))
        XCTAssertFalse(document.belongs(to: otherUser))
        XCTAssertFalse(legacyDocument.belongs(to: owner))
    }

    func testDocumentIndexOnlyExposesCurrentLocalOwnerDocuments() throws {
        let owner = UUID()
        let otherUser = UUID()
        let ownedDocumentID = UUID()
        let otherDocumentID = UUID()
        let documentsRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        try writePlaceholderPDF(relativePath: "pdfs/\(ownedDocumentID.uuidString)/original.pdf", documentsRoot: documentsRoot)
        try writePlaceholderPDF(relativePath: "pdfs/\(otherDocumentID.uuidString)/original.pdf", documentsRoot: documentsRoot)

        let saved = [
            SavedLocalDocument(
                id: ownedDocumentID,
                title: "Owned",
                localPath: "pdfs/\(ownedDocumentID.uuidString)/original.pdf",
                sourceURLString: nil,
                ownerUserId: owner,
                createdAt: Date(timeIntervalSince1970: 10),
                updatedAt: Date(timeIntervalSince1970: 20),
                isFavorite: false
            ),
            SavedLocalDocument(
                id: otherDocumentID,
                title: "Other",
                localPath: "pdfs/\(otherDocumentID.uuidString)/original.pdf",
                sourceURLString: nil,
                ownerUserId: otherUser,
                createdAt: Date(timeIntervalSince1970: 30),
                updatedAt: Date(timeIntervalSince1970: 40),
                isFavorite: false
            ),
        ]

        UserDefaults.standard.set(try JSONEncoder().encode(saved), forKey: LectraLocalAccountData.localPDFsDefaultsKey)
        LectraLocalAccountData.markOwner(owner)

        XCTAssertEqual(LectraDocumentIndex.all().map(\.id), [ownedDocumentID])
    }

    func testAccountScopedPurgeRemovesLocalLibraryStateAndFiles() throws {
        let documentID = UUID()
        let documentsRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try writePlaceholderPDF(relativePath: "pdfs/\(documentID.uuidString)/original.pdf", documentsRoot: documentsRoot)
        try FileManager.default.createDirectory(
            at: documentsRoot.appendingPathComponent("sync", isDirectory: true),
            withIntermediateDirectories: true
        )

        UserDefaults.standard.set(Data("[]".utf8), forKey: LectraLocalAccountData.localPDFsDefaultsKey)
        UserDefaults.standard.set(UUID().uuidString, forKey: LectraLocalAccountData.localOwnerUserIdDefaultsKey)
        UserDefaults.standard.set(["x": "y"], forKey: LectraLocalAccountData.documentFolderMapDefaultsKey)
        UserDefaults.standard.set(Data("{}".utf8), forKey: LegacyThirdPartyIntegrationData.linkedSubmissionDefaultsKey)
        UserDefaults.standard.set([["Name": "value"]], forKey: LegacyThirdPartyIntegrationData.plaintextCookieDefaultsKey)

        LectraLocalAccountData.purgeAccountScopedData()

        XCTAssertNil(UserDefaults.standard.object(forKey: LectraLocalAccountData.localPDFsDefaultsKey))
        XCTAssertNil(UserDefaults.standard.object(forKey: LectraLocalAccountData.localOwnerUserIdDefaultsKey))
        XCTAssertNil(UserDefaults.standard.object(forKey: LectraLocalAccountData.documentFolderMapDefaultsKey))
        XCTAssertNil(UserDefaults.standard.object(forKey: LegacyThirdPartyIntegrationData.linkedSubmissionDefaultsKey))
        XCTAssertNil(UserDefaults.standard.object(forKey: LegacyThirdPartyIntegrationData.plaintextCookieDefaultsKey))
        XCTAssertFalse(FileManager.default.fileExists(atPath: documentsRoot.appendingPathComponent("pdfs").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: documentsRoot.appendingPathComponent("sync").path))
    }

    private func writePlaceholderPDF(relativePath: String, documentsRoot: URL) throws {
        let url = documentsRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("%PDF-1.4\n%%EOF".utf8).write(to: url)
    }
}
