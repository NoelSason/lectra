//
//  DocumentRepository.swift
//  Lectra
//
//  Handles all Supabase interactions for PDF documents:
//  fetching the document list, downloading PDFs, uploading annotated PDFs,
//  and updating row status.
//

import Foundation
import Supabase

nonisolated final class DocumentRepository {

    // MARK: - Private
    private let client = SupabaseManager.shared.client
    private let bucketName = "lectra_documents"

    // MARK: - Local Storage Helpers

    /// Returns the app's Documents directory for storing downloaded PDFs.
    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Returns (and creates) the folder for a specific document's files.
    private func localFolder(for documentId: UUID) -> URL {
        let folder = documentsDirectory
            .appendingPathComponent("pdfs", isDirectory: true)
            .appendingPathComponent(documentId.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Path to the raw (original) PDF on disk.
    func localPDFURL(for documentId: UUID) -> URL {
        localFolder(for: documentId).appendingPathComponent("original.pdf")
    }

    /// Path to the drawings data on disk.
    func localDrawingsURL(for documentId: UUID) -> URL {
        localFolder(for: documentId).appendingPathComponent("drawings.dat")
    }

    /// Path to the semantic annotation sidecar on disk.
    func localAnnotationsURL(for documentId: UUID) -> URL {
        localFolder(for: documentId).appendingPathComponent("annotations.json")
    }

    /// Path to the flattened annotated PDF on disk.
    func localAnnotatedPDFURL(for documentId: UUID) -> URL {
        localFolder(for: documentId).appendingPathComponent("annotated.pdf")
    }

    /// Path to the local metadata sidecar.
    func localMetadataURL(for documentId: UUID) -> URL {
        localFolder(for: documentId).appendingPathComponent("metadata.json")
    }

    /// Shared sync queue store.
    func syncQueueURL() -> URL {
        let folder = documentsDirectory.appendingPathComponent("sync", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("pending-sync-jobs.json")
    }

    func ocrQueueURL() -> URL {
        let folder = documentsDirectory.appendingPathComponent("ocr", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("pending-ocr-jobs.json")
    }

    func assetLibraryURL() -> URL {
        let folder = documentsDirectory.appendingPathComponent("assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("reusable-assets.json")
    }

    // MARK: - Fetch Document List

    /// Pulls all `pdf_document` rows for the authenticated user.
    func fetchDocuments() async throws -> [SyncedItem] {
        let userId = try await resolveUserId()
        let items: [SyncedItem] = try await client
            .from("synced_items")
            .select()
            .eq("item_type", value: "pdf_document")
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        return items
    }

    private func resolveUserId() async throws -> UUID {
        if let userId = client.auth.currentSession?.user.id {
            return userId
        }

        let session = try await client.auth.session
        return session.user.id
    }

    // MARK: - Download PDF

    /// Downloads the raw PDF from Supabase Storage and saves it locally.
    /// Returns the local file URL.
    ///
    /// Streams straight to disk via a short-lived signed URL instead of buffering
    /// the whole file in memory, so many prefetches can run in parallel without a
    /// memory spike. Falls back to the SDK's buffered download if signing fails.
    @discardableResult
    func downloadPDF(storagePath: String, documentId: UUID) async throws -> URL {
        let localURL = localPDFURL(for: documentId)

        do {
            let signedURL = try await client.storage
                .from(bucketName)
                .createSignedURL(path: storagePath, expiresIn: 300)

            let (tempURL, _) = try await URLSession.shared.download(from: signedURL)
            if FileManager.default.fileExists(atPath: localURL.path) {
                try? FileManager.default.removeItem(at: localURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: localURL)
            return localURL
        } catch {
            let data = try await client.storage
                .from(bucketName)
                .download(path: storagePath)
            try data.write(to: localURL)
            return localURL
        }
    }

    // MARK: - Upload Annotated PDF

    /// Uploads the flattened, annotated PDF back to Supabase Storage.
    func uploadAnnotatedPDF(data: Data, userId: UUID, documentId: UUID) async throws -> String {
        // Storage RLS compares foldername[1] against auth.uid()::text, which Postgres
        // emits lowercase. Swift's UUID.uuidString is uppercase, so the path must be
        // lowercased or the INSERT is rejected with a 403 row-level-security error.
        let path = "\(userId.uuidString.lowercased())/lectra_documents/annotated-\(documentId.uuidString.lowercased()).pdf"

        try await client.storage
            .from(bucketName)
            .upload(
                path,
                data: data,
                options: FileOptions(contentType: "application/pdf", upsert: true)
            )

        return path
    }

    // MARK: - Update Row Status

    /// Wrapper struct so Supabase gets a concrete Encodable type.
    private struct ItemDataUpdate: Encodable {
        let item_data: DocumentData
    }

    /// Updates the `synced_items` row to mark the document as annotated.
    func markAsAnnotated(rowId: UUID, annotatedPath: String, currentItemData: DocumentData) async throws {
        var updated = currentItemData
        updated.annotatedStoragePath = annotatedPath
        updated.status = "annotated"

        try await client
            .from("synced_items")
            .update(ItemDataUpdate(item_data: updated))
            .eq("id", value: rowId.uuidString)
            .execute()
    }

    // MARK: - Save / Load Drawings Locally

    /// Persist PencilKit drawing data to disk so the user doesn't lose work.
    func saveDrawingsLocally(data: Data, documentId: UUID) throws {
        let url = localDrawingsURL(for: documentId)
        try data.write(to: url)
    }

    /// Load previously-saved drawing data from disk.
    func loadLocalDrawings(documentId: UUID) -> Data? {
        let url = localDrawingsURL(for: documentId)
        return try? Data(contentsOf: url)
    }

    func saveLocalAnnotations(_ store: LectraAnnotationStore, documentId: UUID) throws {
        let url = localAnnotationsURL(for: documentId)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(store)
        try data.write(to: url, options: [.atomic])
    }

    func loadLocalAnnotations(documentId: UUID) -> LectraAnnotationStore? {
        let url = localAnnotationsURL(for: documentId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LectraAnnotationStore.self, from: data)
    }

    func saveLocalMetadata(_ metadata: DocumentLocalMetadata, documentId: UUID) {
        let url = localMetadataURL(for: documentId)
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    func loadLocalMetadata(documentId: UUID) -> DocumentLocalMetadata {
        let url = localMetadataURL(for: documentId)
        guard let data = try? Data(contentsOf: url),
              let metadata = try? JSONDecoder().decode(DocumentLocalMetadata.self, from: data) else {
            return DocumentLocalMetadata()
        }
        return metadata
    }

    func savePendingSyncJobs(_ jobs: [PendingSyncJob]) {
        let url = syncQueueURL()
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    func loadPendingSyncJobs() -> [PendingSyncJob] {
        let url = syncQueueURL()
        guard let data = try? Data(contentsOf: url),
              let jobs = try? JSONDecoder().decode([PendingSyncJob].self, from: data) else {
            return []
        }
        return jobs
    }

    func savePendingOCRJobs(_ jobs: [PDFOCRWorkItem]) {
        let url = ocrQueueURL()
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    func loadPendingOCRJobs() -> [PDFOCRWorkItem] {
        let url = ocrQueueURL()
        guard let data = try? Data(contentsOf: url),
              let jobs = try? JSONDecoder().decode([PDFOCRWorkItem].self, from: data) else {
            return []
        }
        return jobs
    }

    func mergePendingOCRJobs(_ jobs: [PDFOCRWorkItem]) {
        guard !jobs.isEmpty else { return }
        var current = loadPendingOCRJobs()
        var existingKeys = Set(current.map { "\($0.documentId.uuidString):\($0.pageIndex)" })
        for job in jobs {
            let key = "\(job.documentId.uuidString):\(job.pageIndex)"
            guard !existingKeys.contains(key) else { continue }
            current.append(job)
            existingKeys.insert(key)
        }
        savePendingOCRJobs(current)
    }

    func saveAssetLibrary(_ library: LectraAssetLibrary) throws {
        let url = assetLibraryURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(library)
        try data.write(to: url, options: [.atomic])
    }

    func loadAssetLibrary() -> LectraAssetLibrary {
        let url = assetLibraryURL()
        guard let data = try? Data(contentsOf: url),
              let library = try? JSONDecoder().decode(LectraAssetLibrary.self, from: data) else {
            return LectraAssetLibrary()
        }
        return library
    }

    // MARK: - Check if PDF is cached

    func isPDFCachedLocally(documentId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: localPDFURL(for: documentId).path)
    }

    // MARK: - Delete Remote Document

    /// Deletes the document row from Supabase.
    func deleteRemoteDocument(rowId: UUID) async throws {
        try await client
            .from("synced_items")
            .delete()
            .eq("id", value: rowId.uuidString)
            .execute()
    }
}
