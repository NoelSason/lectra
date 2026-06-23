import Foundation
import UIKit
import PDFKit

nonisolated enum DocumentSyncState: String, Codable, CaseIterable, Sendable {
    case idle
    case savingLocal
    case flattening
    case queuedUpload
    case uploading
    case synced
    case failed
}

nonisolated enum DocumentConflictState: String, Codable, CaseIterable, Sendable {
    case none
    case needsReview
    case resolved
}

nonisolated enum ICloudMirrorState: String, Codable, CaseIterable, Sendable {
    case unknown
    case pending
    case mirrored
    case unavailable
    case failed
}

nonisolated struct DocumentLocalMetadata: Codable, Equatable, Sendable {
    var syncState: DocumentSyncState = .idle
    var syncErrorMessage: String?
    var dirtyPageIndexes: [Int] = []
    var lastLocalEditAt: Date?
    var lastRemoteSyncAt: Date?
    var lastOpenedPage: Int?
    var thumbnailRevision: Int = 0
    var searchIndexRevision: Int = 0
    var annotationSchemaVersion: Int = LectraAnnotationStore.currentVersion
    var lastLocalCheckpointAt: Date?
    var lastUploadAttemptAt: Date?
    var lastSuccessfulUploadAt: Date?
    var nextRetryAt: Date?
    var conflictState: DocumentConflictState = .none
    var iCloudMirrorState: ICloudMirrorState = .unknown
    var lastICloudMirrorAt: Date?
    var iCloudMirrorErrorMessage: String?
    var ocrState: PDFOCRState = .unknown
    var ocrCheckedAt: Date?
    var ocrSampledPageIndexes: [Int] = []
    var ocrExtractedCharacterCount: Int = 0
    var ocrQueuedPageIndexes: [Int] = []

    init(
        syncState: DocumentSyncState = .idle,
        syncErrorMessage: String? = nil,
        dirtyPageIndexes: [Int] = [],
        lastLocalEditAt: Date? = nil,
        lastRemoteSyncAt: Date? = nil,
        lastOpenedPage: Int? = nil,
        thumbnailRevision: Int = 0,
        searchIndexRevision: Int = 0,
        annotationSchemaVersion: Int = LectraAnnotationStore.currentVersion,
        lastLocalCheckpointAt: Date? = nil,
        lastUploadAttemptAt: Date? = nil,
        lastSuccessfulUploadAt: Date? = nil,
        nextRetryAt: Date? = nil,
        conflictState: DocumentConflictState = .none,
        iCloudMirrorState: ICloudMirrorState = .unknown,
        lastICloudMirrorAt: Date? = nil,
        iCloudMirrorErrorMessage: String? = nil,
        ocrState: PDFOCRState = .unknown,
        ocrCheckedAt: Date? = nil,
        ocrSampledPageIndexes: [Int] = [],
        ocrExtractedCharacterCount: Int = 0,
        ocrQueuedPageIndexes: [Int] = []
    ) {
        self.syncState = syncState
        self.syncErrorMessage = syncErrorMessage
        self.dirtyPageIndexes = dirtyPageIndexes
        self.lastLocalEditAt = lastLocalEditAt
        self.lastRemoteSyncAt = lastRemoteSyncAt
        self.lastOpenedPage = lastOpenedPage
        self.thumbnailRevision = thumbnailRevision
        self.searchIndexRevision = searchIndexRevision
        self.annotationSchemaVersion = annotationSchemaVersion
        self.lastLocalCheckpointAt = lastLocalCheckpointAt
        self.lastUploadAttemptAt = lastUploadAttemptAt
        self.lastSuccessfulUploadAt = lastSuccessfulUploadAt
        self.nextRetryAt = nextRetryAt
        self.conflictState = conflictState
        self.iCloudMirrorState = iCloudMirrorState
        self.lastICloudMirrorAt = lastICloudMirrorAt
        self.iCloudMirrorErrorMessage = iCloudMirrorErrorMessage
        self.ocrState = ocrState
        self.ocrCheckedAt = ocrCheckedAt
        self.ocrSampledPageIndexes = ocrSampledPageIndexes
        self.ocrExtractedCharacterCount = ocrExtractedCharacterCount
        self.ocrQueuedPageIndexes = ocrQueuedPageIndexes
    }

    private enum CodingKeys: String, CodingKey {
        case syncState
        case syncErrorMessage
        case dirtyPageIndexes
        case lastLocalEditAt
        case lastRemoteSyncAt
        case lastOpenedPage
        case thumbnailRevision
        case searchIndexRevision
        case annotationSchemaVersion
        case lastLocalCheckpointAt
        case lastUploadAttemptAt
        case lastSuccessfulUploadAt
        case nextRetryAt
        case conflictState
        case iCloudMirrorState
        case lastICloudMirrorAt
        case iCloudMirrorErrorMessage
        case ocrState
        case ocrCheckedAt
        case ocrSampledPageIndexes
        case ocrExtractedCharacterCount
        case ocrQueuedPageIndexes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        syncState = try container.decodeIfPresent(DocumentSyncState.self, forKey: .syncState) ?? .idle
        syncErrorMessage = try container.decodeIfPresent(String.self, forKey: .syncErrorMessage)
        dirtyPageIndexes = try container.decodeIfPresent([Int].self, forKey: .dirtyPageIndexes) ?? []
        lastLocalEditAt = try container.decodeIfPresent(Date.self, forKey: .lastLocalEditAt)
        lastRemoteSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastRemoteSyncAt)
        lastOpenedPage = try container.decodeIfPresent(Int.self, forKey: .lastOpenedPage)
        thumbnailRevision = try container.decodeIfPresent(Int.self, forKey: .thumbnailRevision) ?? 0
        searchIndexRevision = try container.decodeIfPresent(Int.self, forKey: .searchIndexRevision) ?? 0
        annotationSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .annotationSchemaVersion) ?? 1
        lastLocalCheckpointAt = try container.decodeIfPresent(Date.self, forKey: .lastLocalCheckpointAt)
        lastUploadAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastUploadAttemptAt)
        lastSuccessfulUploadAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulUploadAt)
        nextRetryAt = try container.decodeIfPresent(Date.self, forKey: .nextRetryAt)
        conflictState = try container.decodeIfPresent(DocumentConflictState.self, forKey: .conflictState) ?? .none
        iCloudMirrorState = try container.decodeIfPresent(ICloudMirrorState.self, forKey: .iCloudMirrorState) ?? .unknown
        lastICloudMirrorAt = try container.decodeIfPresent(Date.self, forKey: .lastICloudMirrorAt)
        iCloudMirrorErrorMessage = try container.decodeIfPresent(String.self, forKey: .iCloudMirrorErrorMessage)
        ocrState = try container.decodeIfPresent(PDFOCRState.self, forKey: .ocrState) ?? .unknown
        ocrCheckedAt = try container.decodeIfPresent(Date.self, forKey: .ocrCheckedAt)
        ocrSampledPageIndexes = try container.decodeIfPresent([Int].self, forKey: .ocrSampledPageIndexes) ?? []
        ocrExtractedCharacterCount = try container.decodeIfPresent(Int.self, forKey: .ocrExtractedCharacterCount) ?? 0
        ocrQueuedPageIndexes = try container.decodeIfPresent([Int].self, forKey: .ocrQueuedPageIndexes) ?? []
    }
}

