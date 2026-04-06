import XCTest
@testable import Lectra

final class DocumentBrowserViewNoticeTests: XCTestCase {
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
}
