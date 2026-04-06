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

    // MARK: - Fetch Document List

    /// Pulls all `pdf_document` rows for the authenticated user.
    func fetchDocuments() async throws -> [SyncedItem] {
        let items: [SyncedItem] = try await client
            .from("synced_items")
            .select()
            .eq("item_type", value: "pdf_document")
            .order("created_at", ascending: false)
            .execute()
            .value
        return items
    }

    // MARK: - Download PDF

    /// Downloads the raw PDF from Supabase Storage and saves it locally.
    /// Returns the local file URL.
    @discardableResult
    func downloadPDF(storagePath: String, documentId: UUID) async throws -> URL {
        let data = try await client.storage
            .from(bucketName)
            .download(path: storagePath)

        let localURL = localPDFURL(for: documentId)
        try data.write(to: localURL)
        return localURL
    }

    // MARK: - Upload Annotated PDF

    /// Uploads the flattened, annotated PDF back to Supabase Storage.
    func uploadAnnotatedPDF(data: Data, userId: UUID, documentId: UUID) async throws -> String {
        let path = "\(userId.uuidString)/lectra_documents/annotated-\(documentId.uuidString).pdf"

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

    // MARK: - Check if PDF is cached

    func isPDFCachedLocally(documentId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: localPDFURL(for: documentId).path)
    }
}