extension DocumentLocalMetadata {
    nonisolated func updatingForRecoverySnapshot(
        lastOpenedPage: Int,
        dirtyPageIndexes: [Int],
        editedAt: Date?
    ) -> DocumentLocalMetadata {
        var metadata = self
        metadata.lastOpenedPage = lastOpenedPage
        metadata.dirtyPageIndexes = dirtyPageIndexes
        if let editedAt {
            metadata.lastLocalEditAt = editedAt
            metadata.lastLocalCheckpointAt = editedAt
        }
        metadata.annotationSchemaVersion = LectraAnnotationStore.currentVersion
        return metadata
    }

    nonisolated mutating func markLocalCheckpoint(
        editedAt: Date,
        lastOpenedPage: Int,
        dirtyPageIndexes: [Int]
    ) {
        self.lastLocalEditAt = editedAt
        self.lastLocalCheckpointAt = editedAt
        self.lastOpenedPage = lastOpenedPage
        self.dirtyPageIndexes = dirtyPageIndexes
        self.annotationSchemaVersion = LectraAnnotationStore.currentVersion
    }

    nonisolated mutating func markUploadQueued() {
        syncState = .queuedUpload
        syncErrorMessage = nil
        nextRetryAt = nil
    }

    nonisolated mutating func markUploadAttempt(at attemptedAt: Date) {
        syncState = .uploading
        syncErrorMessage = nil
        lastUploadAttemptAt = attemptedAt
        nextRetryAt = nil
    }

    nonisolated mutating func markUploadSucceeded(at uploadedAt: Date) {
        syncState = .synced
        syncErrorMessage = nil
        lastRemoteSyncAt = uploadedAt
        lastSuccessfulUploadAt = uploadedAt
        dirtyPageIndexes = []
        nextRetryAt = nil
        conflictState = .none
    }

    nonisolated mutating func markUploadFailed(message: String, nextRetryAt retryAt: Date?) {
        syncState = .failed
        syncErrorMessage = message
        nextRetryAt = retryAt
    }

    nonisolated mutating func applyOCRDetection(_ result: PDFOCRDetectionResult) {
        ocrState = result.state
        ocrCheckedAt = result.checkedAt
        ocrSampledPageIndexes = result.sampledPageIndexes
        ocrExtractedCharacterCount = result.extractedCharacterCount
        ocrQueuedPageIndexes = result.needsOCR ? result.sampledPageIndexes : []
    }
}

struct DocumentSaveResult: Codable, Equatable {
    let documentId: UUID
    let annotatedFilePath: String?
    let localEditAt: Date
    let lastOpenedPage: Int
    let dirtyPageIndexes: [Int]
}

struct PendingSyncJob: Codable, Identifiable, Equatable {
    let id: UUID
    let documentId: UUID
    let rowId: UUID
    let userId: UUID
    let itemData: DocumentData
    let annotatedFilePath: String
    let queuedAt: Date
    var retryCount: Int
    var nextRetryAt: Date?
    var lastErrorMessage: String?
}

