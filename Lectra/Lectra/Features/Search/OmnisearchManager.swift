import Foundation
import PDFKit
import Vision
import Combine
import UIKit

@MainActor
final class OmnisearchManager: ObservableObject {
    static let shared = OmnisearchManager()
    
    struct GSFeedbackEntry: Codable, Identifiable {
        var id: String { assignmentId }
        let assignmentId: String
        let assignmentName: String
        let feedbackText: String
    }
    
    @Published private(set) var indexedDocumentIDs: Set<UUID> = []
    @Published private(set) var registeredFeedback: [GSFeedbackEntry] = []
    
    private let cacheDirectory: URL
    private var memoryCache: [UUID: String] = [:]
    
    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDirectory = appSupport.appendingPathComponent("LectraOmnisearch", isDirectory: true)
        
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        
        loadIndex()
    }
    
    private func loadIndex() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "txt" {
            let idString = file.deletingPathExtension().lastPathComponent
            if let id = UUID(uuidString: idString) {
                indexedDocumentIDs.insert(id)
            }
        }
        
        let feedbackURL = cacheDirectory.appendingPathComponent("gradescope_feedback.json")
        if let data = try? Data(contentsOf: feedbackURL),
           let entries = try? JSONDecoder().decode([GSFeedbackEntry].self, from: data) {
            registeredFeedback = entries
        } else {
            registeredFeedback = [
                GSFeedbackEntry(assignmentId: "CS101-HW3", assignmentName: "Homework 3: Trees", feedbackText: "-2 pts: Did not handle null root node appropriately in DFS function. Try to check if root is null before traversing. Looked good otherwise. Rubric match: DFS Implementation.")
            ]
        }
    }
    
    func indexIfNeeded(document: LocalDocument) {
        guard !indexedDocumentIDs.contains(document.id) else { return }
        guard let pdfURL = document.localPDFURL else { return }
        
        Task.detached(priority: .background) {
            await self.performOCR(for: document.id, fileURL: pdfURL)
        }
    }
    
    func hasMatch(for documentID: UUID, query: String) -> Bool {
        if !indexedDocumentIDs.contains(documentID) { return false }
        
        if let cached = memoryCache[documentID] {
            return cached.localizedCaseInsensitiveContains(query)
        }
        
        let fileURL = cacheDirectory.appendingPathComponent("\(documentID.uuidString).txt")
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return false }
        
        memoryCache[documentID] = text
        return text.localizedCaseInsensitiveContains(query)
    }
    
    func indexGradescopeFeedback(assignmentId: String, assignmentName: String, feedbackText: String) {
        let entry = GSFeedbackEntry(assignmentId: assignmentId, assignmentName: assignmentName, feedbackText: feedbackText)
        registeredFeedback.removeAll(where: { $0.assignmentId == assignmentId })
        registeredFeedback.append(entry)
        
        let data = try? JSONEncoder().encode(registeredFeedback)
        let fileURL = cacheDirectory.appendingPathComponent("gradescope_feedback.json")
        try? data?.write(to: fileURL)
    }
    
    func searchFeedback(query: String) -> [GSFeedbackEntry] {
        guard !query.isEmpty else { return [] }
        return registeredFeedback.filter { entry in
            entry.feedbackText.localizedCaseInsensitiveContains(query) || entry.assignmentName.localizedCaseInsensitiveContains(query)
        }
    }
    
    private func performOCR(for documentID: UUID, fileURL: URL) async {
        guard let document = PDFDocument(url: fileURL) else { return }
        
        var fullText = ""
        let maxPages = min(document.pageCount, 15) // Limit to first 15 pages for performance
        
        for i in 0..<maxPages {
            guard let page = document.page(at: i) else { continue }
            if let pageText = page.string, !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fullText += pageText + "\n"
            } else {
                fullText += (await extractTextFromImage(page: page)) + "\n"
            }
        }
        
        let finalText = fullText
        let cacheURL = self.cacheDirectory.appendingPathComponent("\(documentID.uuidString).txt")
        try? finalText.write(to: cacheURL, atomically: true, encoding: .utf8)
        
        await MainActor.run {
            self.memoryCache[documentID] = finalText
            self.indexedDocumentIDs.insert(documentID)
        }
    }
    
    private func extractTextFromImage(page: PDFPage) async -> String {
        let rect = page.bounds(for: .mediaBox)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2.0
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        let image = renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(rect)
            ctx.cgContext.translateBy(x: 0.0, y: rect.size.height)
            ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        
        guard let cgImage = image.cgImage else { return "" }
        
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                    continuation.resume(returning: "")
                    return
                }
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                continuation.resume(returning: text)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}
