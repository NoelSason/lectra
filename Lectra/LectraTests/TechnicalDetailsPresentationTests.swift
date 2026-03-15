import XCTest
@testable import Lectra

final class TechnicalDetailsPresentationTests: XCTestCase {
    func testPresentationIsHiddenWhenDetailsAreMissing() {
        XCTAssertNil(
            TechnicalDetailsPresentation.make(
                summary: "Technical details are available.",
                details: nil
            )
        )

        XCTAssertNil(
            TechnicalDetailsPresentation.make(
                summary: "Technical details are available.",
                details: "   \n"
            )
        )
    }

    func testPresentationIsHiddenWhenDetailsDuplicateSuppressedContent() {
        XCTAssertNil(
            TechnicalDetailsPresentation.make(
                summary: "Technical details are available.",
                details: "same payload",
                excluding: "same payload"
            )
        )
    }

    func testPresentationFallsBackToDefaultSummary() {
        let presentation = TechnicalDetailsPresentation.make(
            summary: "   ",
            details: "request-id: 123"
        )

        XCTAssertEqual(presentation?.summary, "Technical details are available for support.")
        XCTAssertEqual(presentation?.details, "request-id: 123")
    }
}