final class DocumentSyncStatusPayload {
    let documentId: UUID
    let metadata: DocumentLocalMetadata

    init(documentId: UUID, metadata: DocumentLocalMetadata) {
        self.documentId = documentId
        self.metadata = metadata
    }
}

final class ICloudSyncStatusPayload {
    let documentId: UUID
    let syncedAt: Date
    let errorMessage: String?

    init(documentId: UUID, syncedAt: Date, errorMessage: String?) {
        self.documentId = documentId
        self.syncedAt = syncedAt
        self.errorMessage = errorMessage
    }
}

final class RemoteDocumentsChangePayload {
    let documentIds: [UUID]
    let reason: String

    init(documentIds: [UUID], reason: String) {
        self.documentIds = documentIds
        self.reason = reason
    }
}

struct DocumentSearchResult: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case metadata
        case pageText
    }

    let documentId: UUID
    let title: String
    let subtitle: String
    let snippet: String?
    let pageIndex: Int?
    let kind: Kind

    var id: String {
        [
            documentId.uuidString,
            kind.rawValue,
            pageIndex.map(String.init) ?? "metadata",
            subtitle,
        ]
        .joined(separator: ":")
    }
}

enum RecoverySnapshotLocation: String, Codable {
    case onDevice
    case iCloudDrive
}

nonisolated enum LectraLocalAccountData {
    static let localOwnerUserIdDefaultsKey = "lectra_local_owner_user_id"
    static let localPDFsDefaultsKey = "lectra_local_pdfs"
    static let localFoldersDefaultsKey = "lectra_local_folders"
    static let documentFolderMapDefaultsKey = "lectra_document_folder_map"
    static let titleOverridesDefaultsKey = "lectra_document_title_overrides"
    static let recentDocumentsDefaultsKey = "lectra_recently_opened_documents"
    static let cloudSyncEnabledDefaultsKey = "lectra_cloud_sync_enabled"
    static let autoBackupEnabledDefaultsKey = "lectra_auto_backup_enabled"
    static let lastCloudSyncDefaultsKey = "lectra_last_cloud_sync"
    static let lastBackupDefaultsKey = "lectra_last_backup"

    static func ownerUserId() -> UUID? {
        guard let value = UserDefaults.standard.string(forKey: localOwnerUserIdDefaultsKey) else { return nil }
        return UUID(uuidString: value)
    }

    static func markOwner(_ userId: UUID) {
        UserDefaults.standard.set(userId.uuidString, forKey: localOwnerUserIdDefaultsKey)
    }

    static func hasUnownedLocalDocuments() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: localPDFsDefaultsKey),
              let saved = try? JSONDecoder().decode([SavedLocalDocument].self, from: data) else {
            return false
        }
        return saved.contains { $0.ownerUserId == nil }
    }

    @MainActor
    static func purgeAccountScopedData() {
        let defaults = UserDefaults.standard
        [
            localOwnerUserIdDefaultsKey,
            localPDFsDefaultsKey,
            localFoldersDefaultsKey,
            documentFolderMapDefaultsKey,
            titleOverridesDefaultsKey,
            recentDocumentsDefaultsKey,
            cloudSyncEnabledDefaultsKey,
            autoBackupEnabledDefaultsKey,
            lastCloudSyncDefaultsKey,
            lastBackupDefaultsKey,
        ].forEach { defaults.removeObject(forKey: $0) }

        let fileManager = FileManager.default
        let documentsRoot = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        [
            documentsRoot.appendingPathComponent("pdfs", isDirectory: true),
            documentsRoot.appendingPathComponent("sync", isDirectory: true),
            documentsRoot.appendingPathComponent("LectraBackups", isDirectory: true),
        ].forEach { try? fileManager.removeItem(at: $0) }

        ThumbnailCache.shared.removeAll()
        DocumentSearchIndex.shared.removeAll()
        LegacyThirdPartyIntegrationData.clearFromDevice()
    }
}

struct RecoverySnapshotManifestItem: Codable, Hashable {
    let id: UUID
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let relativePDFPath: String?
    let folderId: UUID?
    var isFavorite: Bool?
    var checksum: String?
}

struct RecoverySnapshotManifest: Codable {
    let createdAt: Date
    let source: String
    let ownerUserId: UUID?
    let folders: [SavedLocalFolder]
    let items: [RecoverySnapshotManifestItem]
}

struct RecoverySnapshot: Identifiable, Hashable {
    let id: String
    let manifestURL: URL
    let snapshotFolderURL: URL
    let createdAt: Date
    let source: String
    let itemCount: Int
    let location: RecoverySnapshotLocation
    let ownerUserId: UUID?
    let items: [RecoverySnapshotManifestItem]
}

extension Notification.Name {
    static let lectraDocumentSyncStateDidChange = Notification.Name("lectraDocumentSyncStateDidChange")
    static let lectraEditorPreferencesDidChange = Notification.Name("lectraEditorPreferencesDidChange")
    static let lectraICloudSyncDidChange = Notification.Name("lectraICloudSyncDidChange")
    static let lectraRemoteDocumentsDidChange = Notification.Name("lectraRemoteDocumentsDidChange")
}

