import Foundation
import UIKit
import PDFKit

enum DocumentSyncState: String, Codable, CaseIterable {
    case idle
    case savingLocal
    case flattening
    case queuedUpload
    case uploading
    case synced
    case failed
}

struct DocumentLocalMetadata: Codable, Equatable {
    var syncState: DocumentSyncState = .idle
    var syncErrorMessage: String?
    var dirtyPageIndexes: [Int] = []
    var lastLocalEditAt: Date?
    var lastRemoteSyncAt: Date?
    var lastOpenedPage: Int?
    var thumbnailRevision: Int = 0
    var searchIndexRevision: Int = 0
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
    let items: [RecoverySnapshotManifestItem]
}

extension Notification.Name {
    static let lectraDocumentSyncStateDidChange = Notification.Name("lectraDocumentSyncStateDidChange")
    static let lectraEditorPreferencesDidChange = Notification.Name("lectraEditorPreferencesDidChange")
    static let lectraICloudSyncDidChange = Notification.Name("lectraICloudSyncDidChange")
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
                    "lastOpenedPage": metadata.lastOpenedPage,
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
    var toolbarDockEdge: String = "bottom"
    var handedness: EditorHandedness = .right
    var squeezeAction: PencilSqueezeAction = .togglePenEraser
    var hasSeenLassoHint = false
    var hasSeenSqueezeHint = false
    var hasSeenDoubleTapHint = false
}

final class EditorPreferencesStore {
    static let shared = EditorPreferencesStore()

    private let defaults = UserDefaults.standard
    private let ubiquitousStore = NSUbiquitousKeyValueStore.default
    private let key = "lectra_editor_preferences"

    private init() {}

    func load() -> EditorPreferences {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(EditorPreferences.self, from: data) {
            return decoded
        }

        if let data = ubiquitousStore.data(forKey: key),
           let decoded = try? JSONDecoder().decode(EditorPreferences.self, from: data) {
            defaults.set(data, forKey: key)
            return decoded
        }

        return EditorPreferences()
    }

    func save(_ preferences: EditorPreferences) {
        guard let encoded = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(encoded, forKey: key)
        ubiquitousStore.set(encoded, forKey: key)
        ubiquitousStore.synchronize()
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
                document.isRemoteBacked ? "Canvascope" : "On Device",
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
                        subtitle: folderName ?? (document.isRemoteBacked ? "Canvascope" : "On Device"),
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
            source: document.isRemoteBacked ? "Canvascope" : "On Device",
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
    private var scheduledRetryTask: Task<Void, Never>?

    deinit {
        scheduledRetryTask?.cancel()
    }

    init() {
        pendingJobs = Dictionary(uniqueKeysWithValues: repository.loadPendingSyncJobs().map { ($0.documentId, $0) })
        scheduleRetryIfNeeded()
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
        metadata.lastLocalEditAt = result.localEditAt
        metadata.lastOpenedPage = result.lastOpenedPage
        metadata.dirtyPageIndexes = result.dirtyPageIndexes
        metadata.thumbnailRevision += 1
        metadata.searchIndexRevision += 1
        scheduleICloudMirror(documentId: documentId, title: title, metadata: metadata)

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
            metadata.syncState = .queuedUpload
            metadata.syncErrorMessage = nil
            repository.saveLocalMetadata(metadata, documentId: documentId)
            publish(documentId: documentId, metadata: metadata)
            scheduleProcessing()
            return
        }

        metadata.syncState = .synced
        metadata.syncErrorMessage = nil
        repository.saveLocalMetadata(metadata, documentId: documentId)
        publish(documentId: documentId, metadata: metadata)
    }

    func retry(documentId: UUID) async {
        guard var job = pendingJobs[documentId] else { return }
        job.nextRetryAt = nil
        job.lastErrorMessage = nil
        pendingJobs[documentId] = job
        repository.savePendingSyncJobs(Array(pendingJobs.values))
        var metadata = repository.loadLocalMetadata(documentId: documentId)
        metadata.syncState = .queuedUpload
        metadata.syncErrorMessage = nil
        repository.saveLocalMetadata(metadata, documentId: documentId)
        publish(documentId: documentId, metadata: metadata)
        scheduleProcessing()
    }

    func resumePendingJobs() async {
        pendingJobs = Dictionary(uniqueKeysWithValues: repository.loadPendingSyncJobs().map { ($0.documentId, $0) })
        scheduleRetryIfNeeded()
        await processPendingJobs()
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

        scheduleRetryIfNeeded()
    }

    private func scheduleProcessing() {
        Task { @MainActor in
            await processPendingJobs()
        }
    }

    private func process(job: PendingSyncJob) async {
        var metadata = repository.loadLocalMetadata(documentId: job.documentId)
        metadata.syncState = .uploading
        metadata.syncErrorMessage = nil
        repository.saveLocalMetadata(metadata, documentId: job.documentId)
        publish(documentId: job.documentId, metadata: metadata)

        let annotatedURL = URL(fileURLWithPath: job.annotatedFilePath)
        guard let data = try? Data(contentsOf: annotatedURL) else {
            metadata.syncState = .failed
            metadata.syncErrorMessage = "Saved locally, but the upload file is missing."
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

            metadata.syncState = .synced
            metadata.syncErrorMessage = nil
            metadata.lastRemoteSyncAt = Date()
            metadata.dirtyPageIndexes = []
            repository.saveLocalMetadata(metadata, documentId: job.documentId)
            publish(documentId: job.documentId, metadata: metadata)
            pendingJobs.removeValue(forKey: job.documentId)
            repository.savePendingSyncJobs(Array(pendingJobs.values))
        } catch {
            var failedJob = job
            failedJob.retryCount += 1
            let backoffSeconds = min(pow(2, Double(failedJob.retryCount)) * 15.0, 3600)
            failedJob.nextRetryAt = Date().addingTimeInterval(backoffSeconds)
            failedJob.lastErrorMessage = error.localizedDescription
            pendingJobs[job.documentId] = failedJob
            repository.savePendingSyncJobs(Array(pendingJobs.values))

            metadata.syncState = .queuedUpload
            metadata.syncErrorMessage = "Saved locally. Upload retry scheduled."
            repository.saveLocalMetadata(metadata, documentId: job.documentId)
            publish(documentId: job.documentId, metadata: metadata)
        }
    }

    private func scheduleRetryIfNeeded() {
        scheduledRetryTask?.cancel()

        guard let nextRetryAt = pendingJobs.values.compactMap(\.nextRetryAt).min() else {
            scheduledRetryTask = nil
            return
        }

        let delay = max(nextRetryAt.timeIntervalSinceNow, 0)
        scheduledRetryTask = Task { @MainActor in
            if delay > 0 {
                let duration = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: duration)
            }
            guard !Task.isCancelled else { return }
            await processPendingJobs()
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
            try? await ICloudDocumentStore.shared.mirrorDocument(
                documentId: documentId,
                title: title,
                originalPDFURL: resolvedOriginalURL,
                annotatedPDFURL: resolvedAnnotatedURL,
                metadata: metadata
            )
        }
    }
}
