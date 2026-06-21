//
//  DocumentItem.swift
//  Lectra
//
//  Data models that map to the Supabase `synced_items` table
//  when `item_type == "pdf_document"`.
//

import Foundation
import Combine

// MARK: - Supabase Row Model

/// Represents a single row in the `synced_items` table.
struct SyncedItem: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let itemType: String
    let itemData: DocumentData
    let syncStatus: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId    = "user_id"
        case itemType  = "item_type"
        case itemData  = "item_data"
        case syncStatus = "sync_status"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - PDF Document Metadata (inside item_data JSONB)

/// The JSON payload stored inside `item_data` for pdf_document items.
struct DocumentData: Codable, Equatable {
    var title: String
    let courseId: Int?
    let sourceUrl: String?
    let storagePath: String
    var annotatedStoragePath: String?
    var status: String   // "pending_annotation" | "annotated" | "archived"
    /// Course-level import metadata (present on Canvascope course imports).
    /// Used to nest imports under "Imported From Canvascope / <Course> / <subfolder>".
    let courseName: String?
    let folderPath: String?        // e.g. "Discussions > 202 > Solutions"
    let pathSegments: [String]?    // e.g. ["Discussions", "202", "Solutions"]

    enum CodingKeys: String, CodingKey {
        case title
        case courseId           = "courseId"
        case sourceUrl          = "sourceUrl"
        case storagePath        = "storagePath"
        case annotatedStoragePath = "annotatedStoragePath"
        case status
        case courseName         = "courseName"
        case folderPath         = "folderPath"
        case pathSegments       = "pathSegments"
    }

    init(
        title: String,
        courseId: Int?,
        sourceUrl: String?,
        storagePath: String,
        annotatedStoragePath: String?,
        status: String,
        courseName: String? = nil,
        folderPath: String? = nil,
        pathSegments: [String]? = nil
    ) {
        self.title = title
        self.courseId = courseId
        self.sourceUrl = sourceUrl
        self.storagePath = storagePath
        self.annotatedStoragePath = annotatedStoragePath
        self.status = status
        self.courseName = courseName
        self.folderPath = folderPath
        self.pathSegments = pathSegments
    }

    /// Ordered folder chain to nest this import under the Canvascope folder:
    /// the course name followed by the Canvas subfolder segments. Empty when
    /// the document has no course/folder metadata (legacy single-file sends).
    var importFolderChain: [String] {
        var chain: [String] = []
        if let courseName = courseName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !courseName.isEmpty {
            chain.append(courseName)
        }
        let segments: [String]
        if let pathSegments, !pathSegments.isEmpty {
            segments = pathSegments
        } else if let folderPath, !folderPath.isEmpty {
            segments = folderPath.components(separatedBy: ">")
        } else {
            segments = []
        }
        for segment in segments {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { chain.append(trimmed) }
        }
        return chain
    }
}

// MARK: - Local Document (view-model for the app)

/// A local view-model that wraps a SyncedItem and adds download state.
final class LocalDocument: Identifiable, ObservableObject {
    let id: UUID
    @Published var title: String
    let courseId: Int?
    let sourceURLString: String?
    let storagePath: String
    let supabaseRowId: UUID
    let sourceDocumentData: DocumentData?
    @Published var isFavorite: Bool
    @Published var status: DocumentStatus
    @Published var localPDFURL: URL?
    let createdAt: Date
    @Published var updatedAt: Date
    @Published var syncState: DocumentSyncState = .idle
    @Published var syncErrorMessage: String?
    @Published var dirtyPageIndexes: Set<Int> = []
    @Published var lastLocalEditAt: Date?
    @Published var lastRemoteSyncAt: Date?
    @Published var lastOpenedPage: Int = 0
    @Published var thumbnailRevision: Int = 0
    @Published var searchIndexRevision: Int = 0

    private static let isoParserWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    init(from item: SyncedItem) {
        self.id = item.id
        self.title = item.itemData.title
        self.courseId = item.itemData.courseId
        self.sourceURLString = item.itemData.sourceUrl
        self.storagePath = item.itemData.storagePath
        self.supabaseRowId = item.id
        self.sourceDocumentData = item.itemData
        self.isFavorite = false
        self.status = DocumentStatus(rawValue: item.itemData.status) ?? .pendingAnnotation
        let created = Self.parseISODate(item.createdAt) ?? Date()
        self.createdAt = created
        self.updatedAt = Self.parseISODate(item.updatedAt) ?? created
    }

    /// Convenience init for locally-imported PDFs (not from Supabase).
    init(
        title: String,
        localURL: URL,
        id: UUID = UUID(),
        isFavorite: Bool = false,
        sourceURLString: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.isFavorite = isFavorite
        self.courseId = nil
        self.sourceURLString = sourceURLString
        self.storagePath = ""
        self.supabaseRowId = UUID()
        self.sourceDocumentData = nil
        self.status = .local
        self.localPDFURL = localURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private static func parseISODate(_ raw: String) -> Date? {
        if let parsed = isoParserWithFractionalSeconds.date(from: raw) {
            return parsed
        }
        return isoParser.date(from: raw)
    }

    var isRemoteBacked: Bool {
        sourceDocumentData != nil
    }

    func apply(metadata: DocumentLocalMetadata) {
        syncState = metadata.syncState
        syncErrorMessage = metadata.syncErrorMessage
        dirtyPageIndexes = Set(metadata.dirtyPageIndexes)
        lastLocalEditAt = metadata.lastLocalEditAt
        lastRemoteSyncAt = metadata.lastRemoteSyncAt
        lastOpenedPage = metadata.lastOpenedPage ?? 0
        thumbnailRevision = metadata.thumbnailRevision
        searchIndexRevision = metadata.searchIndexRevision
    }
}

// MARK: - Status Enum

enum DocumentStatus: String {
    case pendingAnnotation = "pending_annotation"
    case annotated         = "annotated"
    case archived          = "archived"
    case local             = "local"          // imported locally, not from Supabase
    case downloading       = "downloading"
    case error             = "error"
}