enum ICloudDocumentStoreError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "iCloud Drive is unavailable right now."
        }
    }
}

final class ICloudDocumentStore {
    static let shared = ICloudDocumentStore()

    private let lastCloudSyncDefaultsKey = "lectra_last_cloud_sync"

    private init() {}

    func isAvailable() -> Bool {
        FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil
    }

    func mirrorDocument(
        documentId: UUID,
        title: String,
        originalPDFURL: URL?,
        annotatedPDFURL: URL?,
        metadata: DocumentLocalMetadata
    ) async throws {
        let mirroredAt = Date()

        do {
            try await Task.detached(priority: .utility) {
                let root = try self.documentsRootURL()
                let documentFolder = root.appendingPathComponent(documentId.uuidString, isDirectory: true)
                try FileManager.default.createDirectory(
                    at: documentFolder,
                    withIntermediateDirectories: true
                )

                let originalDestination = documentFolder.appendingPathComponent("original.pdf")
                let annotatedDestination = documentFolder.appendingPathComponent("annotated.pdf")

                try self.copyIfPresent(source: originalPDFURL, destination: originalDestination)
                try self.copyIfPresent(source: annotatedPDFURL, destination: annotatedDestination)

                let preferredFileName: String?
                if FileManager.default.fileExists(atPath: annotatedDestination.path) {
                    preferredFileName = "annotated.pdf"
                } else if FileManager.default.fileExists(atPath: originalDestination.path) {
                    preferredFileName = "original.pdf"
                } else {
                    preferredFileName = nil
                }

                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                let manifestObject: [String: Any?] = [
                    "documentId": documentId.uuidString,
                    "title": title,
                    "mirroredAt": formatter.string(from: mirroredAt),
                    "lastLocalEditAt": metadata.lastLocalEditAt.map(formatter.string(from:)),
                    "lastRemoteSyncAt": metadata.lastRemoteSyncAt.map(formatter.string(from:)),
                    "lastLocalCheckpointAt": metadata.lastLocalCheckpointAt.map(formatter.string(from:)),
                    "lastUploadAttemptAt": metadata.lastUploadAttemptAt.map(formatter.string(from:)),
                    "lastSuccessfulUploadAt": metadata.lastSuccessfulUploadAt.map(formatter.string(from:)),
                    "nextRetryAt": metadata.nextRetryAt.map(formatter.string(from:)),
                    "lastOpenedPage": metadata.lastOpenedPage,
                    "annotationSchemaVersion": metadata.annotationSchemaVersion,
                    "syncState": metadata.syncState.rawValue,
                    "conflictState": metadata.conflictState.rawValue,
                    "iCloudMirrorState": metadata.iCloudMirrorState.rawValue,
                    "ocrState": metadata.ocrState.rawValue,
                    "preferredFileName": preferredFileName,
                ]
                let manifest = manifestObject.compactMapValues { $0 }
                let data = try JSONSerialization.data(
                    withJSONObject: manifest,
                    options: [.prettyPrinted, .sortedKeys]
                )
                try data.write(
                    to: documentFolder.appendingPathComponent("manifest.json"),
                    options: [.atomic]
                )
            }.value

            let payload = ICloudSyncStatusPayload(
                documentId: documentId,
                syncedAt: mirroredAt,
                errorMessage: nil
            )
            UserDefaults.standard.set(mirroredAt, forKey: lastCloudSyncDefaultsKey)
            NotificationCenter.default.post(name: .lectraICloudSyncDidChange, object: payload)
        } catch {
            let payload = ICloudSyncStatusPayload(
                documentId: documentId,
                syncedAt: mirroredAt,
                errorMessage: error.localizedDescription
            )
            NotificationCenter.default.post(name: .lectraICloudSyncDidChange, object: payload)
            throw error
        }
    }

    func mirrorDocuments(_ documents: [LocalDocument], repository: DocumentRepository) async throws {
        for document in documents {
            let originalURL = repository.localPDFURL(for: document.id)
            let annotatedURL = repository.localAnnotatedPDFURL(for: document.id)
            let metadata = repository.loadLocalMetadata(documentId: document.id)
            let resolvedOriginalURL = FileManager.default.fileExists(atPath: originalURL.path) ? originalURL : nil
            let resolvedAnnotatedURL = FileManager.default.fileExists(atPath: annotatedURL.path) ? annotatedURL : nil

            guard resolvedOriginalURL != nil || resolvedAnnotatedURL != nil else { continue }

            try await mirrorDocument(
                documentId: document.id,
                title: document.title,
                originalPDFURL: resolvedOriginalURL,
                annotatedPDFURL: resolvedAnnotatedURL,
                metadata: metadata
            )
        }
    }

    func deleteMirroredDocument(documentId: UUID) async {
        await Task.detached(priority: .utility) {
            guard let root = try? self.documentsRootURL() else { return }
            let documentFolder = root.appendingPathComponent(documentId.uuidString, isDirectory: true)
            try? FileManager.default.removeItem(at: documentFolder)
        }.value
    }

