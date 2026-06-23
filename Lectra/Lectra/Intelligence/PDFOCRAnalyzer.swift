import Foundation
import PDFKit

nonisolated enum PDFOCRState: String, Codable, CaseIterable, Sendable {
    case unknown
    case textAvailable
    case needsOCR
    case queued
}

nonisolated struct PDFOCRDetectionResult: Codable, Equatable, Sendable {
    let state: PDFOCRState
    let sampledPageIndexes: [Int]
    let extractedCharacterCount: Int
    let checkedAt: Date

    var needsOCR: Bool {
        state == .needsOCR
    }
}

nonisolated enum PDFOCREnginePreference: String, Codable, CaseIterable, Sendable {
    case visionOnDevice
    case cloudOptIn
}

nonisolated enum PDFOCRWorkItemState: String, Codable, CaseIterable, Sendable {
    case queued
    case processing
    case completed
    case failed
}

nonisolated struct PDFOCRWorkItem: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var documentId: UUID
    var pageIndex: Int
    var enginePreference: PDFOCREnginePreference
    var state: PDFOCRWorkItemState
    var queuedAt: Date
    var updatedAt: Date
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        documentId: UUID,
        pageIndex: Int,
        enginePreference: PDFOCREnginePreference = .visionOnDevice,
        state: PDFOCRWorkItemState = .queued,
        queuedAt: Date = Date(),
        updatedAt: Date = Date(),
        errorMessage: String? = nil
    ) {
        self.id = id
        self.documentId = documentId
        self.pageIndex = pageIndex
        self.enginePreference = enginePreference
        self.state = state
        self.queuedAt = queuedAt
        self.updatedAt = updatedAt
        self.errorMessage = errorMessage
    }
}

nonisolated enum PDFOCRAnalyzer {
    static func detectTextAvailability(
        at url: URL,
        maxSampledPages: Int = 8,
        minimumTextCharacterCount: Int = 12,
        checkedAt: Date = Date()
    ) -> PDFOCRDetectionResult {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            return PDFOCRDetectionResult(
                state: .unknown,
                sampledPageIndexes: [],
                extractedCharacterCount: 0,
                checkedAt: checkedAt
            )
        }

        let indexes = sampledPageIndexes(
            pageCount: document.pageCount,
            maxSampledPages: maxSampledPages
        )

        let characterCount = indexes.reduce(0) { partial, index in
            guard let page = document.page(at: index) else { return partial }
            let text = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return partial + text.count
        }

        return PDFOCRDetectionResult(
            state: characterCount >= minimumTextCharacterCount ? .textAvailable : .needsOCR,
            sampledPageIndexes: indexes,
            extractedCharacterCount: characterCount,
            checkedAt: checkedAt
        )
    }

    static func workItems(
        for documentId: UUID,
        pageIndexes: [Int],
        queuedAt: Date = Date()
    ) -> [PDFOCRWorkItem] {
        pageIndexes.map {
            PDFOCRWorkItem(
                documentId: documentId,
                pageIndex: $0,
                queuedAt: queuedAt,
                updatedAt: queuedAt
            )
        }
    }

    static func sampledPageIndexes(pageCount: Int, maxSampledPages: Int = 8) -> [Int] {
        guard pageCount > 0, maxSampledPages > 0 else { return [] }
        guard pageCount > maxSampledPages else { return Array(0..<pageCount) }

        let lastIndex = pageCount - 1
        var indexes = Set([0, lastIndex, pageCount / 2])
        let step = max(lastIndex / max(maxSampledPages - 1, 1), 1)

        var cursor = 0
        while indexes.count < maxSampledPages, cursor <= lastIndex {
            indexes.insert(cursor)
            cursor += step
        }

        cursor = lastIndex
        while indexes.count < maxSampledPages, cursor >= 0 {
            indexes.insert(cursor)
            cursor -= step
        }

        return indexes.sorted()
    }
}
