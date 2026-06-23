import PDFKit
import UIKit
import XCTest
@testable import Lectra

final class PDFOCRAnalyzerTests: XCTestCase {
    func testTextPDFDoesNotNeedOCR() throws {
        let url = try makePDF { bounds in
            let text = "This page has selectable lecture text."
            text.draw(
                at: CGPoint(x: 24, y: 24),
                withAttributes: [.font: UIFont.systemFont(ofSize: 18)]
            )
            UIColor.clear.setFill()
            UIRectFill(CGRect(x: bounds.maxX - 1, y: bounds.maxY - 1, width: 1, height: 1))
        }
        defer { try? FileManager.default.removeItem(at: url) }

        let result = PDFOCRAnalyzer.detectTextAvailability(
            at: url,
            minimumTextCharacterCount: 4,
            checkedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(result.state, .textAvailable)
        XCTAssertFalse(result.needsOCR)
        XCTAssertGreaterThan(result.extractedCharacterCount, 4)
    }

    func testImageOnlyPDFNeedsOCRAndQueuesSampledPages() throws {
        let url = try makePDF(pageCount: 3) { bounds in
            UIColor.black.setFill()
            UIRectFill(CGRect(x: 20, y: 20, width: bounds.width - 40, height: bounds.height - 40))
        }
        defer { try? FileManager.default.removeItem(at: url) }

        let result = PDFOCRAnalyzer.detectTextAvailability(
            at: url,
            maxSampledPages: 2,
            minimumTextCharacterCount: 4,
            checkedAt: Date(timeIntervalSince1970: 100)
        )
        let workItems = PDFOCRAnalyzer.workItems(
            for: UUID(uuidString: "00000000-0000-0000-0000-000000000303")!,
            pageIndexes: result.sampledPageIndexes,
            queuedAt: result.checkedAt
        )

        XCTAssertEqual(result.state, .needsOCR)
        XCTAssertTrue(result.needsOCR)
        XCTAssertEqual(result.extractedCharacterCount, 0)
        XCTAssertEqual(workItems.map(\.pageIndex), result.sampledPageIndexes)
        XCTAssertTrue(workItems.allSatisfy { $0.enginePreference == .visionOnDevice })
    }

    private func makePDF(
        pageCount: Int = 1,
        draw: (CGRect) -> Void
    ) throws -> URL {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 400)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data = renderer.pdfData { context in
            for _ in 0..<pageCount {
                context.beginPage()
                draw(bounds)
            }
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocr-test-\(UUID().uuidString).pdf")
        try data.write(to: url)
        return url
    }
}