    private nonisolated func documentsRootURL() throws -> URL {
        guard let ubiquitousRoot = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            throw ICloudDocumentStoreError.unavailable
        }

        let documentsRoot = ubiquitousRoot
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("LectraDocuments", isDirectory: true)
        try FileManager.default.createDirectory(at: documentsRoot, withIntermediateDirectories: true)
        return documentsRoot
    }

    private nonisolated func copyIfPresent(source: URL?, destination: URL) throws {
        guard let source, FileManager.default.fileExists(atPath: source.path) else {
            try? FileManager.default.removeItem(at: destination)
            return
        }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
    }
}

enum EditorHandedness: String, Codable, CaseIterable {
    case right
    case left
}

enum PencilSqueezeAction: String, Codable, CaseIterable {
    case togglePenEraser
    case undo
    case redo
}

struct EditorPreferences: Codable, Equatable {
    var selectedTool: AnnotationTool = .pen
    var selectedColor: AnnotationInkColor = .accent
    var selectedStrokeWidth: CGFloat = 2.0
    var selectedEraserMode: EraserMode = .stroke
    var lastAnnotationTool: AnnotationTool = .pen
    var highlighterOpacity: CGFloat = 0.35
    var toolbarDockEdge: String = "bottom"
    var dockEdgesByProfile: [String: String] = [:]
    var handedness: EditorHandedness = .right
    var squeezeAction: PencilSqueezeAction = .togglePenEraser
    var hasSeenLassoHint = false
    var hasSeenSqueezeHint = false
    var hasSeenDoubleTapHint = false

    func dockEdge(for profile: EditorDockProfile) -> EditorToolbarDockEdge {
        if let rawValue = dockEdgesByProfile[profile.rawValue],
           let edge = EditorToolbarDockEdge(rawValue: rawValue) {
            return profile.normalizedDockEdge(edge, handedness: handedness)
        }

        if let legacyEdge = EditorToolbarDockEdge(rawValue: toolbarDockEdge) {
            return profile.normalizedDockEdge(legacyEdge, handedness: handedness)
        }

        return profile.normalizedDockEdge(
            EditorToolbarDockEdge.defaultEdge(for: handedness),
            handedness: handedness
        )
    }

    mutating func setDockEdge(_ edge: EditorToolbarDockEdge, for profile: EditorDockProfile) {
        dockEdgesByProfile[profile.rawValue] = edge.rawValue
        toolbarDockEdge = edge.rawValue
    }

    mutating func noteSelectedTool(_ tool: AnnotationTool) {
        selectedTool = tool
        if tool.isAnnotationTool, tool != .hand {
            lastAnnotationTool = tool
        }
    }
}

final class EditorPreferencesStore {
    static let shared = EditorPreferencesStore()

    private let defaults: UserDefaults
    private let ubiquitousStore: NSUbiquitousKeyValueStore?
    private let key = "lectra_editor_preferences"

    init(
        defaults: UserDefaults = .standard,
        ubiquitousStore: NSUbiquitousKeyValueStore? = .default
    ) {
        self.defaults = defaults
        self.ubiquitousStore = ubiquitousStore
    }

    func load() -> EditorPreferences {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(EditorPreferences.self, from: data) {
            return decoded
        }

        if let data = ubiquitousStore?.data(forKey: key),
           let decoded = try? JSONDecoder().decode(EditorPreferences.self, from: data) {
            defaults.set(data, forKey: key)
            return decoded
        }

        return EditorPreferences()
    }

    func save(_ preferences: EditorPreferences) {
        guard let encoded = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(encoded, forKey: key)
        ubiquitousStore?.set(encoded, forKey: key)
        ubiquitousStore?.synchronize()
        NotificationCenter.default.post(name: .lectraEditorPreferencesDidChange, object: preferences)
    }
}

