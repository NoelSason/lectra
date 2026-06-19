//
//  LectraDocumentIndex.swift
//  Lectra
//
//  A lightweight, view-independent accessor over the documents Lectra has
//  saved locally, so App Intents (Siri / Spotlight / Shortcuts) can resolve
//  and act on a document without the library UI being on screen.
//
//  It reads the same persisted store the library writes (`lectra_local_pdfs`,
//  an array of `SavedLocalDocument`) and reconstructs each PDF's on-disk URL.
//

import Foundation

struct LectraIndexedDocument: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let url: URL
}

enum LectraDocumentIndex {
    /// Matches `DocumentBrowserView.localPDFsDefaultsKey`.
    nonisolated private static let localPDFsDefaultsKey = "lectra_local_pdfs"

    /// All locally-available documents, most recently updated first.
    nonisolated static func all() -> [LectraIndexedDocument] {
        guard let data = UserDefaults.standard.data(forKey: localPDFsDefaultsKey),
              let saved = try? JSONDecoder().decode([SavedLocalDocument].self, from: data) else {
            return []
        }

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        let resolved: [(LectraIndexedDocument, Date)] = saved.compactMap { item in
            let url = documentsDir.appendingPathComponent(item.localPath)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let doc = LectraIndexedDocument(id: item.id, title: title.isEmpty ? "Untitled PDF" : title, url: url)
            return (doc, item.updatedAt ?? item.createdAt ?? .distantPast)
        }

        return resolved
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    nonisolated static func document(for id: UUID) -> LectraIndexedDocument? {
        all().first { $0.id == id }
    }

    nonisolated static func search(_ query: String) -> [LectraIndexedDocument] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all() }
        return all().filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }
}
