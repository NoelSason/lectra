//
//  PDFTextExtractor.swift
//  Lectra
//
//  Pulls plain text out of a PDF so the intelligence layer has something
//  to reason over. Uses PDFKit (already part of the editor stack) and
//  caches the extracted text per-document beside the existing sidecar
//  files under DocumentDirectory/pdfs/{id}/.
//

import Foundation
import PDFKit

enum PDFTextExtractor {

    /// Approximate character budget the on-device model comfortably handles.
    /// Used by callers to decide how much of a document to feed in.
    static let onDeviceCharBudget = 14_000

    /// Character budget when Private Cloud Compute (iOS 27+) serves the request.
    /// PCC's ~32K-token window holds far more text, so whole-document features
    /// keep the tail instead of truncating at the on-device limit. Conservative
    /// (~30K tokens at ~4 chars/token) to leave headroom for instructions and
    /// the response.
    static let pccCharBudget = 120_000

    /// Whole-document text, optionally capped to the first `pageLimit` pages.
    nonisolated static func fullText(at url: URL, pageLimit: Int? = nil) -> String {
        guard let document = PDFDocument(url: url) else { return "" }
        let count = document.pageCount
        let upperBound = pageLimit.map { min($0, count) } ?? count
        guard upperBound > 0 else { return "" }

        var pieces: [String] = []
        pieces.reserveCapacity(upperBound)
        for index in 0..<upperBound {
            if let page = document.page(at: index), let text = page.string {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { pieces.append(trimmed) }
            }
        }
        return pieces.joined(separator: "\n\n")
    }

    /// Text from a single page (0-based).
    nonisolated static func text(at url: URL, pageIndex: Int) -> String {
        guard let document = PDFDocument(url: url),
              pageIndex >= 0, pageIndex < document.pageCount,
              let page = document.page(at: pageIndex) else { return "" }
        return (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func pageCount(at url: URL) -> Int {
        PDFDocument(url: url)?.pageCount ?? 0
    }

    /// Trims text to a character budget on a word boundary so prompts stay
    /// within the model's context window without cutting mid-word.
    nonisolated static func clamp(_ text: String, toChars limit: Int) -> String {
        guard text.count > limit else { return text }
        let slice = text.prefix(limit)
        if let lastSpace = slice.lastIndex(of: " ") {
            return String(slice[..<lastSpace]) + "…"
        }
        return String(slice) + "…"
    }
}