final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let ioQueue = DispatchQueue(label: "com.canvascope.lectra.thumbnail-cache", qos: .userInitiated)

    private init() {
        memoryCache.countLimit = 128
    }

    func loadThumbnail(documentId: UUID, pdfURL: URL, revision: Int, size: CGSize) async -> UIImage? {
        let key = cacheKey(documentId: documentId, revision: revision, size: size)
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        return await withCheckedContinuation { continuation in
            ioQueue.async {
                let diskURL = self.diskURL(documentId: documentId, revision: revision, size: size)
                if let data = try? Data(contentsOf: diskURL),
                   let image = UIImage(data: data) {
                    self.memoryCache.setObject(image, forKey: key as NSString)
                    continuation.resume(returning: image)
                    return
                }

                guard let document = PDFDocument(url: pdfURL),
                      let page = document.page(at: 0) else {
                    continuation.resume(returning: nil)
                    return
                }

                let bounds = page.bounds(for: .mediaBox)
                let width = max(size.width, 140)
                let height = max(size.height, 140)
                let targetWidth = max(width, height * bounds.width / max(bounds.height, 1))
                let targetSize = CGSize(
                    width: targetWidth,
                    height: targetWidth * bounds.height / max(bounds.width, 1)
                )
                let thumbnail = page.thumbnail(of: targetSize, for: .mediaBox)
                self.memoryCache.setObject(thumbnail, forKey: key as NSString)
                try? FileManager.default.createDirectory(
                    at: diskURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if let data = thumbnail.jpegData(compressionQuality: 0.86) {
                    try? data.write(to: diskURL, options: [.atomic])
                }
                continuation.resume(returning: thumbnail)
            }
        }
    }

    func warmThumbnail(documentId: UUID, pdfURL: URL, revision: Int) {
        Task {
            _ = await loadThumbnail(
                documentId: documentId,
                pdfURL: pdfURL,
                revision: revision,
                size: CGSize(width: 220, height: 220)
            )
        }
    }

    func invalidate(documentId: UUID) {
        ioQueue.async {
            let root = self.rootDirectory().appendingPathComponent(documentId.uuidString, isDirectory: true)
            try? FileManager.default.removeItem(at: root)
        }
    }

    func removeAll() {
        memoryCache.removeAllObjects()
        ioQueue.async {
            try? FileManager.default.removeItem(at: self.rootDirectory())
        }
    }

    private func cacheKey(documentId: UUID, revision: Int, size: CGSize) -> String {
        "\(documentId.uuidString)-\(revision)-\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    private func diskURL(documentId: UUID, revision: Int, size: CGSize) -> URL {
        rootDirectory()
            .appendingPathComponent(documentId.uuidString, isDirectory: true)
            .appendingPathComponent("\(cacheKey(documentId: documentId, revision: revision, size: size)).jpg")
    }

    private func rootDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lectra_thumbnails", isDirectory: true)
    }
}

final class DocumentSearchIndex {
    static let shared = DocumentSearchIndex()

    private struct SearchIndexPage: Codable {
        let pageIndex: Int
        let text: String
    }

    private struct SearchIndexEntry: Codable {
        let documentId: UUID
        let revision: Int
        let title: String
        let folderName: String?
        let source: String
        let courseLabel: String?
        let pages: [SearchIndexPage]
    }

    private let lock = NSLock()
    private let ioQueue = DispatchQueue(label: "com.canvascope.lectra.search-index", qos: .utility)
    private var entries: [UUID: SearchIndexEntry] = [:]
    private var indexingDocuments: Set<UUID> = []

    private init() {
        if let data = try? Data(contentsOf: indexURL()),
           let decoded = try? JSONDecoder().decode([UUID: SearchIndexEntry].self, from: data) {
            entries = decoded
        }
    }

    func refresh(documents: [LocalDocument], folderNameByDocumentID: [UUID: String]) {
        for document in documents {
            guard let pdfURL = document.localPDFURL else { continue }
            scheduleIndex(for: document, pdfURL: pdfURL, folderName: folderNameByDocumentID[document.id])
        }
    }

    func search(query: String, documents: [LocalDocument], folderNameByDocumentID: [UUID: String]) -> [DocumentSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        refresh(documents: documents, folderNameByDocumentID: folderNameByDocumentID)

        let normalizedQuery = trimmedQuery.lowercased()
        var results: [DocumentSearchResult] = []

        lock.lock()
        let entriesSnapshot = entries
        lock.unlock()

        for document in documents {
            let folderName = folderNameByDocumentID[document.id]
            let metadataText = [
                document.title,
                folderName,
                document.isRemoteBacked ? "Lectra" : "On Device",
                document.courseId.map { "Course \($0)" },
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

            if metadataText.contains(normalizedQuery) {
                results.append(
                    DocumentSearchResult(
                        documentId: document.id,
                        title: document.title,
                        subtitle: folderName ?? (document.isRemoteBacked ? "Lectra" : "On Device"),
                        snippet: nil,
                        pageIndex: nil,
                        kind: .metadata
                    )
                )
            }

            guard let entry = entriesSnapshot[document.id] else { continue }
            for page in entry.pages {
                let lowercasedText = page.text.lowercased()
                guard lowercasedText.contains(normalizedQuery) else { continue }
                results.append(
                    DocumentSearchResult(
                        documentId: document.id,
                        title: document.title,
                        subtitle: "Page \(page.pageIndex + 1)",
                        snippet: snippet(for: page.text, query: trimmedQuery),
                        pageIndex: page.pageIndex,
                        kind: .pageText
                    )
                )
            }
        }

        return Array(NSOrderedSet(array: results)) as? [DocumentSearchResult] ?? results
    }

    func removeAll() {
        lock.lock()
        entries = [:]
        indexingDocuments = []
        lock.unlock()

        ioQueue.async {
            try? FileManager.default.removeItem(at: self.indexURL())
        }
    }

    private func scheduleIndex(for document: LocalDocument, pdfURL: URL, folderName: String?) {
        lock.lock()
        if indexingDocuments.contains(document.id) {
            lock.unlock()
            return
        }
        if let existing = entries[document.id],
           existing.revision == document.searchIndexRevision {
            lock.unlock()
            return
        }
        indexingDocuments.insert(document.id)
        lock.unlock()

        ioQueue.async {
            defer {
                self.lock.lock()
                self.indexingDocuments.remove(document.id)
                self.lock.unlock()
            }

            guard let indexed = self.buildEntry(
                document: document,
                pdfURL: pdfURL,
                folderName: folderName
            ) else {
                return
            }

            self.lock.lock()
            self.entries[document.id] = indexed
            let snapshot = self.entries
            self.lock.unlock()

            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: self.indexURL(), options: [.atomic])
            }
        }
    }

    private func buildEntry(document: LocalDocument, pdfURL: URL, folderName: String?) -> SearchIndexEntry? {
        guard let pdfDocument = PDFDocument(url: pdfURL) else { return nil }

        var pages: [SearchIndexPage] = []
        pages.reserveCapacity(pdfDocument.pageCount)

        for index in 0..<pdfDocument.pageCount {
            let pageText = pdfDocument.page(at: index)?.string?
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            pages.append(SearchIndexPage(pageIndex: index, text: pageText))
        }

        return SearchIndexEntry(
            documentId: document.id,
            revision: document.searchIndexRevision,
            title: document.title,
            folderName: folderName,
            source: document.isRemoteBacked ? "Lectra" : "On Device",
            courseLabel: document.courseId.map { "Course \($0)" },
            pages: pages
        )
    }

    private func snippet(for text: String, query: String) -> String {
        let normalizedText = text as NSString
        let range = normalizedText.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        )
        guard range.location != NSNotFound else {
            return String(text.prefix(120))
        }

        let start = max(range.location - 48, 0)
        let end = min(range.location + range.length + 48, normalizedText.length)
        let snippetRange = NSRange(location: start, length: max(end - start, 0))
        return normalizedText.substring(with: snippetRange)
    }

    private func indexURL() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lectra-search-index.json")
    }
}

@MainActor
final class DocumentSyncCoordinator {
    static let shared = DocumentSyncCoordinator()

    private let repository = DocumentRepository()
    private var isProcessing = false
    private var needsProcessingPass = false
    private var pendingJobs: [UUID: PendingSyncJob] = [:]

    init() {
        pendingJobs = Dictionary(uniqueKeysWithValues: repository.loadPendingSyncJobs().map { ($0.documentId, $0) })
    }

    func applyPersistedMetadata(to document: LocalDocument) {
        let metadata = repository.loadLocalMetadata(documentId: document.id)
        document.apply(metadata: metadata)
    }

    func registerLocalSave(
        result: DocumentSaveResult,
        documentId: UUID,
        title: String,
        rowId: UUID?,
        itemData: DocumentData?,
        userId: UUID?
    ) async {
        var metadata = repository.loadLocalMetadata(documentId: documentId)
        metadata.markLocalCheckpoint(
            editedAt: result.localEditAt,
            lastOpenedPage: result.lastOpenedPage,
            dirtyPageIndexes: result.dirtyPageIndexes
        )
        metadata.thumbnailRevision += 1
        metadata.searchIndexRevision += 1
        if UserDefaults.standard.bool(forKey: "lectra_cloud_sync_enabled") {
            metadata.iCloudMirrorState = .pending
            metadata.iCloudMirrorErrorMessage = nil
        }

        if let annotatedFilePath = result.annotatedFilePath,
           let rowId,
           let itemData,
           let userId {
            let job = PendingSyncJob(
                id: UUID(),
                documentId: documentId,
                rowId: rowId,
                userId: userId,
                itemData: itemData,
                annotatedFilePath: annotatedFilePath,
                queuedAt: result.localEditAt,
                retryCount: 0,
                nextRetryAt: nil,
                lastErrorMessage: nil
            )
            pendingJobs[documentId] = job
            repository.savePendingSyncJobs(Array(pendingJobs.values))
            metadata.markUploadQueued()
            repository.saveLocalMetadata(metadata, documentId: documentId)
            publish(documentId: documentId, metadata: metadata)
            scheduleICloudMirror(documentId: documentId, title: title, metadata: metadata)
            scheduleProcessing()
            return
        }

        metadata.syncState = .synced
        metadata.syncErrorMessage = nil
        repository.saveLocalMetadata(metadata, documentId: documentId)
        publish(documentId: documentId, metadata: metadata)
        scheduleICloudMirror(documentId: documentId, title: title, metadata: metadata)
    }

    func retry(documentId: UUID) async {
        guard var job = pendingJobs[documentId] else { return }
        job.nextRetryAt = nil
        job.lastErrorMessage = nil
        pendingJobs[documentId] = job
        repository.savePendingSyncJobs(Array(pendingJobs.values))

        var metadata = repository.loadLocalMetadata(documentId: documentId)
        metadata.markUploadQueued()
        repository.saveLocalMetadata(metadata, documentId: documentId)
        publish(documentId: documentId, metadata: metadata)
        scheduleProcessing()
    }

    func resumePendingJobs() async {
        pendingJobs = Dictionary(uniqueKeysWithValues: repository.loadPendingSyncJobs().map { ($0.documentId, $0) })
        await processPendingJobs()
    }

    func clearPendingJobsForAccountBoundary() {
        pendingJobs = [:]
        needsProcessingPass = false
        repository.savePendingSyncJobs([])
    }

    private func processPendingJobs() async {
        guard !isProcessing else {
            needsProcessingPass = true
            return
        }
        isProcessing = true
        defer {
            isProcessing = false
        }

        repeat {
            needsProcessingPass = false

            let orderedJobs = pendingJobs.values.sorted { lhs, rhs in
                lhs.queuedAt < rhs.queuedAt
            }

            for job in orderedJobs {
                if let nextRetryAt = job.nextRetryAt, nextRetryAt > Date() {
                    continue
                }
                await process(job: job)
            }
        } while needsProcessingPass
    }

    private func scheduleProcessing() {
        Task { @MainActor in
            await processPendingJobs()
        }
    }

    private func process(job: PendingSyncJob) async {
        var metadata = repository.loadLocalMetadata(documentId: job.documentId)
        metadata.markUploadAttempt(at: Date())
        repository.saveLocalMetadata(metadata, documentId: job.documentId)
        publish(documentId: job.documentId, metadata: metadata)

        let annotatedURL = URL(fileURLWithPath: job.annotatedFilePath)
        guard let data = try? Data(contentsOf: annotatedURL) else {
            LectraDebugLog("[DocumentSyncCoordinator] Sync process failed: annotated file not found at \(job.annotatedFilePath)")
            metadata.markUploadFailed(
                message: "Saved locally, but the upload file is missing.",
                nextRetryAt: nil
            )
            repository.saveLocalMetadata(metadata, documentId: job.documentId)
            publish(documentId: job.documentId, metadata: metadata)
            pendingJobs.removeValue(forKey: job.documentId)
            repository.savePendingSyncJobs(Array(pendingJobs.values))
            return
        }

        do {
            let uploadedPath = try await repository.uploadAnnotatedPDF(
                data: data,
                userId: job.userId,
                documentId: job.documentId
            )
            try await repository.markAsAnnotated(
                rowId: job.rowId,
                annotatedPath: uploadedPath,
                currentItemData: job.itemData
            )

            metadata.markUploadSucceeded(at: Date())
            repository.saveLocalMetadata(metadata, documentId: job.documentId)
            publish(documentId: job.documentId, metadata: metadata)
            pendingJobs.removeValue(forKey: job.documentId)
            repository.savePendingSyncJobs(Array(pendingJobs.values))
        } catch {
            LectraDebugLog("[DocumentSyncCoordinator] Sync process failed for document \(job.documentId) with error: \(error)")
            var failedJob = job
            failedJob.retryCount += 1
            let backoffSeconds = min(pow(2, Double(failedJob.retryCount)) * 15.0, 3600)
            failedJob.nextRetryAt = Date().addingTimeInterval(backoffSeconds)
            failedJob.lastErrorMessage = error.localizedDescription
            pendingJobs[job.documentId] = failedJob
            repository.savePendingSyncJobs(Array(pendingJobs.values))

            metadata.markUploadFailed(
                message: error.localizedDescription,
                nextRetryAt: failedJob.nextRetryAt
            )
            repository.saveLocalMetadata(metadata, documentId: job.documentId)
            publish(documentId: job.documentId, metadata: metadata)
        }
    }

    private func publish(documentId: UUID, metadata: DocumentLocalMetadata) {
        NotificationCenter.default.post(
            name: .lectraDocumentSyncStateDidChange,
            object: DocumentSyncStatusPayload(documentId: documentId, metadata: metadata)
        )
    }

    private func scheduleICloudMirror(documentId: UUID, title: String, metadata: DocumentLocalMetadata) {
        guard UserDefaults.standard.bool(forKey: "lectra_cloud_sync_enabled") else { return }

        let originalURL = repository.localPDFURL(for: documentId)
        let annotatedURL = repository.localAnnotatedPDFURL(for: documentId)
        let resolvedOriginalURL = FileManager.default.fileExists(atPath: originalURL.path) ? originalURL : nil
        let resolvedAnnotatedURL = FileManager.default.fileExists(atPath: annotatedURL.path) ? annotatedURL : nil

        guard resolvedOriginalURL != nil || resolvedAnnotatedURL != nil else { return }

        Task(priority: .utility) {
            do {
                try await ICloudDocumentStore.shared.mirrorDocument(
                    documentId: documentId,
                    title: title,
                    originalPDFURL: resolvedOriginalURL,
                    annotatedPDFURL: resolvedAnnotatedURL,
                    metadata: metadata
                )
                var updatedMetadata = repository.loadLocalMetadata(documentId: documentId)
                updatedMetadata.iCloudMirrorState = .mirrored
                updatedMetadata.lastICloudMirrorAt = Date()
                updatedMetadata.iCloudMirrorErrorMessage = nil
                repository.saveLocalMetadata(updatedMetadata, documentId: documentId)
                await MainActor.run {
                    self.publish(documentId: documentId, metadata: updatedMetadata)
                }
            } catch {
                var updatedMetadata = repository.loadLocalMetadata(documentId: documentId)
                updatedMetadata.iCloudMirrorState = .failed
                updatedMetadata.iCloudMirrorErrorMessage = error.localizedDescription
                repository.saveLocalMetadata(updatedMetadata, documentId: documentId)
                await MainActor.run {
                    self.publish(documentId: documentId, metadata: updatedMetadata)
                }
            }
        }
    }
}
