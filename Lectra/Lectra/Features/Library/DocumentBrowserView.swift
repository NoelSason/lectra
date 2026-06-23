//
//  DocumentBrowserView.swift
//  Lectra
//
//  Lectra workspace shell for browsing folders and PDF documents.
//  PDF editing remains in PDFAnnotationView.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit
import PDFKit
import CryptoKit

// UUID needs Identifiable for fullScreenCover(item:)
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

struct SavedLocalDocument: Codable {
    let id: UUID
    let title: String
    let localPath: String
    let sourceURLString: String?
    let ownerUserId: UUID?
    var createdAt: Date?
    var updatedAt: Date?
    var isFavorite: Bool?

    nonisolated func belongs(to userId: UUID?) -> Bool {
        guard let ownerUserId, let userId else { return false }
        return ownerUserId == userId
    }
}

struct SavedLocalFolder: Codable {
    let id: UUID
    var name: String
    var createdAt: Date
    var colorHex: Int?
    var iconSystemName: String?
    var systemTag: String?
    var parentFolderId: UUID?
}

struct LocalFolder: Identifiable {
    let id: UUID
    var name: String
    var createdAt: Date
    var colorHex: Int?
    var iconSystemName: String?
    var systemTag: String?
    var parentFolderId: UUID?
}

struct SharePayload: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct EditorRoute: Identifiable, Equatable {
    let id = UUID()
    let documentId: UUID
    let initialPage: Int?
}

private enum LibrarySection: String, CaseIterable, Identifiable {
    case documents
    case favorites
    case shared

    var id: String { rawValue }

    var title: String {
        switch self {
        case .documents: return "Documents"
        case .favorites: return "Favorites"
        case .shared: return "Shared"
        }
    }

    var icon: String {
        switch self {
        case .documents: return "folder"
        case .favorites: return "bookmark"
        case .shared: return "person.2"
        }
    }
}

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case documents
    case folders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .documents: return "Documents"
        case .folders: return "Folders"
        }
    }
}

private enum BrowserViewMode: String {
    case grid
    case list
}

private enum RecoveryRestoreMode {
    case copy
    case replace
}

private enum LibraryGridEntry: Identifiable {
    case folder(LocalFolder)
    case document(LocalDocument)

    var id: String {
        switch self {
        case .folder(let folder):
            return "folder-\(folder.id.uuidString)"
        case .document(let document):
            return "document-\(document.id.uuidString)"
        }
    }
}

private enum LibrarySortMode: String, CaseIterable {
    case dateCreated
    case lastModified
    case name
    case type

    var title: String {
        switch self {
        case .dateCreated: return "Date Created"
        case .lastModified: return "Last Modified"
        case .name: return "Name"
        case .type: return "Type"
        }
    }
}

struct DocumentBrowserView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var documents: [LocalDocument] = []
    @State private var folders: [LocalFolder] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var activeSection: LibrarySection = .documents
    @State private var currentFolderId: UUID?
    @State private var documentFilter: LibraryFilter = .all
    @State private var viewMode: BrowserViewMode = .grid
    @State private var sortMode: LibrarySortMode = .lastModified
    @State private var isSidebarCollapsed = false

    @State private var showFilePicker = false
    @State private var filePickerContentTypes: [UTType] = [.pdf]
    @State private var showCreateMenu = false
    @State private var showViewMenu = false
    @State private var showCloudStatus = false
    @State private var showAccountSettingsModal = false
    @State private var accountSettingsInitialTab: AccountSettingsView.SettingsTab = .account
    @State private var showCreateFolderAlert = false
    @State private var newFolderName = ""

    @State private var showSearchOverlay = false
    @State private var searchText = ""
    @State private var globalSearchResults: [DocumentSearchResult] = []
    @State private var isSearchingDocuments = false
    @State private var searchRefreshTask: Task<Void, Never>? = nil
    @State private var activeFolderOptionsID: UUID?

    @State private var selectedDocumentForOptions: LocalDocument?
    @State private var moveDocumentId: UUID?
    @State private var editorRoute: EditorRoute?
    @State private var sharePayload: SharePayload?
    @State private var isSelectionMode = false
    @State private var selectedFolderIDs: Set<UUID> = []
    @State private var selectedDocumentIDs: Set<UUID> = []
    @State private var showBulkDeleteConfirm = false
    @State private var showBulkMoveSheet = false
    @State private var showNotebooks = false
    @State private var crossAskInput: CrossAskInput?

    @State private var featureNotice: String?
    @State private var backgroundSyncToast: String?
    @State private var backgroundSyncToastTask: Task<Void, Never>? = nil
    @State private var hasPendingBackgroundSyncToast = false
    @State private var documentFolderMap: [String: String] = [:]
    @State private var recentlyOpenedDocumentIds: [UUID] = []

    @State private var hasLoaded = false
    @State private var isCloudSyncEnabled = false
    @State private var isAutoBackupEnabled = true
    @State private var isSyncingCloud = false
    @State private var isRefreshingRemoteDocuments = false
    @State private var importedFolderPollingTask: Task<Void, Never>? = nil
    @State private var isICloudAvailable = false
    @State private var lastCloudSyncDate = Date()
    @State private var lastBackupDate = Date().addingTimeInterval(-20 * 60)
    @State private var recoverySnapshots: [RecoverySnapshot] = []
    @State private var recoverySnapshotsLoadGeneration = 0

    private let launchConfiguration: LectraLibraryLaunchConfiguration?
    private let repository = DocumentRepository()

    private let localPDFsDefaultsKey = LectraLocalAccountData.localPDFsDefaultsKey
    private let localFoldersDefaultsKey = LectraLocalAccountData.localFoldersDefaultsKey
    private let documentFolderMapDefaultsKey = LectraLocalAccountData.documentFolderMapDefaultsKey
    private let titleOverridesDefaultsKey = LectraLocalAccountData.titleOverridesDefaultsKey
    private let recentDocumentsDefaultsKey = LectraLocalAccountData.recentDocumentsDefaultsKey
    private let cloudSyncEnabledDefaultsKey = LectraLocalAccountData.cloudSyncEnabledDefaultsKey
    private let autoBackupEnabledDefaultsKey = LectraLocalAccountData.autoBackupEnabledDefaultsKey
    private let lastCloudSyncDefaultsKey = LectraLocalAccountData.lastCloudSyncDefaultsKey
    private let lastBackupDefaultsKey = LectraLocalAccountData.lastBackupDefaultsKey
    private let importedFolderName = "Imported"
    private let importedRootSystemTag = "imported_root"

    init(launchConfiguration: LectraLibraryLaunchConfiguration? = nil) {
        self.launchConfiguration = launchConfiguration
    }
    private let importedCanvascopeFolderName = "Imported From Canvascope"
    private let importedCanvascopeSystemTag = "imported_canvascope"
    private let legacyCanvasImportSystemTag = "imported_canvas"
    private let legacySubmissionImportSystemTag = "imported_gradescope"
    // Safety-net poll behind the realtime wake + prefetch. Kept short so a
    // missed broadcast still surfaces new drops quickly while the folder is open.
    private let importedFolderPollingIntervalNanoseconds: UInt64 = 1_500_000_000

    private var sidebarWidth: CGFloat {
        isSidebarCollapsed ? 86 : 292
    }

    /// Compact layout = every iPhone (any orientation) plus iPad in a compact
    /// multitasking width. The permanent iPad-style sidebar is dropped here and the
    /// toolbar collapses into icons.
    ///
    /// We can't key off `horizontalSizeClass == .compact` alone: large "Max"/"Plus"
    /// iPhones report a *regular* width in landscape, which would otherwise resurrect
    /// the two-column sidebar and squish the UI. Gate on the device idiom so an iPhone
    /// is always single-column.
    private var isCompactLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .phone || horizontalSizeClass == .compact
    }

    /// Content spans the full pane (no centered max-width column) whenever the
    /// sidebar is gone — either collapsed on iPad or absent on iPhone.
    private var usesFullWidthContent: Bool {
        isSidebarCollapsed || isCompactLayout
    }

    private var visibleSidebarSections: [LibrarySection] {
        [.documents]
    }

    private var expandedSidebarContentMaxWidth: CGFloat {
        1220
    }

    private var currentFolder: LocalFolder? {
        guard let currentFolderId else { return nil }
        return folders.first(where: { $0.id == currentFolderId })
    }

    private var importedCanvascopeFolder: LocalFolder? {
        folders.first(where: { $0.systemTag == importedCanvascopeSystemTag })
    }

    private var importedRootFolder: LocalFolder? {
        folders.first(where: { $0.systemTag == importedRootSystemTag })
    }

    private var importedRootFolderId: UUID? {
        importedRootFolder?.id
    }

    private var importedCanvascopeFolderId: UUID? {
        importedCanvascopeFolder?.id
    }

    private var documentsInScope: [LocalDocument] {
        if let importedRootFolderId, currentFolderId == importedRootFolderId {
            return []
        }
        return documents.filter { folderId(for: $0) == currentFolderId }
    }

    private var filteredFolders: [LocalFolder] {
        let scopedFolders: [LocalFolder]
        if let importedRootFolderId, currentFolderId == importedRootFolderId {
            scopedFolders = folders.filter {
                $0.systemTag == importedCanvascopeSystemTag
                    || $0.parentFolderId == importedRootFolderId
            }
        } else if let currentFolderId {
            scopedFolders = folders.filter { $0.parentFolderId == currentFolderId }
        } else {
            scopedFolders = folders.filter {
                $0.parentFolderId == nil
                && $0.systemTag != importedCanvascopeSystemTag
            }
        }

        guard activeSection == .documents else { return [] }
        guard documentFilter != .documents else { return [] }

        switch sortMode {
        case .name, .type:
            return scopedFolders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .dateCreated, .lastModified:
            return scopedFolders.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private var filteredDocuments: [LocalDocument] {
        guard activeSection == .documents else { return [] }
        guard documentFilter != .folders else { return [] }

        let scoped = documentsInScope

        switch sortMode {
        case .dateCreated:
            return scoped.sorted { $0.createdAt > $1.createdAt }
        case .lastModified:
            return scoped.sorted { $0.updatedAt > $1.updatedAt }
        case .name:
            return scoped.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .type:
            return scoped.sorted {
                documentType(for: $0) == documentType(for: $1)
                    ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    : documentType(for: $0) < documentType(for: $1)
            }
        }
    }

    private var visibleGridEntries: [LibraryGridEntry] {
        filteredFolders.map(LibraryGridEntry.folder) + filteredDocuments.map(LibraryGridEntry.document)
    }

    private var libraryCardWidth: CGFloat {
        if isCompactLayout {
            // Smaller cards so two columns fit on an iPhone in portrait.
            return currentFolderId == nil ? 168 : 158
        }
        return currentFolderId == nil ? 220 : 202
    }

    private var libraryGridMetrics: LibraryGridMetrics {
        currentFolderId == nil
            ? .root(cardWidth: libraryCardWidth)
            : .nested(cardWidth: libraryCardWidth)
    }

    private var gridColumns: [GridItem] {
        let spacing: CGFloat = isCompactLayout ? 16 : 26
        return [GridItem(.adaptive(minimum: libraryCardWidth, maximum: libraryCardWidth), spacing: spacing, alignment: .top)]
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recentlyOpenedDocuments: [LocalDocument] {
        recentlyOpenedDocumentIds.compactMap { id in
            documents.first(where: { $0.id == id })
        }
    }

    private var libraryHeaderTitle: String {
        currentFolder?.name ?? "Lectra"
    }

    private var activeSyncCount: Int {
        documents.filter {
            switch $0.syncState {
            case .idle, .synced:
                return false
            case .savingLocal, .flattening, .queuedUpload, .uploading, .failed:
                return true
            }
        }.count
    }

    private var canvascopeDocumentCount: Int {
        documents.filter { $0.status != .local || isDocumentInProtectedImportedFolder($0) }.count
    }

    private var activeSelectedFolderIDs: Set<UUID> {
        let valid = Set(folders.map(\.id))
        return selectedFolderIDs.intersection(valid)
    }

    private var selectedDocumentsOnly: [LocalDocument] {
        selectedDocumentIDs.compactMap { document(for: $0) }
    }

    private var selectedDocumentsInSelectedFolders: [LocalDocument] {
        let folderTreeIDs = selectedFolderTreeIDs
        guard !folderTreeIDs.isEmpty else { return [] }
        return documents.filter { doc in
            guard let folderID = folderId(for: doc) else { return false }
            return folderTreeIDs.contains(folderID)
        }
    }

    private var selectedFolderTreeIDs: Set<UUID> {
        activeSelectedFolderIDs.reduce(into: Set<UUID>()) { result, folderId in
            result.formUnion(descendantFolderIDs(including: folderId))
        }
    }

    private var resolvedSelectedDocuments: [LocalDocument] {
        var seen: Set<UUID> = []
        var merged: [LocalDocument] = []
        for doc in selectedDocumentsOnly + selectedDocumentsInSelectedFolders {
            if seen.insert(doc.id).inserted {
                merged.append(doc)
            }
        }
        return merged
    }

    private var selectedItemCount: Int {
        activeSelectedFolderIDs.count + selectedDocumentsOnly.count
    }

    private var canMoveSelection: Bool {
        activeSelectedFolderIDs.isEmpty
            && !selectedDocumentsOnly.isEmpty
            && selectedDocumentsOnly.allSatisfy { $0.status == .local }
    }

    private var exportableSelectionURLs: [URL] {
        var seenPaths: Set<String> = []
        var urls: [URL] = []
        for doc in resolvedSelectedDocuments {
            guard let localURL = doc.localPDFURL else { continue }
            if seenPaths.insert(localURL.path).inserted {
                urls.append(localURL)
            }
        }
        return urls
    }

    private var canExportSelection: Bool {
        !exportableSelectionURLs.isEmpty
    }

    /// Documents in the current selection that have readable local text and can
    /// be reasoned over together. Need at least two for a cross-document ask.
    private var crossAskCandidates: [LocalDocument] {
        resolvedSelectedDocuments.filter { $0.localPDFURL != nil }
    }

    private var canAskAcrossSelection: Bool {
        crossAskCandidates.count >= 2
    }

    private func presentCrossDocumentAsk() {
        let documents = crossAskCandidates.compactMap { doc -> CrossAskInput.Document? in
            guard let url = doc.localPDFURL else { return nil }
            return CrossAskInput.Document(id: doc.id, title: doc.title, url: url)
        }
        guard documents.count >= 2 else { return }
        crossAskInput = CrossAskInput(documents: documents)
    }

    private var canDeleteSelection: Bool {
        selectedItemCount > 0
    }

    /// IDs of every folder/document currently visible in this scope, used to
    /// drive the "Select All" toggle in the selection action bar.
    private var visibleSelectableFolderIDs: Set<UUID> {
        Set(filteredFolders.map(\.id))
    }

    private var visibleSelectableDocumentIDs: Set<UUID> {
        Set(filteredDocuments.map(\.id))
    }

    private var hasSelectableItems: Bool {
        !visibleSelectableFolderIDs.isEmpty || !visibleSelectableDocumentIDs.isEmpty
    }

    private var isAllSelected: Bool {
        hasSelectableItems
            && visibleSelectableFolderIDs.isSubset(of: selectedFolderIDs)
            && visibleSelectableDocumentIDs.isSubset(of: selectedDocumentIDs)
    }

    private var mainContentLayout: AnyView {
        if isCompactLayout {
            // iPhone: no permanent sidebar — the pane owns the full width.
            return AnyView(
                mainPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(LectraGradient.appBackdrop.ignoresSafeArea())
            )
        }

        return AnyView(
            HStack(spacing: 0) {
                sidebar
                    .frame(width: sidebarWidth)

                mainPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(LectraColor.background)
            }
            .background(LectraGradient.appBackdrop.ignoresSafeArea())
        )
    }
    
    private var overlays: AnyView {
        AnyView(
            Group {
                if let message = backgroundSyncToast {
                    VStack {
                        Spacer()
                        Text(message)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(LectraColor.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(LectraColor.accent.opacity(0.92))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
                            )
                            .padding(.bottom, 26)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
                }
            }
        )
    }

    private var bulkDeletePromptTitle: String {
        let folderCount = activeSelectedFolderIDs.count
        let documentCount = resolvedSelectedDocuments.count
        if folderCount > 0 && documentCount > 0 {
            return "Delete \(folderCount) folder\(folderCount == 1 ? "" : "s") and \(documentCount) document\(documentCount == 1 ? "" : "s")?"
        }
        if folderCount > 0 {
            return "Delete \(folderCount) folder\(folderCount == 1 ? "" : "s")?"
        }
        return "Delete \(documentCount) document\(documentCount == 1 ? "" : "s")?"
    }

    var body: some View {
        let syncPublisher = NotificationCenter.default.publisher(for: .lectraDocumentSyncStateDidChange)
        let iCloudPublisher = NotificationCenter.default.publisher(for: .lectraICloudSyncDidChange)
        let remoteDocumentsPublisher = NotificationCenter.default.publisher(for: .lectraRemoteDocumentsDidChange)
        let openDocumentPublisher = NotificationCenter.default.publisher(for: .lectraOpenDocumentRequest)

        return presentedContent
            .onReceive(syncPublisher, perform: handleDocumentSyncNotification)
            .onReceive(iCloudPublisher, perform: handleICloudSyncNotification)
            .onReceive(remoteDocumentsPublisher, perform: handleRemoteDocumentsNotification)
            .onReceive(openDocumentPublisher, perform: handleOpenDocumentRequest)
            .onChange(of: backgroundSyncToast) { _, newValue in
                guard let newValue else { return }
                postAccessibilityAnnouncement(newValue)
            }
            .onChange(of: featureNotice) { _, newValue in
                guard let newValue else { return }
                postAccessibilityAnnouncement(newValue)
            }
            .onChange(of: editorRoute) { _, newValue in
                handleEditorRouteChange(newValue)
            }
            .onChange(of: currentFolderId) { _, _ in
                handleCurrentFolderChange()
            }
            .onChange(of: activeSection) { _, newSection in
                handleActiveSectionChange(newSection)
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
            .onChange(of: authManager.userId) { oldValue, newValue in
                handleAuthenticatedUserChange(oldUserId: oldValue, newUserId: newValue)
            }
            .onChange(of: searchText) { _, _ in
                runGlobalSearch()
            }
            .task {
                await performInitialLoadIfNeeded()
            }
            .onDisappear {
                handleDisappear()
            }
            .preferredColorScheme(ColorScheme.dark)
    }

    private func handleDocumentSyncNotification(_ notification: Notification) {
        guard let payload = notification.object as? DocumentSyncStatusPayload else { return }
        applySyncPayload(payload)
        guard activeSection == LibrarySection.documents else { return }

        if payload.metadata.syncState == .synced {
            if editorRoute == nil {
                showBackgroundSyncToast("Synced to cloud ✓")
            } else {
                hasPendingBackgroundSyncToast = true
            }
        } else if editorRoute != nil {
            hasPendingBackgroundSyncToast = true
        }
    }

    private func handleICloudSyncNotification(_ notification: Notification) {
        guard launchConfiguration == nil else { return }
        guard let payload = notification.object as? ICloudSyncStatusPayload,
              payload.errorMessage == nil else {
            return
        }

        lastCloudSyncDate = payload.syncedAt
        UserDefaults.standard.set(payload.syncedAt, forKey: lastCloudSyncDefaultsKey)
    }

    private func handleRemoteDocumentsNotification(_ notification: Notification) {
        guard launchConfiguration == nil else { return }
        Task {
            await refreshRemoteDocuments()
        }
    }

    private func handleEditorRouteChange(_ newValue: EditorRoute?) {
        if newValue == nil, hasPendingBackgroundSyncToast {
            hasPendingBackgroundSyncToast = false
            showBackgroundSyncToast("Synced to cloud ✓")
        }
    }

    private func handleCurrentFolderChange() {
        if isSelectionMode {
            exitSelectionMode()
        }
        updateImportedFolderPolling()
    }

    private func handleActiveSectionChange(_ newSection: LibrarySection) {
        if newSection != LibrarySection.documents && isSelectionMode {
            exitSelectionMode()
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        guard launchConfiguration == nil else { return }
        updateImportedFolderPolling()
        guard newPhase == .active else { return }

        isICloudAvailable = ICloudDocumentStore.shared.isAvailable()
        loadRecoverySnapshots()
        Task(priority: .utility) {
            await DocumentSyncCoordinator.shared.resumePendingJobs()
        }
    }

    private func handleAuthenticatedUserChange(oldUserId: UUID?, newUserId: UUID?) {
        guard launchConfiguration == nil else { return }
        guard oldUserId != newUserId else { return }

        clearAccountScopedLibraryState()
        hasLoaded = false

        guard newUserId != nil else { return }
        Task {
            await performInitialLoadIfNeeded()
        }
    }

    private func performInitialLoadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        if let launchConfiguration {
            applyLaunchConfiguration(launchConfiguration)
            return
        }

        loadRecentDocuments()
        loadCloudPreferences()
        loadRecoverySnapshots()
        await loadDocuments()
        Task(priority: .utility) {
            await DocumentSyncCoordinator.shared.resumePendingJobs()
        }
        if isCloudSyncEnabled {
            Task(priority: .utility) {
                await runCloudSync(triggeredByUser: false)
            }
        }
    }

    private func handleDisappear() {
        backgroundSyncToastTask?.cancel()
        searchRefreshTask?.cancel()
        stopImportedFolderPolling()
    }

    private func clearAccountScopedLibraryState() {
        backgroundSyncToastTask?.cancel()
        searchRefreshTask?.cancel()
        stopImportedFolderPolling()

        documents = []
        folders = []
        documentFolderMap = [:]
        recentlyOpenedDocumentIds = []
        globalSearchResults = []
        recoverySnapshots = []
        selectedFolderIDs = []
        selectedDocumentIDs = []
        currentFolderId = nil
        editorRoute = nil
        sharePayload = nil
        isSelectionMode = false
        isRefreshingRemoteDocuments = false
        isSyncingCloud = false
        isLoading = false
        errorMessage = nil
        DocumentSearchIndex.shared.removeAll()
    }

    private func applyLaunchConfiguration(_ launchConfiguration: LectraLibraryLaunchConfiguration) {
        documents = launchConfiguration.documents
        folders = launchConfiguration.folders
        documentFolderMap = launchConfiguration.documentFolderMap
        recentlyOpenedDocumentIds = launchConfiguration.recentDocumentIDs
        currentFolderId = launchConfiguration.currentFolderID
        isCloudSyncEnabled = launchConfiguration.isCloudSyncEnabled
        isAutoBackupEnabled = launchConfiguration.isAutoBackupEnabled
        lastCloudSyncDate = launchConfiguration.lastCloudSyncDate
        lastBackupDate = launchConfiguration.lastBackupDate
        isICloudAvailable = false
        isLoading = false
        errorMessage = nil
        ensureImportedFolderHierarchyExists()
        refreshLibraryDerivatives(reloadRecoverySnapshots: false)
        pruneFolderMappingForCurrentData()
    }

    private var presentedContent: some View {
        presentationAlerts(
            content: presentationSheets(
                content: ZStack {
                    mainContentLayout
                    overlays
                }
            )
        )
    }

    private func presentationSheets<Content: View>(content: Content) -> some View {
        content
            .sheet(isPresented: $showAccountSettingsModal) {
                AccountSettingsView(
                    initialTab: accountSettingsInitialTab,
                    userName: resolvedAccountDisplayName,
                    userEmail: authManager.userEmail,
                    avatarURL: authManager.avatarURL,
                    isCloudSyncEnabled: isCloudSyncEnabled,
                    isAutoBackupEnabled: isAutoBackupEnabled,
                    isICloudAvailable: isICloudAvailable,
                    isSyncInProgress: isSyncingCloud,
                    lastCloudSyncDate: lastCloudSyncDate,
                    lastBackupDate: lastBackupDate,
                    recoverySnapshots: recoverySnapshots,
                    onSetCloudSyncEnabled: { isEnabled in
                        setCloudSyncEnabled(isEnabled)
                    },
                    onSetAutoBackupEnabled: { isEnabled in
                        setAutoBackupEnabled(isEnabled)
                    },
                    onRunCloudSync: {
                        Task {
                            await runCloudSync(triggeredByUser: true)
                        }
                    },
                    onRunManualBackup: {
                        Task {
                            await runManualBackup()
                        }
                    },
                    onReloadRecoverySnapshots: {
                        loadRecoverySnapshots()
                    },
                    onRestoreSnapshotAsCopy: { snapshot in
                        Task {
                            await restoreSnapshot(snapshot, mode: .copy)
                        }
                    },
                    onRestoreSnapshotReplacing: { snapshot in
                        Task {
                            await restoreSnapshot(snapshot, mode: .replace)
                        }
                    },
                    onSignOut: {
                        Task {
                            await signOutFromLectra()
                        }
                    },
                    onDeleteAccount: {
                        Task {
                            await deleteAccountFromLectra()
                        }
                    }
                )
                .id(accountSettingsInitialTab)
            }
            .sheet(isPresented: $showFilePicker) {
                DocumentPickerView(contentTypes: filePickerContentTypes) { url in
                    guard canModifyContents(of: currentFolderId) else { return }
                    importPickedFile(from: url, folderId: currentFolderId)
                }
            }
            .sheet(item: $selectedDocumentForOptions) { doc in
                DocumentOptionsSheetView(
                    documentTitle: doc.title,
                    onDuplicate: { duplicateDocument(doc) },
                    onMove: { moveDocumentId = doc.id },
                    onExport: { exportDocument(doc) },
                    onDelete: { removeDocument(doc) }
                )
            }
            .sheet(item: $moveDocumentId) { docId in
                if let doc = document(for: docId) {
                    MoveDocumentSheetView(
                        documentTitle: doc.title,
                        folders: folders.filter { !isProtectedImportedFolder($0.id) },
                        currentFolderId: folderId(for: doc),
                        isLockedToImportedFolder: isDocumentLockedToImportedFolder(doc),
                        importedFolderName: lockedImportedFolderName(for: doc),
                        onMove: { targetFolderId in
                            moveDocument(documentId: doc.id, to: targetFolderId)
                        }
                    )
                }
            }
            .sheet(isPresented: $showBulkMoveSheet) {
                BulkMoveDocumentsSheetView(
                    selectedCount: selectedDocumentsOnly.count,
                    folders: folders.filter { !isProtectedImportedFolder($0.id) },
                    onMove: { targetFolderId in
                        performBulkMove(to: targetFolderId)
                    }
                )
            }
            .sheet(item: $sharePayload) { payload in
                ShareSheetView(items: payload.urls)
            }
            .sheet(item: $crossAskInput) { input in
                CrossDocumentAskSheet(input: input)
            }
            .sheet(isPresented: $showNotebooks) {
                NotebookLibraryView()
            }
            .fullScreenCover(item: $editorRoute) { route in
                if let doc = document(for: route.documentId) {
                    PDFAnnotationView(
                        document: doc,
                        repository: repository,
                        initialPage: route.initialPage,
                        onRename: { newTitle in
                            persistTitleRename(for: doc, newTitle: newTitle)
                        }
                    )
                }
            }
    }

    private func presentationAlerts<Content: View>(content: Content) -> some View {
        content
            .alert("Create Folder", isPresented: $showCreateFolderAlert) {
                TextField("Folder name", text: $newFolderName)
                Button("Cancel", role: .cancel) { newFolderName = "" }
                Button("Create") {
                    createFolder(named: newFolderName)
                    newFolderName = ""
                }
            } message: {
                Text("Add a new folder.")
            }
            .alert(
                featureNoticeTitle,
                isPresented: Binding(
                    get: { featureNotice != nil },
                    set: { isPresented in
                        if !isPresented { featureNotice = nil }
                    }
                )
            ) {
                Button("OK", role: .cancel) { featureNotice = nil }
            } message: {
                Text(featureNotice ?? "")
            }
            .confirmationDialog(
                bulkDeletePromptTitle,
                isPresented: $showBulkDeleteConfirm,
                titleVisibility: Visibility.visible
            ) {
                Button("Delete", role: .destructive) { performBulkDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
    }

    private var featureNoticeTitle: String {
        guard let featureNotice else { return "Notice" }

        if featureNotice.hasPrefix("Sign in to iCloud") || featureNotice.contains("iCloud Drive is unavailable") {
            return "iCloud Unavailable"
        }

        if featureNotice.hasPrefix("Enable Cloud Sync") {
            return "Cloud Sync Off"
        }

        if featureNotice.hasPrefix("Manual backup failed")
            || featureNotice.hasPrefix("Sync finished, but backup failed")
            || featureNotice.hasPrefix("Saved locally, but iCloud sync did not finish")
            || featureNotice.hasPrefix("Could not ")
            || featureNotice.hasPrefix("Download failed") {
            return "Something Went Wrong"
        }

        return "Notice"
    }

    private func showFeatureNotice(_ message: String?, force: Bool = false) {
        guard let message else { return }
        guard force || !Self.shouldSuppressBlockingNotice(for: message) else { return }
        featureNotice = message
    }

    static func shouldSuppressBlockingNotice(for message: String) -> Bool {
        message == "Saved locally. We'll retry upload automatically."
            || message.hasPrefix("Saved locally, but iCloud sync did not finish")
            || message.hasPrefix("Changes not saved locally")
            || message.hasPrefix("Changes weren't saved locally")
    }

    private var resolvedAccountDisplayName: String {
        if let userName = authManager.userName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !userName.isEmpty {
            return userName
        }
        if let userEmail = authManager.userEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !userEmail.isEmpty {
            return userEmail
        }
        return "Lectra Account"
    }

    private func openAccountSettings(at tab: AccountSettingsView.SettingsTab = .account) {
        accountSettingsInitialTab = tab
        showAccountSettingsModal = true
    }

    private func signOutFromLectra() async {
        LegacyThirdPartyIntegrationData.clearFromDevice()
        await authManager.signOut()
        showAccountSettingsModal = false
    }

    private func deleteAccountFromLectra() async {
        do {
            try await authManager.deleteAccount()
            LegacyThirdPartyIntegrationData.clearFromDevice()
            showAccountSettingsModal = false
        } catch {
            showFeatureNotice(
                "We couldn't delete your account. Please check your connection and try again, or contact support.",
                force: true
            )
        }
    }

    private func showBackgroundSyncToast(_ message: String) {
        backgroundSyncToastTask?.cancel()
        withAnimation(LectraMotion.quick) {
            backgroundSyncToast = message
        }

        backgroundSyncToastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_300_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(LectraMotion.quick) {
                backgroundSyncToast = nil
            }
        }
    }

    @MainActor
    private func showCloudSuccessToast(_ message: String) {
        featureNotice = nil
        showCloudStatus = false
        showBackgroundSyncToast(message)
    }

    private var sidebar: some View {
        VStack(alignment: isSidebarCollapsed ? .center : .leading, spacing: isSidebarCollapsed ? 14 : 12) {
            Group {
                if isSidebarCollapsed {
                    VStack(spacing: 8) {
                        brandMark
                        collapseSidebarButton
                    }
                } else {
                    HStack(spacing: 10) {
                        brandMark

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lectra")
                                .font(LectraTypography.title)
                                .foregroundStyle(LectraColor.textPrimary)
                                .lineLimit(1)

                            Text("Lectra workspace")
                                .font(LectraTypography.footnote)
                                .foregroundStyle(LectraColor.textTertiary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        collapseSidebarButton
                            .layoutPriority(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: isSidebarCollapsed ? .center : .leading)
            .padding(.top, 8)
            .padding(.bottom, isSidebarCollapsed ? 4 : 14)

            ForEach(visibleSidebarSections) { section in
                sidebarRow(for: section)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, isSidebarCollapsed ? 10 : 16)
        .padding(.vertical, 16)
        .background(
            Rectangle()
                .fill(LectraColor.sidebarBackground)
                .overlay {
                    LinearGradient(
                        colors: [
                            LectraColor.paper.opacity(0.05),
                            LectraColor.accent.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(LectraColor.sidebarDivider)
                        .frame(width: 1)
                }
                .ignoresSafeArea()
        )
    }

    private var brandMark: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
            .clipShape(RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
            .lectraShadow(LectraElevation.low())
            .accessibilityHidden(true)
    }

    private var collapseSidebarButton: some View {
        Button {
            withAnimation(LectraMotion.toolbarDock) {
                isSidebarCollapsed.toggle()
            }
        } label: {
            Image(systemName: isSidebarCollapsed ? "sidebar.right" : "sidebar.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(LectraColor.textSecondary)
                .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
                .background {
                    RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                        .fill(LectraColor.sidebarControl)
                        .overlay(
                            RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                                .stroke(LectraColor.sidebarDivider, lineWidth: 1)
                        )
                }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(isSidebarCollapsed ? "Expand sidebar" : "Collapse sidebar")
        .accessibilityIdentifier("library.sidebarToggle")
    }

    @ViewBuilder
    private func sidebarRow(for section: LibrarySection) -> some View {
        Button {
            withAnimation(LectraMotion.quick) {
                selectSection(section)
            }
        } label: {
            VStack(alignment: .leading, spacing: isSidebarCollapsed ? 0 : 2) {
                HStack(spacing: isSidebarCollapsed ? 0 : 12) {
                    Image(systemName: section.icon)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 28)

                    if !isSidebarCollapsed {
                        Text(section.title)
                            .font(.headline)
                            .lineLimit(1)
                    }

                    if !isSidebarCollapsed {
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: isSidebarCollapsed ? .center : .leading)

            }
            .foregroundColor(activeSection == section ? LectraColor.textPrimary : LectraColor.textSecondary)
            .padding(.horizontal, isSidebarCollapsed ? 0 : 12)
            .padding(.vertical, isSidebarCollapsed ? 12 : 12)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: isSidebarCollapsed ? .center : .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(activeSection == section ? LectraColor.sidebarSelection : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(activeSection == section ? LectraColor.accent.opacity(0.32) : Color.clear, lineWidth: 1)
                    }
            )
            .overlay(alignment: .leading) {
                if activeSection == section && !isSidebarCollapsed {
                    Capsule()
                        .fill(LectraColor.accent)
                        .frame(width: 3, height: 20)
                        .offset(x: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: isSidebarCollapsed ? .center : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(section.title)
        .accessibilityHint("Shows the \(section.title.lowercased()) workspace.")
        .accessibilityAddTraits(activeSection == section ? .isSelected : [])
        .accessibilityIdentifier("library.section.\(section.rawValue)")
    }

    private var mainPane: AnyView {
        switch activeSection {
        case .documents:
            return AnyView(documentsPane)
        case .favorites:
            return AnyView(favoritesPane)
        case .shared:
            return AnyView(sharedPane)
        }
    }

    private var documentsPane: AnyView {
        AnyView(
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    documentsTopBar
                        .padding(.horizontal, 18)
                        .padding(.top, 10)

                    if isLoading && documents.isEmpty && folders.isEmpty {
                        Spacer()
                        loadingView
                            .frame(maxWidth: .infinity)
                        Spacer()
                    } else if filteredFolders.isEmpty && filteredDocuments.isEmpty {
                        Spacer()
                        emptyDocumentsView
                            .frame(maxWidth: .infinity)
                        Spacer()
                    } else if viewMode == .grid {
                        documentsGridView
                    } else {
                        documentsListView
                    }
                }
                .frame(
                    maxWidth: usesFullWidthContent ? .infinity : expandedSidebarContentMaxWidth,
                    alignment: .leading
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: usesFullWidthContent ? .topLeading : .top
                )

                if showSearchOverlay {
                    searchOverlay
                        .transition(.opacity)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelectionMode {
                    selectionActionBar
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, 12)
                        .background(
                            LinearGradient(
                                colors: [
                                    LectraColor.background.opacity(0.02),
                                    LectraColor.background.opacity(0.86),
                                    LectraColor.background.opacity(0.98)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
        )
    }

    private var documentsTopBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                documentTitleCluster

                Spacer(minLength: 8)

                // Collapses to icons + an overflow menu whenever the labeled
                // controls can't fit (iPhone, and iPad in portrait/split).
                ViewThatFits(in: .horizontal) {
                    fullTrailingControls
                    compactTrailingControls
                }
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LectraColor.edgeStroke)
                .frame(height: 1)
        }
    }

    private var fullTrailingControls: some View {
        HStack(spacing: 10) {
            filterMenu
            selectButton
            newButton(compact: false)
            viewModeButton
            notebooksButton
            cloudButton
            searchButton
            avatarButton
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var compactTrailingControls: some View {
        HStack(spacing: 8) {
            newButton(compact: true)
            notebooksButton
            cloudButton
            compactOverflowMenu
            avatarButton
        }
    }

    private var notebooksButton: some View {
        Button {
            LectraHaptics.tap()
            showNotebooks = true
        } label: {
            Image(systemName: "book.closed")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(LectraColor.textPrimary)
                .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
                .background(controlSurface)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Notebooks")
        .accessibilityHint("Open and create Python notebooks.")
        .accessibilityIdentifier("library.notebooks")
    }

    private var searchButton: some View {
        Button {
            withAnimation(LectraMotion.quick) {
                showSearchOverlay = true
                searchText = ""
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(LectraColor.textPrimary)
                .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
                .background(controlSurface)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search library")
        .accessibilityHint("Searches documents and notes.")
        .accessibilityIdentifier("library.search")
    }

    /// Overflow: folds the secondary library controls (search, select, filter,
    /// view, sort) into a single menu so the bar never wraps on narrow widths.
    private var compactOverflowMenu: some View {
        Menu {
            Button {
                withAnimation(LectraMotion.quick) {
                    showSearchOverlay = true
                    searchText = ""
                }
            } label: {
                Label("Search", systemImage: "magnifyingglass")
            }

            Button {
                if isSelectionMode {
                    exitSelectionMode()
                } else {
                    enterSelectionMode()
                }
            } label: {
                Label(isSelectionMode ? "Cancel Selection" : "Select", systemImage: isSelectionMode ? "xmark.circle" : "checkmark.circle")
            }

            Divider()

            if currentFolderId == nil {
                Menu("Filter") {
                    ForEach(LibraryFilter.allCases) { filter in
                        Button {
                            documentFilter = filter
                        } label: {
                            if documentFilter == filter {
                                Label(filter.title, systemImage: "checkmark")
                            } else {
                                Text(filter.title)
                            }
                        }
                    }
                }
                .disabled(isSelectionMode)
            }

            Menu("View") {
                Button {
                    viewMode = .grid
                } label: {
                    if viewMode == .grid {
                        Label("Grid", systemImage: "checkmark")
                    } else {
                        Text("Grid")
                    }
                }
                Button {
                    viewMode = .list
                } label: {
                    if viewMode == .list {
                        Label("List", systemImage: "checkmark")
                    } else {
                        Text("List")
                    }
                }
            }

            Menu("Sort") {
                ForEach(LibrarySortMode.allCases, id: \.self) { mode in
                    Button {
                        sortMode = mode
                    } label: {
                        if sortMode == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(LectraColor.textPrimary)
                .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
                .background(controlSurface)
        }
        .accessibilityLabel("More library options")
        .accessibilityIdentifier("library.overflow")
    }

    private var documentTitleCluster: some View {
        HStack(spacing: 10) {
            if currentFolderId != nil {
                Button {
                    returnToVaultRoot()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        // On iPhone the bar is tight: drop to a chevron-only back
                        // button so the parent name can't wrap ("Documen/ts") or
                        // crowd the folder title. The title shows the current folder.
                        if !isCompactLayout {
                            Text(backNavigationLabel)
                                .font(LectraTypography.caption)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .foregroundColor(LectraColor.accentSoft)
                    .padding(.horizontal, isCompactLayout ? 9 : 10)
                    .frame(height: 34)
                    .background(controlSurface)
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Back to \(backNavigationLabel)")
            }

            Text(libraryHeaderTitle)
                .font(.system(size: currentFolderId == nil ? 28 : 24, weight: .bold, design: .rounded))
                .foregroundStyle(LectraColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
                .layoutPriority(1)
        }
        .frame(minHeight: 38, alignment: .leading)
    }

    private var workspaceStatusStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                workspaceMetricPill(symbol: "doc.text", value: "\(documents.count)", label: "Docs")
                workspaceMetricPill(symbol: "folder", value: "\(folders.count)", label: "Folders")
                workspaceMetricPill(symbol: "arrow.triangle.2.circlepath", value: "\(activeSyncCount)", label: "Sync")
                workspaceMetricPill(symbol: "arrow.up.forward.app", value: "\(canvascopeDocumentCount)", label: "Canvascope")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    workspaceMetricPill(symbol: "doc.text", value: "\(documents.count)", label: "Docs")
                    workspaceMetricPill(symbol: "folder", value: "\(folders.count)", label: "Folders")
                }
                HStack(spacing: 8) {
                    workspaceMetricPill(symbol: "arrow.triangle.2.circlepath", value: "\(activeSyncCount)", label: "Sync")
                    workspaceMetricPill(symbol: "arrow.up.forward.app", value: "\(canvascopeDocumentCount)", label: "Canvascope")
                }
            }
        }
    }

    private func workspaceMetricPill(symbol: String, value: String, label: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(LectraColor.accentSoft)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: LectraRadius.button, style: .continuous)
                        .fill(LectraColor.accent.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(LectraColor.textPrimary)

                Text(label)
                    .font(LectraTypography.footnote)
                    .foregroundColor(LectraColor.textTertiary)
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 13)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                .fill(LectraColor.paper.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                .stroke(LectraColor.edgeStroke.opacity(0.6), lineWidth: 1)
        )
    }

    private var favoritesPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            genericTopBar(title: "Favorites", filterTitle: "All Favorites", includeSearch: false)
                .padding(.horizontal, 18)
                .padding(.top, 10)

            let favDocs = documents.filter { $0.isFavorite }

            if favDocs.isEmpty {
                Spacer()
                GenericEmptyStateView(
                    symbol: "folder.badge.star",
                    title: "Find things quicker with Favorites",
                    subtitle: "Simply tap the star to add documents to favorites."
                )
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    if viewMode == .grid {
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 34) {
                            ForEach(favDocs) { doc in
                                documentGridCard(for: doc)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 18)
                        .padding(.bottom, 44)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(favDocs) { doc in
                                documentListRow(for: doc)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 18)
                        .padding(.bottom, 60)
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var sharedPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            genericTopBar(title: "Shared", filterTitle: "Owned by Anyone", includeSearch: false)
                .padding(.horizontal, 18)
                .padding(.top, 10)

            Spacer()
            GenericEmptyStateView(
                symbol: "puzzlepiece.extension",
                title: "Want to share a document?",
                subtitle: "Tap the share icon or open a shared link."
            )
            .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    private func genericTopBar(title: String, filterTitle: String, includeSearch: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundColor(LectraColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 0)

                utilityButtons(showSearch: includeSearch)
            }

            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 14, weight: .bold))
                    Text(filterTitle)
                        .font(LectraTypography.bodyEmphasis)
                }
                .foregroundColor(LectraColor.textPrimary)
                .padding(.horizontal, 12)
                .frame(minHeight: LectraSizing.minHitTarget)
                .background(controlSurface)

                Spacer(minLength: 0)

                viewModeButton
                cloudButton
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LectraColor.edgeStroke)
                .frame(height: 1)
        }
    }

    private var documentsGridView: some View {
        let metrics = libraryGridMetrics
        return ScrollView {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: metrics.documentGridSpacing) {
                ForEach(visibleGridEntries) { entry in
                    switch entry {
                    case .folder(let folder):
                        folderGridCard(for: folder)
                    case .document(let document):
                        documentGridCard(for: document)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 44)
        }
        .scrollIndicators(.hidden)
    }

    private var documentsListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(filteredFolders) { folder in
                    Button {
                        if isSelectionMode {
                            toggleFolderSelection(folder.id)
                        } else {
                            openFolder(folder)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            if isSelectionMode {
                                LibrarySelectionIndicatorView(isSelected: activeSelectedFolderIDs.contains(folder.id))
                            }

                            Image(systemName: "folder.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(LectraColor.accentSoft)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(folder.name)
                                    .font(LectraTypography.headlineMedium)
                                    .foregroundColor(LectraColor.textPrimary)
                                Text(folder.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(LectraTypography.captionMedium)
                                    .foregroundColor(LectraColor.textTertiary)
                            }

                            Spacer(minLength: 0)

                            if !isSelectionMode {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(LectraColor.textTertiary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 58)
                        .background(
                            RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                                .fill(LectraColor.surfaceElevated.opacity(0.58))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                                .stroke(LectraColor.edgeStroke, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                ForEach(filteredDocuments) { doc in
                    documentListRow(for: doc)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func folderGridCard(for folder: LocalFolder) -> some View {
        let metrics = libraryGridMetrics
        let protectedFolderManagerName = importedFolderManagerName(for: folder.id)
        let isProtectedFolder = protectedFolderManagerName != nil
        let allowsFolderDeletion = canDeleteFolder(folder.id)
        VaultFolderCardView(
            folderName: folder.name,
            subtitle: folder.createdAt.formatted(date: .abbreviated, time: .shortened),
            metrics: metrics,
            accent: folderAccentColor(for: folder),
            iconSystemName: folder.iconSystemName,
            showsOptionsButton: !isSelectionMode && (!isProtectedFolder || allowsFolderDeletion),
            isOptionsVisible: !isSelectionMode && activeFolderOptionsID == folder.id,
            onOpen: {
                if isSelectionMode {
                    toggleFolderSelection(folder.id)
                } else {
                    openFolder(folder)
                }
            },
            onOptionsTap: {
                guard !isSelectionMode else { return }
                if activeFolderOptionsID == folder.id {
                    activeFolderOptionsID = nil
                } else {
                    activeFolderOptionsID = folder.id
                }
            }
        )
        .frame(width: metrics.cardWidth, height: metrics.folderTotalHeight, alignment: .topLeading)
        .accessibilityIdentifier("library.folder.card.\(folder.id.uuidString)")
        .overlay(alignment: .topLeading) {
            if isSelectionMode {
                LibrarySelectionIndicatorView(isSelected: activeSelectedFolderIDs.contains(folder.id))
                    .padding(10)
            }
        }
        .popover(
            isPresented: Binding(
                get: { !isSelectionMode && activeFolderOptionsID == folder.id },
                set: { isPresented in
                    if !isPresented && activeFolderOptionsID == folder.id {
                        activeFolderOptionsID = nil
                    }
                }
            ),
            arrowEdge: .top
        ) {
            if let activeFolder = folders.first(where: { $0.id == folder.id }) {
                FolderOptionsPopoverView(
                    folderName: activeFolder.name,
                    selectedColorHex: activeFolder.colorHex,
                    selectedIcon: activeFolder.iconSystemName ?? "folder",
                    isProtectedFolder: isProtectedFolder,
                    protectedFolderManagerName: protectedFolderManagerName,
                    canMoveToTrash: allowsFolderDeletion,
                    onClose: {
                        activeFolderOptionsID = nil
                    },
                    onRename: { newName in
                        renameFolder(folderId: activeFolder.id, to: newName)
                    },
                    onSelectColor: { colorHex in
                        updateFolderColor(folderId: activeFolder.id, colorHex: colorHex)
                    },
                    onSelectIcon: { iconSystemName in
                        updateFolderIcon(folderId: activeFolder.id, iconSystemName: iconSystemName)
                    },
                    onMove: {
                        moveFolderToTop(folderId: activeFolder.id)
                    },
                    onOpenInWindow: {
                        openFolder(activeFolder)
                        activeFolderOptionsID = nil
                    },
                    onExport: {
                        exportFolder(activeFolder)
                        activeFolderOptionsID = nil
                    },
                    onMoveToTrash: {
                        deleteFolder(folderId: activeFolder.id)
                        activeFolderOptionsID = nil
                    }
                )
                .presentationCompactAdaptation(.popover)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard !isSelectionMode else { return false }
            return handleDrop(items: items, into: folder.id)
        }
    }

    @ViewBuilder
    private func documentGridCard(for doc: LocalDocument) -> some View {
        let metrics = libraryGridMetrics
        let baseCard = DocumentCardView(
            document: doc,
            subtitle: formattedDocumentGridDate(for: doc),
            metrics: metrics,
            onOptionsTap: isSelectionMode ? nil : {
                selectedDocumentForOptions = doc
            },
            onSyncRetryTap: doc.syncState == .failed ? {
                Task { await DocumentSyncCoordinator.shared.retry(documentId: doc.id) }
            } : nil
        )
        .frame(width: metrics.cardWidth, height: metrics.pdfTotalHeight, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            if isSelectionMode {
                LibrarySelectionIndicatorView(isSelected: selectedDocumentIDs.contains(doc.id))
                    .padding(10)
            }
        }
        .onTapGesture {
            handleDocumentTap(doc)
        }
        .accessibilityIdentifier("library.document.card.\(doc.id.uuidString)")

        if isSelectionMode {
            baseCard
        } else {
            baseCard
                .draggable(doc.id.uuidString)
        }
    }

    private func documentListRow(for doc: LocalDocument) -> some View {
        Button {
            handleDocumentTap(doc)
        } label: {
            HStack(spacing: 12) {
                if isSelectionMode {
                    LibrarySelectionIndicatorView(isSelected: selectedDocumentIDs.contains(doc.id))
                }

                MiniDocumentPreview(document: doc)
                    .frame(width: 48, height: 64)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(doc.title)
                            .font(LectraTypography.bodyEmphasis)
                            .foregroundColor(LectraColor.textPrimary)
                            .lineLimit(1)

                        if doc.syncState != .idle {
                            DocumentSyncBadgeView(
                                state: doc.syncState,
                                onRetryTap: doc.syncState == .failed ? {
                                    Task { await DocumentSyncCoordinator.shared.retry(documentId: doc.id) }
                                } : nil
                            )
                        }

                        if !isSelectionMode {
                            Button {
                                toggleFavorite(for: doc)
                            } label: {
                                Image(systemName: doc.isFavorite ? "star.fill" : "star")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(doc.isFavorite ? LectraColor.warning : LectraColor.textTertiary)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)

                            Button {
                                selectedDocumentForOptions = doc
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(LectraColor.accentSoft)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text(formattedDocumentDate(for: doc))
                        .font(LectraTypography.captionMedium)
                        .foregroundColor(LectraColor.textTertiary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 72)
            .background(
                RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                    .fill(LectraColor.surfaceElevated.opacity(0.58))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func utilityButtons(showSearch: Bool) -> some View {
        HStack(spacing: 10) {
            if showSearch {
                searchButton
            }

            avatarButton
        }
    }

    private var avatarButton: some View {
        Button {
            openAccountSettings()
        } label: {
            ProfileAvatarView(
                avatarURL: authManager.avatarURL,
                fallbackName: authManager.userName ?? authManager.userEmail,
                size: 18
            )
            .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
            .background(controlSurface)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open account settings")
        .accessibilityHint("Shows account, integration, and backup settings.")
        .accessibilityIdentifier("library.account")
    }

    private var controlSurface: some View {
        RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
            .fill(LectraColor.surfaceFloating.opacity(0.84))
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
    }

    private var filterMenu: some View {
        Menu {
            if currentFolderId == nil {
                ForEach(LibraryFilter.allCases) { filter in
                    Button {
                        documentFilter = filter
                    } label: {
                        if documentFilter == filter {
                            Label(filter.title, systemImage: "checkmark")
                        } else {
                            Text(filter.title)
                        }
                    }
                }
            } else {
                Button {
                    documentFilter = .all
                } label: {
                    Label("All", systemImage: "checkmark")
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 14, weight: .bold))
                Text(filterTitle)
                    .font(LectraTypography.bodyEmphasis)
            }
            .foregroundColor(LectraColor.textPrimary)
            .padding(.horizontal, 12)
            .frame(minHeight: LectraSizing.minHitTarget)
            .background(controlSurface)
        }
        .disabled(isSelectionMode)
        .opacity(isSelectionMode ? 0.5 : 1)
    }

    private var filterTitle: String {
        if currentFolderId != nil {
            return "All"
        }
        return documentFilter.title
    }

    private var selectButton: some View {
        Button {
            if isSelectionMode {
                exitSelectionMode()
            } else {
                enterSelectionMode()
            }
        } label: {
            Text(isSelectionMode ? "Cancel" : "Select")
                .font(LectraTypography.bodyEmphasis)
                .foregroundColor(LectraColor.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: LectraSizing.minHitTarget)
                .background(controlSurface)
        }
        .buttonStyle(.plain)
    }

    private func newButton(compact: Bool) -> some View {
        Button {
            showCreateMenu = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                if !compact {
                    Text("New")
                        .font(LectraTypography.bodyEmphasis)
                        .fixedSize()
                }
            }
            .foregroundColor(LectraColor.textPrimary)
            .padding(.horizontal, compact ? 0 : 14)
            .frame(width: compact ? LectraSizing.minHitTarget : nil, height: LectraSizing.minHitTarget)
            .background(
                RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [LectraColor.accentSoft, LectraColor.accentDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSelectionMode)
        .opacity(isSelectionMode ? 0.5 : 1)
        .accessibilityIdentifier("library.new")
        .popover(isPresented: $showCreateMenu, arrowEdge: .top) {
            CreateMenuPopoverView(
                onNotebook: {
                    showCreateMenu = false
                    createBlankLocalDocument(title: "Notebook")
                },
                onTextDoc: {
                    showCreateMenu = false
                    createBlankLocalDocument(title: "Text Doc")
                },
                onWhiteboard: {
                    showCreateMenu = false
                    createBlankLocalDocument(title: "Whiteboard")
                },
                onImport: {
                    showCreateMenu = false
                    filePickerContentTypes = [.pdf]
                    showFilePicker = true
                },
                onFolder: {
                    showCreateMenu = false
                    showCreateFolderAlert = true
                },
                onQuickNote: {
                    showCreateMenu = false
                    createBlankLocalDocument(title: "QuickNote")
                },
                onImage: {
                    showCreateMenu = false
                    filePickerContentTypes = [.image]
                    showFilePicker = true
                }
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private var viewModeButton: some View {
        Button {
            showViewMenu = true
        } label: {
            Image(systemName: viewMode == .grid ? "square.grid.2x2" : "list.bullet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(LectraColor.textPrimary)
                .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
                .background(controlSurface)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showViewMenu, arrowEdge: .top) {
            ViewAndSortPopoverView(
                viewMode: viewMode,
                sortMode: sortMode,
                onSelectGrid: {
                    viewMode = .grid
                    showViewMenu = false
                },
                onSelectList: {
                    viewMode = .list
                    showViewMenu = false
                },
                onSelectSort: { mode in
                    sortMode = mode
                    showViewMenu = false
                }
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private var cloudButton: some View {
        Button {
            showCloudStatus = true
        } label: {
            Image(systemName: "icloud.and.arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(LectraColor.textPrimary)
                .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
                .background(controlSurface)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showCloudStatus, arrowEdge: .top) {
            CloudStatusPopoverView(
                isCloudSyncEnabled: isCloudSyncEnabled,
                isICloudAvailable: isICloudAvailable,
                isSyncInProgress: isSyncingCloud,
                lastSyncDate: lastCloudSyncDate,
                lastBackupDate: lastBackupDate,
                onSyncNow: {
                    Task {
                        await runCloudSync(triggeredByUser: true)
                    }
                },
                onBackupNow: {
                    Task {
                        await runManualBackup()
                    }
                },
                onOpenSettings: {
                    showCloudStatus = false
                    openAccountSettings(at: .cloudBackup)
                }
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private var selectionActionBar: some View {
        VStack(spacing: 10) {
            Divider()
                .background(LectraColor.edgeStroke)

            HStack(spacing: 12) {
                Text("\(selectedItemCount) selected")
                    .font(LectraTypography.bodyEmphasis)
                    .foregroundColor(LectraColor.textPrimary)

                bulkActionButton(
                    title: isAllSelected ? "Deselect All" : "Select All",
                    icon: isAllSelected ? "circle" : "checkmark.circle.fill",
                    isEnabled: hasSelectableItems,
                    action: {
                        toggleSelectAll()
                    }
                )

                Spacer(minLength: 0)

                bulkActionButton(
                    title: "Move",
                    icon: "arrowshape.turn.up.right",
                    isEnabled: canMoveSelection,
                    action: {
                        showBulkMoveSheet = true
                    }
                )

                bulkActionButton(
                    title: "Ask",
                    icon: "sparkles",
                    isEnabled: canAskAcrossSelection,
                    action: {
                        presentCrossDocumentAsk()
                    }
                )

                bulkActionButton(
                    title: "Export",
                    icon: "square.and.arrow.up",
                    isEnabled: canExportSelection,
                    action: {
                        performBulkExport()
                    }
                )

                bulkActionButton(
                    title: "Delete",
                    icon: "trash",
                    isDestructive: true,
                    isEnabled: canDeleteSelection,
                    action: {
                        showBulkDeleteConfirm = true
                    }
                )
            }
        }
    }

    private func bulkActionButton(
        title: String,
        icon: String,
        isDestructive: Bool = false,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(isDestructive ? LectraColor.accentDestructive : LectraColor.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                    .fill(LectraColor.surfaceFloating.opacity(0.84))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(LectraColor.accentSoft)
            Text("Loading documents")
                .font(LectraTypography.body)
                .foregroundColor(LectraColor.textSecondary)
        }
    }

    private var emptyDocumentsView: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder")
                .font(.system(size: 32, weight: .regular))
                .foregroundColor(LectraColor.accentCool)
            Text("No items yet")
                .font(LectraTypography.headline)
                .foregroundColor(LectraColor.textPrimary)
            Text("Tap New to create a notebook or import a document.")
                .font(LectraTypography.body)
                .foregroundColor(LectraColor.textSecondary)
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                .fill(LectraColor.surfaceElevated.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                        .stroke(LectraColor.edgeStroke, lineWidth: 1)
                )
        )
    }

    private var searchOverlay: some View {
        ZStack {
            LectraGradient.appBackdrop
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button {
                        withAnimation(LectraMotion.quick) {
                            showSearchOverlay = false
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text(currentFolder?.name ?? "Documents")
                                .font(LectraTypography.bodyEmphasis)
                        }
                        .foregroundColor(LectraColor.accentSoft)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }

                WorkspaceSearchBar(text: $searchText, placeholder: "Search documents and page text", isEditable: true)

                HStack {
                    Text(trimmedSearchText.isEmpty ? "Recently Opened Documents" : "Search Results")
                        .font(LectraTypography.titleSmall)
                        .foregroundColor(LectraColor.textPrimary)

                    Spacer(minLength: 0)

                    if trimmedSearchText.isEmpty,
                       !recentlyOpenedDocuments.isEmpty {
                        Button("Clear") {
                            clearRecentDocuments()
                        }
                        .font(LectraTypography.bodyEmphasis)
                        .foregroundColor(LectraColor.accentSoft)
                    }
                }

                if trimmedSearchText.isEmpty {
                    if recentlyOpenedDocuments.isEmpty {
                        Spacer(minLength: 0)
                        Text("No recent documents yet")
                            .font(LectraTypography.body)
                            .foregroundColor(LectraColor.textSecondary)
                        Spacer(minLength: 0)
                    } else {
                        ScrollView {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 148, maximum: 148), spacing: 14, alignment: .top)],
                                alignment: .leading,
                                spacing: 18
                            ) {
                                ForEach(recentlyOpenedDocuments) { doc in
                                    Button {
                                        showSearchOverlay = false
                                        handleDocumentTap(doc)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 7) {
                                            MiniDocumentPreview(document: doc)
                                                .frame(width: 148, height: 192)
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                            Text(doc.title)
                                                .font(LectraTypography.body)
                                                .foregroundColor(LectraColor.textPrimary)
                                                .lineLimit(2)
                                                .frame(width: 148, alignment: .leading)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.bottom, 20)
                        }
                        .scrollIndicators(.hidden)
                    }
                } else if isSearchingDocuments && globalSearchResults.isEmpty {
                    Spacer(minLength: 0)
                    ProgressView()
                        .tint(LectraColor.accentSoft)
                    Spacer(minLength: 0)
                } else if globalSearchResults.isEmpty {
                    Spacer(minLength: 0)
                    Text("No documents or page text matched \"\(trimmedSearchText)\"")
                        .font(LectraTypography.body)
                        .foregroundColor(LectraColor.textSecondary)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(globalSearchResults) { result in
                                if let doc = document(for: result.documentId) {
                                    Button {
                                        showSearchOverlay = false
                                        handleDocumentTap(doc, initialPage: result.pageIndex)
                                    } label: {
                                        HStack(alignment: .top, spacing: 14) {
                                            MiniDocumentPreview(document: doc)
                                                .frame(width: 72, height: 96)

                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack(spacing: 8) {
                                                    Text(result.title)
                                                        .font(LectraTypography.bodyEmphasis)
                                                        .foregroundColor(LectraColor.textPrimary)
                                                        .lineLimit(2)

                                                    Text(result.kind == .pageText ? "Page Text" : "Metadata")
                                                        .font(.system(size: 11, weight: .bold))
                                                        .foregroundColor(result.kind == .pageText ? LectraColor.accentCool : LectraColor.accentSoft)
                                                        .padding(.horizontal, 8)
                                                        .frame(height: 22)
                                                        .background((result.kind == .pageText ? LectraColor.accentCool : LectraColor.accentSoft).opacity(0.14))
                                                        .clipShape(Capsule())
                                                }

                                                Text(result.subtitle)
                                                    .font(LectraTypography.captionMedium)
                                                    .foregroundColor(LectraColor.textTertiary)

                                                if let snippet = result.snippet, !snippet.isEmpty {
                                                    Text(snippet)
                                                        .font(LectraTypography.captionMedium)
                                                        .foregroundColor(LectraColor.textSecondary)
                                                        .lineLimit(3)
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(14)
                                        .background(
                                            RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous)
                                                .fill(LectraColor.surfaceElevated.opacity(0.72))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous)
                                                .stroke(LectraColor.edgeStroke, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 20)
                    }
                    .scrollIndicators(.hidden)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func enterSelectionMode() {
        isSelectionMode = true
        clearSelection()
        activeFolderOptionsID = nil
        selectedDocumentForOptions = nil
        showCreateMenu = false
        showViewMenu = false
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        showBulkDeleteConfirm = false
        showBulkMoveSheet = false
        clearSelection()
    }

    private func clearSelection() {
        selectedFolderIDs.removeAll()
        selectedDocumentIDs.removeAll()
    }

    private func toggleSelectAll() {
        if isAllSelected {
            clearSelection()
        } else {
            selectedFolderIDs.formUnion(visibleSelectableFolderIDs)
            selectedDocumentIDs.formUnion(visibleSelectableDocumentIDs)
        }
    }

    private func toggleFolderSelection(_ folderId: UUID) {
        if selectedFolderIDs.contains(folderId) {
            selectedFolderIDs.remove(folderId)
        } else {
            selectedFolderIDs.insert(folderId)
        }
    }

    private func toggleDocumentSelection(_ documentId: UUID) {
        if selectedDocumentIDs.contains(documentId) {
            selectedDocumentIDs.remove(documentId)
        } else {
            selectedDocumentIDs.insert(documentId)
        }
    }

    private var backNavigationLabel: String {
        guard let currentFolderId else { return "Documents" }
        if let parentFolderId = parentFolderId(for: currentFolderId),
           let parentFolder = folders.first(where: { $0.id == parentFolderId }) {
            return parentFolder.name
        }
        return "Documents"
    }

    private func parentFolderId(for folderId: UUID) -> UUID? {
        if folderId == importedCanvascopeFolderId {
            return importedRootFolderId
        }
        if let folder = folders.first(where: { $0.id == folderId }),
           let parentId = folder.parentFolderId,
           folders.contains(where: { $0.id == parentId }) {
            return parentId
        }
        return nil
    }

    private func selectSection(_ section: LibrarySection) {
        activeSection = section
        showSearchOverlay = false
        if section != .documents {
            exitSelectionMode()
        }

        if section != .documents {
            currentFolderId = nil
        }
    }

    private func openFolder(_ folder: LocalFolder) {
        if isSelectionMode {
            exitSelectionMode()
        }
        withAnimation(LectraMotion.quick) {
            currentFolderId = folder.id
            documentFilter = .all
        }

        if isImportedCanvascopeFolder(folder.id) {
            Task {
                await refreshRemoteDocuments()
            }
        }
    }

    private func returnToVaultRoot() {
        if isSelectionMode {
            exitSelectionMode()
        }
        withAnimation(LectraMotion.quick) {
            if let currentFolderId,
               let parentFolderId = parentFolderId(for: currentFolderId) {
                self.currentFolderId = parentFolderId
            } else {
                currentFolderId = nil
            }
        }
    }

    private func updateImportedFolderPolling() {
        guard scenePhase == .active,
              currentFolderId == importedCanvascopeFolderId else {
            stopImportedFolderPolling()
            return
        }
        startImportedFolderPollingIfNeeded()
    }

    private func startImportedFolderPollingIfNeeded() {
        guard importedFolderPollingTask == nil else { return }
        importedFolderPollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: importedFolderPollingIntervalNanoseconds)
                guard !Task.isCancelled else { break }

                let shouldContinue = await MainActor.run {
                    scenePhase == .active && currentFolderId == importedCanvascopeFolderId
                }
                guard shouldContinue else { break }

                await refreshRemoteDocuments()
            }

            await MainActor.run {
                importedFolderPollingTask = nil
            }
        }
    }

    private func stopImportedFolderPolling() {
        importedFolderPollingTask?.cancel()
        importedFolderPollingTask = nil
    }

    private func document(for id: UUID) -> LocalDocument? {
        documents.first(where: { $0.id == id })
    }

    private func folderId(for document: LocalDocument) -> UUID? {
        guard let stored = documentFolderMap[document.id.uuidString] else { return nil }
        return UUID(uuidString: stored)
    }

    private func lockedImportedFolder(for document: LocalDocument) -> LocalFolder? {
        if document.status != .local {
            return importedCanvascopeFolder
        }
        guard let mappedFolderId = folderId(for: document),
              isProtectedImportedFolder(mappedFolderId) else {
            return nil
        }
        return folders.first(where: { $0.id == mappedFolderId })
    }

    private func lockedImportedFolderId(for document: LocalDocument) -> UUID? {
        lockedImportedFolder(for: document)?.id
    }

    private func lockedImportedFolderName(for document: LocalDocument) -> String {
        lockedImportedFolder(for: document)?.name ?? importedCanvascopeFolderName
    }

    private func isDocumentLockedToImportedFolder(_ document: LocalDocument) -> Bool {
        lockedImportedFolder(for: document) != nil
    }

    private func isDocumentInProtectedImportedFolder(_ document: LocalDocument) -> Bool {
        // Product rule: only the managed import folders themselves are locked.
        // Documents living inside them (including the synced Canvascope imports)
        // are user content and can be deleted.
        return false
    }

    private func isImportedCanvascopeFolder(_ folderId: UUID) -> Bool {
        folders.first(where: { $0.id == folderId })?.systemTag == importedCanvascopeSystemTag
    }

    private func ensureImportedFolderHierarchyExists() {
        ensureImportedRootFolderExists()
        ensureImportedCanvascopeFolderExists()
        migrateLegacyThirdPartyImportFolders()
    }

    private func importedFolderManagerName(for folderId: UUID) -> String? {
        if let systemTag = folders.first(where: { $0.id == folderId })?.systemTag {
            switch systemTag {
            case importedRootSystemTag:
                return "Lectra"
            case importedCanvascopeSystemTag:
                return "Canvascope"
            default:
                break
            }
        }
        if let ancestorTag = ancestorImportedSystemTag(for: folderId) {
            switch ancestorTag {
            case importedCanvascopeSystemTag: return "Canvascope"
            default: return nil
            }
        }
        return nil
    }

    private func isProtectedImportedFolder(_ folderId: UUID) -> Bool {
        importedFolderManagerName(for: folderId) != nil
    }

    private func canDeleteFolder(_ folderId: UUID) -> Bool {
        // Anything nested inside the managed import folder is user content
        // and can be deleted; only the managed folders themselves are locked.
        if isImportedManagedDescendantFolder(folderId) { return true }
        return !isProtectedImportedFolder(folderId)
    }

    /// True for a user-created folder nested under a managed import folder.
    /// The system folders themselves (and the "Imported" root) return false.
    private func isImportedManagedDescendantFolder(_ folderId: UUID) -> Bool {
        guard let folder = folders.first(where: { $0.id == folderId }) else { return false }
        guard folder.systemTag == nil else { return false }
        return ancestorImportedSystemTag(for: folderId) != nil
    }

    private func ancestorImportedSystemTag(for folderId: UUID) -> String? {
        var current: UUID? = folderId
        var visited: Set<UUID> = []
        let recognized: Set<String> = [
            importedCanvascopeSystemTag
        ]
        while let id = current {
            if !visited.insert(id).inserted { return nil }
            guard let folder = folders.first(where: { $0.id == id }) else { return nil }
            if let tag = folder.systemTag, recognized.contains(tag) {
                return tag
            }
            current = folder.parentFolderId
        }
        return nil
    }

    private func managedFolderNotice(for folderId: UUID) -> String {
        if let managerName = importedFolderManagerName(for: folderId) {
            return "This folder is managed by \(managerName) and can’t be changed."
        }
        return "This folder is managed and can’t be changed."
    }

    private func folderDeletionNotice(for folderId: UUID) -> String {
        if isProtectedImportedFolder(folderId) {
            return managedFolderNotice(for: folderId)
        }
        return "This folder can’t be deleted."
    }

    private func reservedImportedFolderNameNotice(for proposedName: String) -> String? {
        if proposedName.localizedCaseInsensitiveCompare(importedFolderName) == .orderedSame {
            return "\"\(importedFolderName)\" is reserved."
        }
        if proposedName.localizedCaseInsensitiveCompare(importedCanvascopeFolderName) == .orderedSame {
            return "\"\(importedCanvascopeFolderName)\" is reserved."
        }
        return nil
    }

    private func ensureImportedRootFolderExists() {
        var changed = false

        var taggedIndices = folders.indices.filter { folders[$0].systemTag == importedRootSystemTag }
        if taggedIndices.count > 1 {
            for idx in taggedIndices.dropFirst() {
                folders[idx].systemTag = nil
                changed = true
            }
            taggedIndices = folders.indices.filter { folders[$0].systemTag == importedRootSystemTag }
        }

        if let taggedIndex = taggedIndices.first {
            if folders[taggedIndex].name != importedFolderName {
                folders[taggedIndex].name = importedFolderName
                changed = true
            }
            if changed {
                saveFolders()
            }
            return
        }

        if let namedIndex = folders.firstIndex(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(importedFolderName) == .orderedSame
        }) {
            folders[namedIndex].name = importedFolderName
            folders[namedIndex].systemTag = importedRootSystemTag
            changed = true
        } else {
            let folder = LocalFolder(
                id: UUID(),
                name: importedFolderName,
                createdAt: Date(),
                colorHex: nil,
                iconSystemName: "tray.full",
                systemTag: importedRootSystemTag,
                parentFolderId: nil
            )
            folders = [folder] + folders
            changed = true
        }

        if changed {
            saveFolders()
        }
    }

    private func ensureImportedCanvascopeFolderExists() {
        var changed = false

        var taggedIndices = folders.indices.filter { folders[$0].systemTag == importedCanvascopeSystemTag }
        if taggedIndices.count > 1 {
            for idx in taggedIndices.dropFirst() {
                folders[idx].systemTag = nil
                changed = true
            }
            taggedIndices = folders.indices.filter { folders[$0].systemTag == importedCanvascopeSystemTag }
        }

        if let taggedIndex = taggedIndices.first {
            if folders[taggedIndex].name != importedCanvascopeFolderName {
                folders[taggedIndex].name = importedCanvascopeFolderName
                changed = true
            }
            if changed {
                saveFolders()
            }
            return
        }

        if let namedIndex = folders.firstIndex(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(importedCanvascopeFolderName) == .orderedSame
        }) {
            folders[namedIndex].name = importedCanvascopeFolderName
            folders[namedIndex].systemTag = importedCanvascopeSystemTag
            changed = true
        } else {
            let folder = LocalFolder(
                id: UUID(),
                name: importedCanvascopeFolderName,
                createdAt: Date(),
                colorHex: nil,
                iconSystemName: "folder",
                systemTag: importedCanvascopeSystemTag,
                parentFolderId: nil
            )
            folders = [folder] + folders
            changed = true
        }

        if changed {
            saveFolders()
        }
    }

    private func migrateLegacyThirdPartyImportFolders() {
        guard let importedRootFolderId else { return }
        var changed = false
        let legacyTags: Set<String> = [
            legacyCanvasImportSystemTag,
            legacySubmissionImportSystemTag
        ]

        for index in folders.indices {
            guard let tag = folders[index].systemTag,
                  legacyTags.contains(tag) else {
                continue
            }

            folders[index].systemTag = nil
            folders[index].parentFolderId = importedRootFolderId
            folders[index].name = neutralLegacyImportFolderName(excluding: index)
            changed = true
        }

        if changed {
            saveFolders()
        }
    }

    private func neutralLegacyImportFolderName(excluding excludedIndex: Array<LocalFolder>.Index) -> String {
        let existingNames = Set(
            folders.indices
                .filter { $0 != excludedIndex }
                .map { folders[$0].name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        let baseName = "Imported Files"
        if !existingNames.contains(baseName.lowercased()) {
            return baseName
        }

        var suffix = 2
        while existingNames.contains("\(baseName) \(suffix)".lowercased()) {
            suffix += 1
        }
        return "\(baseName) \(suffix)"
    }

    private func routeNonLocalDocumentsToImportedFolder() {
        guard let importedFolderId = importedCanvascopeFolderId else { return }

        var changed = false
        for doc in documents where doc.status != .local {
            let key = doc.id.uuidString
            // Course imports carry a folder chain (Course / subfolder…); nest them
            // under "Imported From Canvascope". Legacy single sends have no chain
            // and stay in the root folder.
            let chain = doc.sourceDocumentData?.importFolderChain ?? []
            let targetId: UUID
            if chain.isEmpty {
                targetId = importedFolderId
            } else {
                let result = ensureCanvascopeSubfolderChain(chain, under: importedFolderId)
                if result.didCreate { changed = true }
                targetId = result.leafId
            }
            let required = targetId.uuidString
            if documentFolderMap[key] != required {
                documentFolderMap[key] = required
                changed = true
            }
        }

        if changed {
            saveFolders()
            saveDocumentFolderMap()
        }
    }

    /// Find or create the nested folder chain under the Canvascope import folder,
    /// returning the leaf folder id. Created folders are managed descendants
    /// (no systemTag) so they render normally and remain user-deletable.
    private func ensureCanvascopeSubfolderChain(
        _ chain: [String],
        under rootId: UUID
    ) -> (leafId: UUID, didCreate: Bool) {
        var parentId = rootId
        var didCreate = false
        for rawName in chain {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }
            if let existing = folders.first(where: {
                $0.parentFolderId == parentId
                    && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) {
                parentId = existing.id
            } else {
                let folder = LocalFolder(
                    id: UUID(),
                    name: name,
                    createdAt: Date(),
                    colorHex: nil,
                    iconSystemName: "folder",
                    systemTag: nil,
                    parentFolderId: parentId
                )
                folders.append(folder)
                parentId = folder.id
                didCreate = true
            }
        }
        return (parentId, didCreate)
    }

    private func folderAccentColor(for folder: LocalFolder) -> Color {
        if let customHex = folder.colorHex {
            return Color(hex: UInt(customHex))
        }

        let palette: [Color] = [
            Color(hex: 0xC95E5E),
            Color(hex: 0xCC6F5A),
            Color(hex: 0xB98B45),
            Color(hex: 0x8B6AA6)
        ]

        let index = stablePaletteIndex(for: folder.id.uuidString, modulo: palette.count)
        return palette[index]
    }

    private func stablePaletteIndex(for key: String, modulo: Int) -> Int {
        guard modulo > 0 else { return 0 }
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return Int(hash % UInt64(modulo))
    }

    private func formattedDocumentDate(for document: LocalDocument) -> String {
        document.updatedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private func formattedDocumentGridDate(for document: LocalDocument) -> String {
        let date = document.updatedAt.formatted(.dateTime.month(.abbreviated).day().year())
        let time = document.updatedAt.formatted(.dateTime.hour().minute())
        return "\(date) • \(time)"
    }

    private func documentType(for document: LocalDocument) -> String {
        if let url = document.localPDFURL {
            return url.pathExtension.lowercased()
        }
        return "pdf"
    }

    private func loadRecentDocuments() {
        guard let ids = UserDefaults.standard.array(forKey: recentDocumentsDefaultsKey) as? [String] else {
            recentlyOpenedDocumentIds = []
            return
        }
        recentlyOpenedDocumentIds = ids.compactMap(UUID.init(uuidString:))
    }

    private func saveRecentDocuments() {
        let ids = recentlyOpenedDocumentIds.map(\.uuidString)
        UserDefaults.standard.set(ids, forKey: recentDocumentsDefaultsKey)
    }

    private func markDocumentAsRecentlyOpened(_ docId: UUID) {
        recentlyOpenedDocumentIds.removeAll(where: { $0 == docId })
        recentlyOpenedDocumentIds.insert(docId, at: 0)

        if recentlyOpenedDocumentIds.count > 24 {
            recentlyOpenedDocumentIds = Array(recentlyOpenedDocumentIds.prefix(24))
        }

        saveRecentDocuments()
    }

    private func markDocumentAsEdited(_ documentId: UUID) {
        guard let doc = document(for: documentId) else { return }

        let now = Date()
        doc.updatedAt = now

        if doc.status == .local {
            updateSavedLocalDocumentTitle(documentId: doc.id, title: doc.title, updatedAt: now)
        }

        documents = Array(documents)
    }

    private func clearRecentDocuments() {
        recentlyOpenedDocumentIds = []
        saveRecentDocuments()
    }

    private func loadCloudPreferences() {
        let defaults = UserDefaults.standard
        isICloudAvailable = ICloudDocumentStore.shared.isAvailable()
        if defaults.object(forKey: cloudSyncEnabledDefaultsKey) != nil {
            isCloudSyncEnabled = defaults.bool(forKey: cloudSyncEnabledDefaultsKey)
        } else {
            isCloudSyncEnabled = false
        }

        if defaults.object(forKey: autoBackupEnabledDefaultsKey) != nil {
            isAutoBackupEnabled = defaults.bool(forKey: autoBackupEnabledDefaultsKey)
        } else {
            isAutoBackupEnabled = true
        }

        if let storedLastSync = defaults.object(forKey: lastCloudSyncDefaultsKey) as? Date {
            lastCloudSyncDate = storedLastSync
        }

        if let storedLastBackup = defaults.object(forKey: lastBackupDefaultsKey) as? Date {
            lastBackupDate = storedLastBackup
        }
    }

    private func setCloudSyncEnabled(_ isEnabled: Bool) {
        if isEnabled {
            isICloudAvailable = ICloudDocumentStore.shared.isAvailable()
            guard isICloudAvailable else {
                isCloudSyncEnabled = false
                UserDefaults.standard.set(false, forKey: cloudSyncEnabledDefaultsKey)
                featureNotice = "Sign in to iCloud and enable iCloud Drive to sync Lectra documents."
                return
            }
        }

        isCloudSyncEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: cloudSyncEnabledDefaultsKey)

        if isEnabled {
            Task {
                await runCloudSync(triggeredByUser: false)
            }
        }
    }

    private func setAutoBackupEnabled(_ isEnabled: Bool) {
        isAutoBackupEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: autoBackupEnabledDefaultsKey)
    }

    private func runCloudSync(triggeredByUser: Bool) async {
        guard launchConfiguration == nil else { return }

        await MainActor.run {
            isICloudAvailable = ICloudDocumentStore.shared.isAvailable()
        }

        if !isCloudSyncEnabled {
            if triggeredByUser {
                await MainActor.run {
                    featureNotice = "Enable Cloud Sync in Cloud & Backup Settings first."
                }
            }
            return
        }

        guard isICloudAvailable else {
            if triggeredByUser {
                await MainActor.run {
                    featureNotice = "iCloud Drive is unavailable. Your documents remain saved on this device."
                }
            }
            return
        }

        guard !isSyncingCloud else { return }

        await MainActor.run {
            isSyncingCloud = true
        }
        defer {
            Task { @MainActor in
                isSyncingCloud = false
            }
        }

        await refreshRemoteDocuments()

        do {
            try await ICloudDocumentStore.shared.mirrorDocuments(documents, repository: repository)
            await MainActor.run {
                lastCloudSyncDate = Date()
                UserDefaults.standard.set(lastCloudSyncDate, forKey: lastCloudSyncDefaultsKey)
            }
        } catch {
            await MainActor.run {
                showFeatureNotice(
                    "Saved locally, but iCloud sync did not finish: \(error.localizedDescription)",
                    force: triggeredByUser
                )
            }
        }

        guard isAutoBackupEnabled || triggeredByUser else { return }

        do {
            let backupTargets = try createLibraryBackupSnapshots()
            await MainActor.run {
                lastBackupDate = Date()
                UserDefaults.standard.set(lastBackupDate, forKey: lastBackupDefaultsKey)
                loadRecoverySnapshots()
                if triggeredByUser {
                    let backupSummary = backupTargets.joined(separator: " + ")
                    showCloudSuccessToast("Synced to iCloud. Backup saved to \(backupSummary).")
                }
            }
        } catch {
            await MainActor.run {
                featureNotice = "Sync finished, but backup failed: \(error.localizedDescription)"
            }
        }
    }

    private func runManualBackup() async {
        do {
            let backupTargets = try createLibraryBackupSnapshots()
            await MainActor.run {
                lastBackupDate = Date()
                UserDefaults.standard.set(lastBackupDate, forKey: lastBackupDefaultsKey)
                loadRecoverySnapshots()
                let backupSummary = backupTargets.joined(separator: " + ")
                showCloudSuccessToast("Backup saved to \(backupSummary).")
            }
        } catch {
            await MainActor.run {
                featureNotice = "Manual backup failed: \(error.localizedDescription)"
            }
        }
    }

    private func createLibraryBackupSnapshots() throws -> [String] {
        var savedTargets: [String] = []
        savedTargets.append(try createLibraryBackupSnapshot(location: .onDevice))

        if isCloudSyncEnabled,
           isICloudAvailable,
           backupRootURL(location: .iCloudDrive) != nil {
            savedTargets.append(try createLibraryBackupSnapshot(location: .iCloudDrive))
        }

        return savedTargets
    }

    private func createLibraryBackupSnapshot(location: RecoverySnapshotLocation) throws -> String {
        let fileManager = FileManager.default
        guard let backupRoot = backupRootURL(location: location) else {
            throw ICloudDocumentStoreError.unavailable
        }
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let snapshotFolder = backupRoot.appendingPathComponent("snapshot-\(timestamp)", isDirectory: true)
        try fileManager.createDirectory(at: snapshotFolder, withIntermediateDirectories: true)

        var snapshotItems: [RecoverySnapshotManifestItem] = []
        snapshotItems.reserveCapacity(documents.count)

        for doc in documents {
            var relativePDFPath: String?
            var pdfChecksum: String?
            let candidateURL = existingPreferredBackupURL(for: doc)

            if let localURL = candidateURL,
               fileManager.fileExists(atPath: localURL.path) {
                let docBackupFolder = snapshotFolder.appendingPathComponent(doc.id.uuidString, isDirectory: true)
                try fileManager.createDirectory(at: docBackupFolder, withIntermediateDirectories: true)

                let destination = docBackupFolder.appendingPathComponent("document.pdf")
                try? fileManager.removeItem(at: destination)
                try fileManager.copyItem(at: localURL, to: destination)
                relativePDFPath = "\(doc.id.uuidString)/document.pdf"
                pdfChecksum = checksum(for: destination)
            }

            snapshotItems.append(
                .init(
                    id: doc.id,
                    title: doc.title,
                    createdAt: doc.createdAt,
                    updatedAt: doc.updatedAt,
                    relativePDFPath: relativePDFPath,
                    folderId: folderId(for: doc),
                    isFavorite: doc.isFavorite,
                    checksum: pdfChecksum
                )
            )
        }

        let snapshot = RecoverySnapshotManifest(
            createdAt: Date(),
            source: location == .iCloudDrive ? "iCloud Drive" : "On Device",
            ownerUserId: authManager.userId,
            folders: folders.map {
                SavedLocalFolder(
                    id: $0.id,
                    name: $0.name,
                    createdAt: $0.createdAt,
                    colorHex: $0.colorHex,
                    iconSystemName: $0.iconSystemName,
                    systemTag: $0.systemTag,
                    parentFolderId: $0.parentFolderId
                )
            },
            items: snapshotItems
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        try data.write(to: snapshotFolder.appendingPathComponent("manifest.json"), options: [.atomic])
        try data.write(to: backupRoot.appendingPathComponent("latest-manifest.json"), options: [.atomic])

        return snapshot.source
    }

    private func backupRootURL(location: RecoverySnapshotLocation) -> URL? {
        let fileManager = FileManager.default
        switch location {
        case .onDevice:
            return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("LectraBackups", isDirectory: true)
        case .iCloudDrive:
            guard let ubiquitousRoot = fileManager.url(forUbiquityContainerIdentifier: nil) else {
                return nil
            }
            return ubiquitousRoot
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("LectraBackups", isDirectory: true)
        }
    }

    private func existingPreferredBackupURL(for document: LocalDocument) -> URL? {
        let annotatedURL = repository.localAnnotatedPDFURL(for: document.id)
        if FileManager.default.fileExists(atPath: annotatedURL.path) {
            return annotatedURL
        }

        if let localURL = document.localPDFURL,
           FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        return nil
    }

    private func checksum(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func loadRecoverySnapshots() {
        recoverySnapshotsLoadGeneration += 1
        let generation = recoverySnapshotsLoadGeneration
        let roots = availableRecoveryRoots()
        let ownerUserId = authManager.userId

        DispatchQueue.global(qos: .utility).async {
            let snapshots = Self.readRecoverySnapshots(from: roots, ownerUserId: ownerUserId)
            DispatchQueue.main.async {
                guard generation == recoverySnapshotsLoadGeneration else { return }
                recoverySnapshots = snapshots
            }
        }
    }

    private static func readRecoverySnapshots(
        from roots: [(RecoverySnapshotLocation, URL)],
        ownerUserId: UUID?
    ) -> [RecoverySnapshot] {
        guard let ownerUserId else { return [] }
        let fileManager = FileManager.default
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var snapshots: [RecoverySnapshot] = []

        for (location, rootURL) in roots {
            guard fileManager.fileExists(atPath: rootURL.path),
                  let snapshotFolders = try? fileManager.contentsOfDirectory(
                    at: rootURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                  ) else {
                continue
            }

            for snapshotFolder in snapshotFolders {
                let values = try? snapshotFolder.resourceValues(forKeys: [.isDirectoryKey])
                guard values?.isDirectory == true else { continue }

                let manifestURL = snapshotFolder.appendingPathComponent("manifest.json")
                guard fileManager.fileExists(atPath: manifestURL.path),
                      let data = try? Data(contentsOf: manifestURL),
                      let manifest = try? decoder.decode(RecoverySnapshotManifest.self, from: data) else {
                    continue
                }
                guard manifest.ownerUserId == ownerUserId else { continue }

                snapshots.append(
                    RecoverySnapshot(
                        id: "\(location.rawValue)-\(snapshotFolder.lastPathComponent)",
                        manifestURL: manifestURL,
                        snapshotFolderURL: snapshotFolder,
                        createdAt: manifest.createdAt,
                        source: manifest.source,
                        itemCount: manifest.items.count,
                        location: location,
                        ownerUserId: manifest.ownerUserId,
                        items: manifest.items
                    )
                )
            }
        }

        return snapshots.sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
    }

    private func availableRecoveryRoots() -> [(RecoverySnapshotLocation, URL)] {
        var roots: [(RecoverySnapshotLocation, URL)] = []

        if let onDeviceRoot = backupRootURL(location: .onDevice) {
            roots.append((.onDevice, onDeviceRoot))
        }
        if let iCloudRoot = backupRootURL(location: .iCloudDrive) {
            roots.append((.iCloudDrive, iCloudRoot))
        }

        return roots
    }

    private func restoreSnapshot(_ snapshot: RecoverySnapshot, mode: RecoveryRestoreMode) async {
        let fileManager = FileManager.default
        let documentsRoot = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let manifestData = try? Data(contentsOf: snapshot.manifestURL),
              let manifest = try? decoder.decode(RecoverySnapshotManifest.self, from: manifestData) else {
            featureNotice = "This recovery snapshot could not be read."
            return
        }
        guard manifest.ownerUserId == authManager.userId else {
            featureNotice = "This recovery snapshot belongs to another Lectra account."
            return
        }

        let folderMapping = resolveRestoredFolderIDs(from: manifest.folders)
        var restoredDocumentCount = 0
        var skippedDocumentCount = 0

        for item in manifest.items {
            guard let relativePDFPath = item.relativePDFPath else {
                skippedDocumentCount += 1
                continue
            }

            let sourceURL = snapshot.snapshotFolderURL.appendingPathComponent(relativePDFPath)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                skippedDocumentCount += 1
                continue
            }

            if let expectedChecksum = item.checksum,
               let actualChecksum = checksum(for: sourceURL),
               actualChecksum != expectedChecksum {
                skippedDocumentCount += 1
                continue
            }

            let targetDocumentId = mode == .replace ? item.id : UUID()
            let destinationFolder = documentsRoot
                .appendingPathComponent("pdfs", isDirectory: true)
                .appendingPathComponent(targetDocumentId.uuidString, isDirectory: true)
            let destinationURL = destinationFolder.appendingPathComponent("original.pdf")

            do {
                try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
                try? fileManager.removeItem(at: destinationURL)
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                skippedDocumentCount += 1
                continue
            }

            let resolvedTitle = mode == .copy ? uniqueRestoredTitle(base: item.title) : item.title
            let resolvedFolderID = item.folderId.flatMap { folderMapping[$0] }
            let existingDocument = document(for: targetDocumentId)

            if let existingDocument {
                existingDocument.title = resolvedTitle
                existingDocument.localPDFURL = destinationURL
                existingDocument.updatedAt = item.updatedAt
                existingDocument.isFavorite = item.isFavorite ?? false
            } else {
                let restoredDocument = LocalDocument(
                    title: resolvedTitle,
                    localURL: destinationURL,
                    id: targetDocumentId,
                    isFavorite: item.isFavorite ?? false,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt
                )
                documents = [restoredDocument] + documents
            }

            storeLocalDocumentMetadata(
                docId: targetDocumentId,
                title: resolvedTitle,
                relativePath: "pdfs/\(targetDocumentId.uuidString)/original.pdf",
                folderId: resolvedFolderID,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt
            )
            ThumbnailCache.shared.invalidate(documentId: targetDocumentId)
            restoredDocumentCount += 1
        }

        refreshLibraryDerivatives(reloadRecoverySnapshots: true)
        runGlobalSearch()

        let restoredScope = snapshot.location == .iCloudDrive ? "iCloud Drive" : "on-device recovery"
        if restoredDocumentCount == 0 {
            featureNotice = "No documents could be restored from \(restoredScope)."
            return
        }

        let modeTitle = mode == .copy ? "as copies" : "by replacing current versions"
        if skippedDocumentCount > 0 {
            featureNotice = "Restored \(restoredDocumentCount) document(s) \(modeTitle) from \(restoredScope). Skipped \(skippedDocumentCount) item(s)."
        } else {
            featureNotice = "Restored \(restoredDocumentCount) document(s) \(modeTitle) from \(restoredScope)."
        }
    }

    private func resolveRestoredFolderIDs(from savedFolders: [SavedLocalFolder]) -> [UUID: UUID] {
        var resolved: [UUID: UUID] = [:]
        var didChangeFolders = false

        for savedFolder in savedFolders {
            if let systemTag = savedFolder.systemTag,
               let existing = folders.first(where: { $0.systemTag == systemTag }) {
                resolved[savedFolder.id] = existing.id
                continue
            }

            if let existing = folders.first(where: { $0.id == savedFolder.id }) {
                resolved[savedFolder.id] = existing.id
                continue
            }

            if let existing = folders.first(where: {
                $0.name.localizedCaseInsensitiveCompare(savedFolder.name) == .orderedSame &&
                $0.systemTag == savedFolder.systemTag
            }) {
                resolved[savedFolder.id] = existing.id
                continue
            }

            let restoredFolder = LocalFolder(
                id: savedFolder.id,
                name: savedFolder.name,
                createdAt: savedFolder.createdAt,
                colorHex: savedFolder.colorHex,
                iconSystemName: savedFolder.iconSystemName,
                systemTag: savedFolder.systemTag,
                parentFolderId: savedFolder.parentFolderId
            )
            folders = [restoredFolder] + folders
            resolved[savedFolder.id] = restoredFolder.id
            didChangeFolders = true
        }

        if didChangeFolders {
            saveFolders()
        }

        return resolved
    }

    private func uniqueRestoredTitle(base: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed = trimmed.isEmpty ? "Recovered Document" : "\(trimmed) Restored"
        var candidate = seed
        var suffix = 2

        while documents.contains(where: { $0.title.localizedCaseInsensitiveCompare(candidate) == .orderedSame }) {
            candidate = "\(seed) \(suffix)"
            suffix += 1
        }

        return candidate
    }

    private func canModifyContents(of folderId: UUID?) -> Bool {
        guard let folderId else { return true }
        guard !isProtectedImportedFolder(folderId) else {
            featureNotice = "Imported folders are read-only."
            return false
        }
        return true
    }

    private func handleDrop(items: [String], into folderId: UUID) -> Bool {
        guard !isSelectionMode else { return false }
        let documentIDs = items.compactMap(UUID.init(uuidString:))
        guard !documentIDs.isEmpty else { return false }

        withAnimation(LectraMotion.quick) {
            for documentId in documentIDs {
                moveDocument(documentId: documentId, to: folderId, shouldAnimate: false)
            }
        }
        return true
    }

    private func performBulkExport() {
        let urls = exportableSelectionURLs
        guard !urls.isEmpty else {
            featureNotice = "No local documents available to export from this selection."
            return
        }

        sharePayload = SharePayload(urls: urls)
        exitSelectionMode()
    }

    private func performBulkMove(to targetFolderId: UUID?) {
        let docsToMove = selectedDocumentsOnly
        guard !docsToMove.isEmpty else {
            featureNotice = "Select at least one document to move."
            return
        }
        guard canModifyContents(of: targetFolderId) else { return }
        guard docsToMove.allSatisfy({ $0.status == .local }) else {
            featureNotice = "Imported docs can’t be moved from Select mode."
            return
        }

        withAnimation(LectraMotion.quick) {
            for doc in docsToMove {
                moveDocument(documentId: doc.id, to: targetFolderId)
            }
        }

        exitSelectionMode()
    }

    private func performBulkDelete() {
        let folderTreeIDs = selectedFolderTreeIDs
        let directDocsToDelete = selectedDocumentsOnly.filter { doc in
            guard let mappedFolderId = folderId(for: doc) else { return true }
            return !folderTreeIDs.contains(mappedFolderId)
        }
        guard !directDocsToDelete.isEmpty || !activeSelectedFolderIDs.isEmpty else { return }

        for folderID in activeSelectedFolderIDs where !canDeleteFolder(folderID) {
            featureNotice = folderDeletionNotice(for: folderID)
            return
        }

        if directDocsToDelete.contains(where: isDocumentInProtectedImportedFolder) {
            featureNotice = "Imported folders are read-only."
            return
        }

        for doc in directDocsToDelete {
            removeDocument(doc)
        }

        for folderID in activeSelectedFolderIDs {
            deleteFolder(folderId: folderID)
        }

        exitSelectionMode()
    }

    // MARK: - Loading

    private func loadDocuments() async {
        isLoading = true
        errorMessage = nil

        loadSavedFolders()
        loadDocumentFolderMap()

        let savedLocalDocs = loadSavedLocalDocuments()
        documents = savedLocalDocs
        applyTitleOverrides()
        refreshLibraryDerivatives()
        pruneFolderMappingForCurrentData()

        if let currentFolderId,
           !folders.contains(where: { $0.id == currentFolderId }) {
            self.currentFolderId = nil
        }

        isLoading = false

        Task(priority: .utility) {
            await refreshRemoteDocuments()
        }
    }

    private func refreshRemoteDocuments() async {
        guard launchConfiguration == nil else { return }
        let expectedUserId = authManager.userId
        guard expectedUserId != nil else { return }

        let shouldRefresh = await MainActor.run { () -> Bool in
            if isRefreshingRemoteDocuments {
                return false
            }
            isRefreshingRemoteDocuments = true
            return true
        }
        guard shouldRefresh else { return }
        defer {
            Task { @MainActor in
                isRefreshingRemoteDocuments = false
            }
        }

        do {
            let items = try await repository.fetchDocuments()
            let fetched = items.map { LocalDocument(from: $0) }
            let currentLocalDocs = documents.filter { $0.status == .local }
            let merged = mergeDocuments(fetched: fetched, local: currentLocalDocs)

            await MainActor.run {
                guard authManager.userId == expectedUserId else { return }
                documents = merged
                applyTitleOverrides()
                ensureImportedFolderHierarchyExists()

                for doc in documents where doc.status != .local {
                    if repository.isPDFCachedLocally(documentId: doc.id) {
                        doc.localPDFURL = repository.localPDFURL(for: doc.id)
                    }
                }

                routeNonLocalDocumentsToImportedFolder()
                refreshLibraryDerivatives()
                pruneFolderMappingForCurrentData()
                if let currentFolderId,
                   !folders.contains(where: { $0.id == currentFolderId }) {
                    self.currentFolderId = nil
                }
            }
        } catch {
            await MainActor.run {
                if documents.isEmpty && folders.isEmpty {
                    errorMessage = "Failed to load: \(error.localizedDescription)"
                }
            }
        }
    }

    private func loadSavedLocalDocuments() -> [LocalDocument] {
        guard let data = UserDefaults.standard.data(forKey: localPDFsDefaultsKey),
              let saved = try? JSONDecoder().decode([SavedLocalDocument].self, from: data) else {
            return []
        }

        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var savedLocalDocs: [LocalDocument] = []

        for savedItem in saved {
            guard savedItem.belongs(to: authManager.userId) else { continue }
            let fileURL = documentsDir.appendingPathComponent(savedItem.localPath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

            let createdAt: Date
            let updatedAt: Date

            if let savedCreated = savedItem.createdAt, let savedUpdated = savedItem.updatedAt {
                createdAt = savedCreated
                updatedAt = savedUpdated
            } else {
                let fileAttributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
                let fileCreated = fileAttributes?[.creationDate] as? Date
                let fileModified = fileAttributes?[.modificationDate] as? Date
                createdAt = savedItem.createdAt ?? fileCreated ?? fileModified ?? Date()
                updatedAt = savedItem.updatedAt ?? fileModified ?? createdAt
            }

            let doc = LocalDocument(
                title: savedItem.title,
                localURL: fileURL,
                id: savedItem.id,
                isFavorite: savedItem.isFavorite ?? false,
                sourceURLString: savedItem.sourceURLString,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
            savedLocalDocs.append(doc)
        }

        return savedLocalDocs
    }

    private func mergeDocuments(fetched: [LocalDocument], local: [LocalDocument]) -> [LocalDocument] {
        var merged: [LocalDocument] = []
        var seen: Set<UUID> = []

        for doc in fetched where seen.insert(doc.id).inserted {
            merged.append(doc)
        }

        for doc in local where seen.insert(doc.id).inserted {
            merged.append(doc)
        }

        return merged
    }

    private func openEditor(documentId: UUID, initialPage: Int? = nil) {
        markDocumentAsRecentlyOpened(documentId)
        editorRoute = EditorRoute(documentId: documentId, initialPage: initialPage)
    }

    /// Routes an OpenDocumentIntent (Siri / Shortcuts) to the editor.
    private func handleOpenDocumentRequest(_ notification: Notification) {
        guard let idString = notification.userInfo?["documentId"] as? String,
              let documentId = UUID(uuidString: idString) else { return }

        if activeSection != .documents {
            activeSection = .documents
        }

        if let doc = document(for: documentId) {
            handleDocumentTap(doc)
        } else {
            // Document may not be merged into memory yet — open by id directly.
            openEditor(documentId: documentId)
        }
    }

    private func existingLectraDocumentID(forSourceURL url: URL) -> UUID? {
        let normalizedSourceURL = normalizedImportedSourceURL(url.absoluteString)
        guard !normalizedSourceURL.isEmpty else { return nil }

        return documents.first { document in
            normalizedImportedSourceURL(document.sourceURLString) == normalizedSourceURL
        }?.id
    }

    private func normalizedImportedSourceURL(_ raw: String?) -> String {
        guard let raw else { return "" }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        guard var components = URLComponents(string: trimmed) else {
            return trimmed.lowercased()
        }

        components.fragment = nil

        if let queryItems = components.queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems.sorted {
                if $0.name == $1.name {
                    return ($0.value ?? "") < ($1.value ?? "")
                }
                return $0.name < $1.name
            }
        }

        return (components.url?.absoluteString ?? trimmed).lowercased()
    }

    private func applySyncPayload(_ payload: DocumentSyncStatusPayload) {
        guard let doc = document(for: payload.documentId) else { return }
        doc.apply(metadata: payload.metadata)

        if let editedAt = payload.metadata.lastLocalEditAt {
            doc.updatedAt = max(doc.updatedAt, editedAt)
        }

        documents = Array(documents)
        DocumentSearchIndex.shared.refresh(
            documents: [doc],
            folderNameByDocumentID: folderNameByDocumentID()
        )
    }

    private func applyPersistedMetadata() {
        for doc in documents {
            DocumentSyncCoordinator.shared.applyPersistedMetadata(to: doc)
        }
    }

    private func folderNameByDocumentID() -> [UUID: String] {
        Dictionary(
            uniqueKeysWithValues: documents.compactMap { doc in
                if let folderID = folderId(for: doc),
                   let folder = folders.first(where: { $0.id == folderID }) {
                    return (doc.id, folder.name)
                }
                if doc.isRemoteBacked {
                    return (doc.id, importedCanvascopeFolderName)
                }
                return nil
            }
        )
    }

    private func refreshLibraryDerivatives(reloadRecoverySnapshots: Bool = false) {
        applyPersistedMetadata()

        let folderMap = folderNameByDocumentID()
        DocumentSearchIndex.shared.refresh(documents: documents, folderNameByDocumentID: folderMap)

        if reloadRecoverySnapshots {
            loadRecoverySnapshots()
        }
    }

    private func runGlobalSearch() {
        searchRefreshTask?.cancel()

        guard !trimmedSearchText.isEmpty else {
            globalSearchResults = []
            isSearchingDocuments = false
            return
        }

        let query = trimmedSearchText
        isSearchingDocuments = true

        func performSearch() -> [DocumentSearchResult] {
            DocumentSearchIndex.shared.search(
                query: query,
                documents: documents,
                folderNameByDocumentID: folderNameByDocumentID()
            )
        }

        globalSearchResults = performSearch()
        isSearchingDocuments = false

        searchRefreshTask = Task { @MainActor in
            for _ in 0..<3 {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled, query == trimmedSearchText else { return }
                globalSearchResults = performSearch()
            }
        }
    }

    // MARK: - Document Tap

    private func handleDocumentTap(_ doc: LocalDocument, initialPage: Int? = nil) {
        if isSelectionMode {
            toggleDocumentSelection(doc.id)
            return
        }

        guard doc.localPDFURL != nil else {
            // Fast path: the wake-time prefetch usually already wrote this PDF to
            // disk. Open immediately instead of re-downloading or waiting.
            if repository.isPDFCachedLocally(documentId: doc.id) {
                let url = repository.localPDFURL(for: doc.id)
                doc.localPDFURL = url
                if doc.status == .downloading { doc.status = .pendingAnnotation }
                ThumbnailCache.shared.warmThumbnail(
                    documentId: doc.id,
                    pdfURL: url,
                    revision: doc.thumbnailRevision
                )
                openEditor(documentId: doc.id, initialPage: initialPage)
                return
            }

            Task {
                await MainActor.run {
                    doc.status = .downloading
                    documents = Array(documents)
                }

                do {
                    let url = try await repository.downloadPDF(
                        storagePath: doc.storagePath,
                        documentId: doc.id
                    )

                    await MainActor.run {
                        doc.localPDFURL = url
                        doc.status = .pendingAnnotation
                        doc.updatedAt = Date()
                        documents = Array(documents)
                        // Open the editor right away; thumbnail/index work is
                        // non-blocking and the PDF is already on disk.
                        openEditor(documentId: doc.id, initialPage: initialPage)
                        ThumbnailCache.shared.warmThumbnail(
                            documentId: doc.id,
                            pdfURL: url,
                            revision: doc.thumbnailRevision
                        )
                        DocumentSearchIndex.shared.refresh(
                            documents: [doc],
                            folderNameByDocumentID: folderNameByDocumentID()
                        )
                    }
                } catch {
                    await MainActor.run {
                        doc.status = .error
                        documents = Array(documents)
                        errorMessage = "Download failed: \(error.localizedDescription)"
                    }
                }
            }
            return
        }

        openEditor(documentId: doc.id, initialPage: initialPage)
    }

    // MARK: - Import

    private func importPickedFile(from url: URL, folderId: UUID? = nil) {
        if let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType {
            if contentType.conforms(to: .pdf) {
                importLocalPDF(from: url, folderId: folderId)
                return
            }

            if contentType.conforms(to: .image) {
                importImageAsPDF(from: url, folderId: folderId)
                return
            }
        }

        if let fallbackType = UTType(filenameExtension: url.pathExtension.lowercased()) {
            if fallbackType.conforms(to: .pdf) {
                importLocalPDF(from: url, folderId: folderId)
                return
            }

            if fallbackType.conforms(to: .image) {
                importImageAsPDF(from: url, folderId: folderId)
                return
            }
        }

        featureNotice = "Unsupported file type. Please choose a PDF or image."
    }

    private func importLocalPDF(from url: URL, folderId: UUID? = nil, sourceURL: URL? = nil) {
        let title = url.deletingPathExtension().lastPathComponent
        let doc = LocalDocument(
            title: title,
            localURL: url,
            sourceURLString: sourceURL.map(\.absoluteString)
        )

        let localFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pdfs", isDirectory: true)
            .appendingPathComponent(doc.id.uuidString, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: localFolder, withIntermediateDirectories: true)
            let destination = localFolder.appendingPathComponent("original.pdf")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: url, to: destination)
            doc.localPDFURL = destination

            let relativePath = "pdfs/\(doc.id.uuidString)/original.pdf"
            storeLocalDocumentMetadata(
                docId: doc.id,
                title: title,
                relativePath: relativePath,
                sourceURLString: doc.sourceURLString,
                folderId: folderId,
                createdAt: doc.createdAt,
                updatedAt: doc.updatedAt
            )

            documents = [doc] + documents
            refreshLibraryDerivatives()
            autoTitleImportedDocumentIfNeeded(doc)
            openEditor(documentId: doc.id)
        } catch {
            featureNotice = "Could not import PDF: \(error.localizedDescription)"
        }
    }

    private func importImageAsPDF(from url: URL, folderId: UUID? = nil) {
        guard let image = UIImage(contentsOfFile: url.path) ?? (try? Data(contentsOf: url)).flatMap(UIImage.init(data:)) else {
            featureNotice = "Could not load image for import."
            return
        }

        let title = url.deletingPathExtension().lastPathComponent
        let doc = LocalDocument(title: title, localURL: URL(fileURLWithPath: "/tmp/placeholder.pdf"))
        let localFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pdfs", isDirectory: true)
            .appendingPathComponent(doc.id.uuidString, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: localFolder, withIntermediateDirectories: true)

            let destination = localFolder.appendingPathComponent("original.pdf")
            let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
            let renderRect = aspectFitRect(for: image.size, in: pageRect.insetBy(dx: 24, dy: 24))
            let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

            let pdfData = renderer.pdfData { context in
                context.beginPage()
                UIColor.white.setFill()
                context.cgContext.fill(pageRect)
                image.draw(in: renderRect)
            }

            try? FileManager.default.removeItem(at: destination)
            try pdfData.write(to: destination, options: [.atomic])

            doc.localPDFURL = destination
            documents = [doc] + documents
            refreshLibraryDerivatives()

            let relativePath = "pdfs/\(doc.id.uuidString)/original.pdf"
            storeLocalDocumentMetadata(
                docId: doc.id,
                title: title,
                relativePath: relativePath,
                folderId: folderId,
                createdAt: doc.createdAt,
                updatedAt: doc.updatedAt
            )

            openEditor(documentId: doc.id)
        } catch {
            featureNotice = "Could not convert image to PDF: \(error.localizedDescription)"
        }
    }

    private func aspectFitRect(for size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fittedSize = CGSize(width: size.width * scale, height: size.height * scale)
        let origin = CGPoint(
            x: bounds.midX - fittedSize.width / 2,
            y: bounds.midY - fittedSize.height / 2
        )
        return CGRect(origin: origin, size: fittedSize)
    }

    private func createBlankLocalDocument(title: String) {
        guard canModifyContents(of: currentFolderId) else { return }
        let doc = LocalDocument(title: title, localURL: URL(fileURLWithPath: "/tmp/placeholder.pdf"))
        let localFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pdfs", isDirectory: true)
            .appendingPathComponent(doc.id.uuidString, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: localFolder, withIntermediateDirectories: true)

            let destination = localFolder.appendingPathComponent("original.pdf")
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
            let data = renderer.pdfData { context in
                context.beginPage()
                UIColor.white.setFill()
                context.cgContext.fill(CGRect(x: 0, y: 0, width: 612, height: 792))
            }
            try data.write(to: destination)

            doc.localPDFURL = destination
            documents = [doc] + documents
            refreshLibraryDerivatives()

            let relativePath = "pdfs/\(doc.id.uuidString)/original.pdf"
            storeLocalDocumentMetadata(
                docId: doc.id,
                title: title,
                relativePath: relativePath,
                folderId: currentFolderId,
                createdAt: doc.createdAt,
                updatedAt: doc.updatedAt
            )

            openEditor(documentId: doc.id)
        } catch {
            featureNotice = "Could not create a new file: \(error.localizedDescription)"
        }
    }

    private func createFolder(named: String) {
        let trimmed = named.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let reservedNotice = reservedImportedFolderNameNotice(for: trimmed) {
            featureNotice = reservedNotice
            return
        }

        let folder = LocalFolder(
            id: UUID(),
            name: trimmed,
            createdAt: Date(),
            colorHex: nil,
            iconSystemName: nil,
            systemTag: nil,
            parentFolderId: nil
        )
        folders = [folder] + folders
        saveFolders()
        runGlobalSearch()
    }

    @discardableResult
    private func findOrCreateChildFolder(
        named: String,
        parentFolderId parent: UUID?,
        iconSystemName: String? = nil
    ) -> UUID {
        let trimmed = named.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? "Untitled" : trimmed

        if let existing = folders.first(where: {
            $0.parentFolderId == parent
            && $0.systemTag == nil
            && $0.name.localizedCaseInsensitiveCompare(normalized) == .orderedSame
        }) {
            return existing.id
        }

        let folder = LocalFolder(
            id: UUID(),
            name: normalized,
            createdAt: Date(),
            colorHex: nil,
            iconSystemName: iconSystemName,
            systemTag: nil,
            parentFolderId: parent
        )
        folders.insert(folder, at: 0)
        saveFolders()
        return folder.id
    }

    private func loadSavedFolders() {
        guard let data = UserDefaults.standard.data(forKey: localFoldersDefaultsKey),
              let saved = try? JSONDecoder().decode([SavedLocalFolder].self, from: data) else {
            folders = []
            ensureImportedFolderHierarchyExists()
            return
        }

        folders = saved
            .map {
                LocalFolder(
                    id: $0.id,
                    name: $0.name,
                    createdAt: $0.createdAt,
                    colorHex: $0.colorHex,
                    iconSystemName: $0.iconSystemName,
                    systemTag: $0.systemTag,
                    parentFolderId: $0.parentFolderId
                )
            }
            .sorted { $0.createdAt > $1.createdAt }

        ensureImportedFolderHierarchyExists()
    }

    private func saveFolders() {
        let saved = folders.map {
            SavedLocalFolder(
                id: $0.id,
                name: $0.name,
                createdAt: $0.createdAt,
                colorHex: $0.colorHex,
                iconSystemName: $0.iconSystemName,
                systemTag: $0.systemTag,
                parentFolderId: $0.parentFolderId
            )
        }
        if let encoded = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(encoded, forKey: localFoldersDefaultsKey)
        }
    }

    private func renameFolder(folderId: UUID, to proposedName: String) {
        if isProtectedImportedFolder(folderId) {
            featureNotice = managedFolderNotice(for: folderId)
            return
        }

        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let reservedNotice = reservedImportedFolderNameNotice(for: trimmed) {
            featureNotice = reservedNotice
            return
        }

        guard let idx = folders.firstIndex(where: { $0.id == folderId }) else { return }
        guard folders[idx].name != trimmed else { return }
        folders[idx].name = trimmed
        saveFolders()
    }

    private func updateFolderColor(folderId: UUID, colorHex: Int) {
        if isProtectedImportedFolder(folderId) {
            featureNotice = managedFolderNotice(for: folderId)
            return
        }
        guard let idx = folders.firstIndex(where: { $0.id == folderId }) else { return }
        folders[idx].colorHex = colorHex
        folders[idx].createdAt = Date()
        saveFolders()
    }

    private func updateFolderIcon(folderId: UUID, iconSystemName: String) {
        if isProtectedImportedFolder(folderId) {
            featureNotice = managedFolderNotice(for: folderId)
            return
        }
        guard let idx = folders.firstIndex(where: { $0.id == folderId }) else { return }
        folders[idx].iconSystemName = iconSystemName
        saveFolders()
    }

    private func moveFolderToTop(folderId: UUID) {
        if isProtectedImportedFolder(folderId) {
            featureNotice = managedFolderNotice(for: folderId)
            return
        }
        guard let idx = folders.firstIndex(where: { $0.id == folderId }) else { return }
        folders[idx].createdAt = Date()
        folders.sort { $0.createdAt > $1.createdAt }
        saveFolders()
    }

    private func deleteFolder(folderId: UUID) {
        if isImportedManagedDescendantFolder(folderId) {
            deleteImportedManagedFolderTree(folderId: folderId)
            return
        }

        if !canDeleteFolder(folderId) {
            featureNotice = folderDeletionNotice(for: folderId)
            return
        }
        folders.removeAll { $0.id == folderId }

        for (docID, mappedFolderID) in documentFolderMap where mappedFolderID == folderId.uuidString {
            documentFolderMap.removeValue(forKey: docID)
        }
        saveDocumentFolderMap()
        saveFolders()

        if currentFolderId == folderId {
            currentFolderId = nil
        }
    }

    private func deleteImportedManagedFolderTree(folderId rootFolderId: UUID) {
        let parentFolderId = folders.first(where: { $0.id == rootFolderId })?.parentFolderId
        let folderIDs = descendantFolderIDs(including: rootFolderId)
        let docsToDelete = documents.filter { doc in
            guard let mappedFolderID = folderId(for: doc) else { return false }
            return folderIDs.contains(mappedFolderID)
        }

        for doc in docsToDelete {
            removeDocument(doc, allowProtectedImportedDelete: true)
        }

        folders.removeAll { folderIDs.contains($0.id) }
        for (docID, mappedFolderID) in documentFolderMap {
            if let id = UUID(uuidString: mappedFolderID), folderIDs.contains(id) {
                documentFolderMap.removeValue(forKey: docID)
            }
        }
        saveDocumentFolderMap()
        saveFolders()

        if let currentFolderId, folderIDs.contains(currentFolderId) {
            // Return to the deleted folder's parent (the managed import folder).
            self.currentFolderId = parentFolderId
        }
        refreshLibraryDerivatives()
        runGlobalSearch()
    }

    private func descendantFolderIDs(including rootFolderId: UUID) -> Set<UUID> {
        var result: Set<UUID> = [rootFolderId]
        var stack: [UUID] = [rootFolderId]

        while let parent = stack.popLast() {
            let children = folders
                .filter { $0.parentFolderId == parent }
                .map(\.id)
            for child in children where result.insert(child).inserted {
                stack.append(child)
            }
        }

        return result
    }

    private func storeLocalDocumentMetadata(
        docId: UUID,
        title: String,
        relativePath: String,
        sourceURLString: String? = nil,
        folderId: UUID?,
        createdAt: Date,
        updatedAt: Date
    ) {
        var existingSaved: [SavedLocalDocument] = []
        if let data = UserDefaults.standard.data(forKey: localPDFsDefaultsKey),
           let saved = try? JSONDecoder().decode([SavedLocalDocument].self, from: data) {
            existingSaved = saved.filter { $0.belongs(to: authManager.userId) }
        }

        var isFav = false
        var resolvedSourceURLString = sourceURLString
        if let index = existingSaved.firstIndex(where: { $0.id == docId }) {
            isFav = existingSaved[index].isFavorite ?? false
            if resolvedSourceURLString == nil {
                resolvedSourceURLString = existingSaved[index].sourceURLString
            }
        }

        let updated = SavedLocalDocument(
            id: docId,
            title: title,
            localPath: relativePath,
            sourceURLString: resolvedSourceURLString,
            ownerUserId: authManager.userId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isFavorite: isFav
        )

        if let index = existingSaved.firstIndex(where: { $0.id == docId }) {
            existingSaved[index] = updated
        } else {
            existingSaved.append(updated)
        }

        if let encoded = try? JSONEncoder().encode(existingSaved) {
            UserDefaults.standard.set(encoded, forKey: localPDFsDefaultsKey)
        }

        moveDocument(documentId: docId, to: folderId)
    }

    private func loadDocumentFolderMap() {
        documentFolderMap = (UserDefaults.standard.dictionary(forKey: documentFolderMapDefaultsKey) as? [String: String]) ?? [:]
    }

    private func saveDocumentFolderMap() {
        UserDefaults.standard.set(documentFolderMap, forKey: documentFolderMapDefaultsKey)
    }

    private func pruneFolderMappingForCurrentData() {
        let validDocumentIds = Set(documents.map { $0.id.uuidString })
        let validFolderIds = Set(folders.map { $0.id.uuidString })
        let oldMap = documentFolderMap

        documentFolderMap = documentFolderMap.filter { key, value in
            validDocumentIds.contains(key) && validFolderIds.contains(value)
        }

        if oldMap != documentFolderMap {
            saveDocumentFolderMap()
        }
    }

    private func moveDocument(documentId: UUID, to folderId: UUID?, shouldAnimate: Bool) {
        let key = documentId.uuidString
        var destination = folderId?.uuidString
        if let doc = document(for: documentId),
           let importedFolderId = lockedImportedFolderId(for: doc) {
            let lockedDestination = importedFolderId.uuidString
            if destination != lockedDestination {
                featureNotice = "Imported docs stay in \"\(lockedImportedFolderName(for: doc))\"."
                destination = lockedDestination
            }
        }
        let currentDestination = documentFolderMap[key]
        guard currentDestination != destination else { return }

        if let destination {
            documentFolderMap[key] = destination
        } else {
            documentFolderMap.removeValue(forKey: key)
        }

        saveDocumentFolderMap()
        runGlobalSearch()
    }

    private func moveDocument(documentId: UUID, to folderId: UUID?) {
        moveDocument(documentId: documentId, to: folderId, shouldAnimate: true)
    }

    private func duplicateDocument(_ doc: LocalDocument) {
        if isDocumentInProtectedImportedFolder(doc) {
            featureNotice = "Imported folders are read-only."
            return
        }
        guard let sourceURL = doc.localPDFURL else {
            featureNotice = "Open this file once, then duplicate it."
            return
        }

        let newId = UUID()
        let newTitle = "\(doc.title) Copy"
        let localFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pdfs", isDirectory: true)
            .appendingPathComponent(newId.uuidString, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: localFolder, withIntermediateDirectories: true)
            let destination = localFolder.appendingPathComponent("original.pdf")
            try FileManager.default.copyItem(at: sourceURL, to: destination)

            let duplicated = LocalDocument(
                title: newTitle,
                localURL: destination,
                id: newId,
                createdAt: Date(),
                updatedAt: Date()
            )

            documents = [duplicated] + documents
            refreshLibraryDerivatives()

            let relativePath = "pdfs/\(newId.uuidString)/original.pdf"
            storeLocalDocumentMetadata(
                docId: newId,
                title: newTitle,
                relativePath: relativePath,
                folderId: folderId(for: doc),
                createdAt: duplicated.createdAt,
                updatedAt: duplicated.updatedAt
            )
        } catch {
            featureNotice = "Could not duplicate file: \(error.localizedDescription)"
        }
    }

    private func exportDocument(_ doc: LocalDocument) {
        guard let localURL = doc.localPDFURL else {
            featureNotice = "Open this file once, then export it."
            return
        }
        sharePayload = SharePayload(urls: [localURL])
    }

    private func exportFolder(_ folder: LocalFolder) {
        let folderDocs = documents.filter { folderId(for: $0) == folder.id }
        let exportableURLs = folderDocs.compactMap(\.localPDFURL)

        guard !exportableURLs.isEmpty else {
            featureNotice = "No local documents available in this folder to export yet."
            return
        }

        sharePayload = SharePayload(urls: exportableURLs)
    }

    private func removeDocument(_ doc: LocalDocument, allowProtectedImportedDelete: Bool = false) {
        if !allowProtectedImportedDelete && isDocumentInProtectedImportedFolder(doc) {
            featureNotice = "Imported folders are read-only."
            return
        }
        documents.removeAll(where: { $0.id == doc.id })
        documentFolderMap.removeValue(forKey: doc.id.uuidString)
        saveDocumentFolderMap()

        removeSavedLocalDocument(documentId: doc.id)
        removeTitleOverride(documentId: doc.id)
        ThumbnailCache.shared.invalidate(documentId: doc.id)
        
        if doc.isRemoteBacked {
            Task {
                try? await repository.deleteRemoteDocument(rowId: doc.id)
            }
        }

        Task {
            await ICloudDocumentStore.shared.deleteMirroredDocument(documentId: doc.id)
        }

        let localFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pdfs", isDirectory: true)
            .appendingPathComponent(doc.id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: localFolder)
        refreshLibraryDerivatives()
        runGlobalSearch()
    }

    private func removeSavedLocalDocument(documentId: UUID) {
        guard let data = UserDefaults.standard.data(forKey: localPDFsDefaultsKey),
              var saved = try? JSONDecoder().decode([SavedLocalDocument].self, from: data) else {
            return
        }

        saved.removeAll(where: { $0.id == documentId })
        if let encoded = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(encoded, forKey: localPDFsDefaultsKey)
        }
    }

    // MARK: - Renaming

    /// After importing a document whose name is generic (e.g. "Scan 2026-06-14",
    /// "IMG_0042", "Untitled"), ask the on-device model to suggest a specific
    /// title from its opening pages and apply it. Best-effort and non-blocking:
    /// if intelligence is unavailable, the model declines, or the user renames it
    /// first, the original name is left untouched.
    private func autoTitleImportedDocumentIfNeeded(_ doc: LocalDocument) {
        let current = doc.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = doc.localPDFURL else { return }
        if #available(iOS 26.0, *) {
            guard current.isEmpty || DocumentAutoTagger.looksGeneric(current),
                  LectraIntelligence.isReady else { return }
            Task { @MainActor in
                // Need real text to title from — scanned/image-only PDFs have no
                // text layer, so skip rather than risk an invented title.
                let opening = await Task.detached(priority: .utility) {
                    PDFTextExtractor.fullText(at: url, pageLimit: 2)
                }.value
                guard opening.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40 else { return }
                guard let labels = try? await DocumentAutoTagger().labels(forFirstPagesOf: url) else { return }
                let suggested = labels.title.trimmingCharacters(in: .whitespacesAndNewlines)
                // Skip if the model gave nothing, or the user renamed it meanwhile.
                guard !suggested.isEmpty,
                      doc.title.trimmingCharacters(in: .whitespacesAndNewlines) == current else { return }
                persistTitleRename(for: doc, newTitle: suggested)
            }
        }
    }

    private func persistTitleRename(for doc: LocalDocument, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        doc.title = trimmed
        doc.updatedAt = Date()
        saveTitleOverride(documentId: doc.id, title: trimmed)

        if doc.status == .local {
            updateSavedLocalDocumentTitle(documentId: doc.id, title: trimmed, updatedAt: doc.updatedAt)
        }

        documents = Array(documents)
        runGlobalSearch()
    }

    private func applyTitleOverrides() {
        let overrides = loadTitleOverrides()
        guard !overrides.isEmpty else { return }

        for doc in documents {
            if let title = overrides[doc.id.uuidString], !title.isEmpty {
                doc.title = title
            }
        }
    }

    private func loadTitleOverrides() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: titleOverridesDefaultsKey) as? [String: String]) ?? [:]
    }

    private func saveTitleOverride(documentId: UUID, title: String) {
        var overrides = loadTitleOverrides()
        overrides[documentId.uuidString] = title
        UserDefaults.standard.set(overrides, forKey: titleOverridesDefaultsKey)
    }

    private func removeTitleOverride(documentId: UUID) {
        var overrides = loadTitleOverrides()
        overrides.removeValue(forKey: documentId.uuidString)
        UserDefaults.standard.set(overrides, forKey: titleOverridesDefaultsKey)
    }

    private func updateSavedLocalDocumentTitle(documentId: UUID, title: String, updatedAt: Date) {
        guard let data = UserDefaults.standard.data(forKey: localPDFsDefaultsKey),
              var saved = try? JSONDecoder().decode([SavedLocalDocument].self, from: data),
              let index = saved.firstIndex(where: { $0.id == documentId }) else {
            return
        }

        saved[index] = SavedLocalDocument(
            id: saved[index].id,
            title: title,
            localPath: saved[index].localPath,
            sourceURLString: saved[index].sourceURLString,
            ownerUserId: saved[index].ownerUserId,
            createdAt: saved[index].createdAt,
            updatedAt: updatedAt,
            isFavorite: saved[index].isFavorite
        )

        if let encoded = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(encoded, forKey: localPDFsDefaultsKey)
        }
    }

    private func toggleFavorite(for doc: LocalDocument) {
        doc.isFavorite.toggle()
        guard let data = UserDefaults.standard.data(forKey: localPDFsDefaultsKey),
              var saved = try? JSONDecoder().decode([SavedLocalDocument].self, from: data),
              let index = saved.firstIndex(where: { $0.id == doc.id }) else { return }
        
        saved[index].isFavorite = doc.isFavorite
        if let encoded = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(encoded, forKey: localPDFsDefaultsKey)
        }
    }
}

private struct VaultFolderCardView: View {
    let folderName: String
    let subtitle: String
    let metrics: LibraryGridMetrics
    let accent: Color
    let iconSystemName: String?
    let showsOptionsButton: Bool
    let isOptionsVisible: Bool
    let onOpen: () -> Void
    let onOptionsTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.92),
                                accent.opacity(0.52),
                                LectraColor.surfaceBG.opacity(0.92)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: metrics.folderArtworkHeight)
                    .overlay {
                        Image(systemName: iconSystemName ?? "folder.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundColor(LectraColor.paper.opacity(0.92))
                            .shadow(color: LectraColor.background.opacity(0.25), radius: 6, y: 2)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous)
                            .stroke(LectraColor.edgeStroke, lineWidth: 1)
                    )

                if showsOptionsButton {
                    Button(action: onOptionsTap) {
                        Image(systemName: isOptionsVisible ? "chevron.up.circle.fill" : "ellipsis.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(LectraColor.textPrimary)
                            .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Folder options")
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous))
            .onTapGesture(perform: onOpen)

            VStack(alignment: .leading, spacing: 0) {
                Text(folderName)
                    .font(LectraTypography.bodyEmphasis)
                    .foregroundColor(LectraColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture(perform: onOpen)
                .frame(height: 42, alignment: .topLeading)

                Text(subtitle)
                    .font(LectraTypography.captionMedium)
                    .foregroundColor(LectraColor.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: metrics.folderFooterHeight, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: metrics.folderTotalHeight, alignment: .topLeading)
    }
}

private struct FolderOptionsPopoverView: View {
    private enum PickerMode: String, CaseIterable, Identifiable {
        case color = "Color"
        case icon = "Icon"

        var id: String { rawValue }
    }

    private struct ColorOption: Identifiable {
        let id = UUID()
        let hex: Int
    }

    private let colorOptions: [ColorOption] = [
        .init(hex: 0xD44D4D),
        .init(hex: 0xD97A44),
        .init(hex: 0xD3B03C),
        .init(hex: 0x4FA46F),
        .init(hex: 0x3F9AA5),
        .init(hex: 0x7D65B7),
        .init(hex: 0xBE6EA9),
        .init(hex: 0xB0B0B0)
    ]

    private let iconOptions: [String] = [
        "folder",
        "graduationcap",
        "briefcase",
        "book.closed",
        "chart.bar.doc.horizontal",
        "pencil.and.scribble"
    ]

    let folderName: String
    let selectedColorHex: Int?
    let selectedIcon: String
    let isProtectedFolder: Bool
    let protectedFolderManagerName: String?
    let canMoveToTrash: Bool
    let onClose: () -> Void
    let onRename: (String) -> Void
    let onSelectColor: (Int) -> Void
    let onSelectIcon: (String) -> Void
    let onMove: () -> Void
    let onOpenInWindow: () -> Void
    let onExport: () -> Void
    let onMoveToTrash: () -> Void

    @State private var mode: PickerMode = .color
    @State private var draftName: String = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                if isProtectedFolder {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folderName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(LectraColor.textPrimary)
                        Text("Managed by \(protectedFolderManagerName ?? "Lectra")")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(LectraColor.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("Folder name", text: $draftName)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(LectraColor.textPrimary)
                }

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(LectraColor.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(LectraColor.surfaceFloating.opacity(0.88))
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if !isProtectedFolder {
                Picker("Folder Options", selection: $mode) {
                    ForEach(PickerMode.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                if mode == .color {
                    HStack(spacing: 12) {
                        ForEach(colorOptions) { option in
                            Button {
                                onSelectColor(option.hex)
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: UInt(option.hex)))
                                        .frame(width: 20, height: 20)
                                    if option.hex == selectedColorHex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(LectraColor.textPrimary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 10) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Button {
                                onSelectIcon(icon)
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(icon == selectedIcon ? LectraColor.sidebarSelection : LectraColor.surfaceFloating.opacity(0.78))
                                        .frame(width: 38, height: 34)
                                    Image(systemName: icon)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(LectraColor.textPrimary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            VStack(spacing: 0) {
                if !isProtectedFolder {
                    FolderMenuActionRow(title: "Move", icon: "arrow.right.square", action: onMove)
                }
                FolderMenuActionRow(title: "Open in New Window", icon: "menubar.dock.rectangle", action: onOpenInWindow)
                FolderMenuActionRow(
                    title: "Export",
                    icon: "square.and.arrow.up",
                    showDivider: canMoveToTrash,
                    action: onExport
                )
                if canMoveToTrash {
                    FolderMenuActionRow(title: "Move to Trash", icon: "trash", isDestructive: true, showDivider: false, action: onMoveToTrash)
                }
            }
            .background(LectraColor.surfaceFloating.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(12)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                .fill(LectraColor.surfaceElevated.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                        .stroke(LectraColor.edgeStroke, lineWidth: 1)
                )
        )
        .onAppear {
            draftName = folderName
        }
        .onChange(of: folderName) { _, newValue in
            draftName = newValue
        }
        .onSubmit {
            if !isProtectedFolder {
                onRename(draftName)
            }
        }
        .onDisappear {
            if !isProtectedFolder {
                onRename(draftName)
            }
        }
    }
}

private struct FolderMenuActionRow: View {
    let title: String
    let icon: String
    var isDestructive: Bool = false
    var showDivider: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 15, weight: .regular))
                Spacer(minLength: 0)
            }
            .foregroundColor(isDestructive ? LectraColor.accentDestructive : LectraColor.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 44)
        }
        .buttonStyle(.plain)

        if showDivider {
            Divider()
                .background(LectraColor.edgeStroke)
                .padding(.leading, 12)
        }
    }
}

private struct LibrarySelectionIndicatorView: View {
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(LectraColor.paper)
            .frame(width: 22, height: 22)
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(LectraColor.accent)
                }
            }
            .overlay(
                Circle()
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
            .shadow(color: LectraColor.background.opacity(0.32), radius: 2, x: 0, y: 1)
    }
}

private struct MiniDocumentPreview: View {
    @ObservedObject var document: LocalDocument

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LectraColor.paper)
            .overlay(
                Group {
                    if document.localPDFURL != nil {
                        CachedDocumentThumbnailView(
                            document: document,
                            size: CGSize(width: 96, height: 128)
                        )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        VStack(spacing: 3) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(LectraColor.textTertiary)
                            Text("PDF")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(LectraColor.textTertiary)
                        }
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
    }
}

private struct WorkspaceSearchBar: View {
    @Binding var text: String
    let placeholder: String
    let isEditable: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(LectraColor.accentCool)

            if isEditable {
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(LectraTypography.bodyEmphasis)
                    .foregroundColor(LectraColor.textPrimary)
            } else {
                Text(placeholder)
                    .font(LectraTypography.body)
                    .foregroundColor(LectraColor.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                .fill(LectraColor.surfaceElevated.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                .stroke(LectraColor.edgeStroke, lineWidth: 1)
        )
    }
}

private struct GenericEmptyStateView: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LectraColor.surfaceElevated.opacity(0.86))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(LectraGradient.spotlight.opacity(0.14))
                    )
                    .frame(width: 146, height: 146)

                Image(systemName: symbol)
                    .font(.system(size: 32, weight: .regular))
                    .foregroundColor(LectraColor.accentCool)
            }

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(LectraColor.textPrimary)

            Text(subtitle)
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(LectraColor.textSecondary)
        }
    }
}

private struct CreateMenuPopoverView: View {
    let onNotebook: () -> Void
    let onTextDoc: () -> Void
    let onWhiteboard: () -> Void
    let onImport: () -> Void
    let onFolder: () -> Void
    let onQuickNote: () -> Void
    let onImage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(LectraColor.textPrimary)

            VStack(spacing: 0) {
                PopoverActionRow(title: "Notebook", icon: "book.closed", action: onNotebook)
                PopoverActionRow(title: "Text Doc", icon: "doc.text", action: onTextDoc)
                PopoverActionRow(title: "Whiteboard", icon: "square.grid.3x3", action: onWhiteboard)
                PopoverActionRow(title: "Folder", icon: "folder", showDivider: false, action: onFolder)
            }
            .background(LectraColor.surfaceFloating.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Import")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(LectraColor.textTertiary)

            VStack(spacing: 0) {
                PopoverActionRow(title: "Import PDF", icon: "square.and.arrow.down", action: onImport)
                PopoverActionRow(title: "Image", icon: "photo", showDivider: false, action: onImage)
            }
            .background(LectraColor.surfaceFloating.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Quick Actions")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(LectraColor.textTertiary)

            VStack(spacing: 0) {
                PopoverActionRow(title: "QuickNote", icon: "square.and.pencil", showDivider: false, action: onQuickNote)
            }
            .background(LectraColor.surfaceFloating.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(14)
        .frame(width: 322)
        .background(
            RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                .fill(LectraColor.surfaceElevated.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                        .stroke(LectraColor.edgeStroke, lineWidth: 1)
                )
        )
    }
}

private struct ViewAndSortPopoverView: View {
    let viewMode: BrowserViewMode
    let sortMode: LibrarySortMode
    let onSelectGrid: () -> Void
    let onSelectList: () -> Void
    let onSelectSort: (LibrarySortMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Layout")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(LectraColor.textTertiary)

            HStack(spacing: 8) {
                layoutPill(
                    title: "Grid",
                    icon: "square.grid.2x2",
                    isSelected: viewMode == .grid,
                    action: onSelectGrid
                )
                layoutPill(
                    title: "List",
                    icon: "list.bullet",
                    isSelected: viewMode == .list,
                    action: onSelectList
                )
            }

            Text("Sort By")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(LectraColor.textTertiary)

            VStack(spacing: 0) {
                ForEach(LibrarySortMode.allCases, id: \.self) { mode in
                    PopoverActionRow(
                        title: mode.title,
                        icon: mode == sortMode ? "checkmark.circle.fill" : "circle",
                        showDivider: mode != LibrarySortMode.allCases.last,
                        action: { onSelectSort(mode) }
                    )
                }
            }
            .background(LectraColor.surfaceFloating.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(14)
        .frame(width: 286)
        .background(
            RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                .fill(LectraColor.surfaceElevated.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                        .stroke(LectraColor.edgeStroke, lineWidth: 1)
                )
        )
    }

    private func layoutPill(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(isSelected ? LectraColor.textPrimary : LectraColor.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .background(isSelected ? LectraColor.accentSoft : LectraColor.surfaceFloating.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct CloudStatusPopoverView: View {
    let isCloudSyncEnabled: Bool
    let isICloudAvailable: Bool
    let isSyncInProgress: Bool
    let lastSyncDate: Date
    let lastBackupDate: Date
    let onSyncNow: () -> Void
    let onBackupNow: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cloud")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(LectraColor.textPrimary)

            HStack(spacing: 8) {
                Image(systemName: isCloudSyncEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isCloudSyncEnabled ? Color(hex: 0x35B77A) : Color(hex: 0xC45454))
                Text(
                    isCloudSyncEnabled
                    ? (isICloudAvailable ? "Enabled (iCloud available)" : "Enabled (local fallback)")
                    : "Disabled"
                )
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(LectraColor.textPrimary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Last sync: \(lastSyncDate.formatted(date: .omitted, time: .shortened))")
                Text("Last backup: \(lastBackupDate.formatted(date: .omitted, time: .shortened))")
            }
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(LectraColor.textSecondary)

            HStack(spacing: 8) {
                actionPill(
                    title: isSyncInProgress ? "Syncing..." : "Sync Now",
                    icon: "arrow.clockwise",
                    isDisabled: isSyncInProgress,
                    action: onSyncNow
                )

                actionPill(
                    title: "Backup Now",
                    icon: "externaldrive",
                    isDisabled: false,
                    action: onBackupNow
                )
            }

            Button(action: onOpenSettings) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                    Text("Open Cloud & Backup Settings")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(LectraColor.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(LectraColor.surfaceFloating.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                        .stroke(LectraColor.edgeStroke, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                .fill(LectraColor.surfaceElevated.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                        .stroke(LectraColor.edgeStroke, lineWidth: 1)
                )
        )
    }

    private func actionPill(
        title: String,
        icon: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(LectraColor.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(isDisabled ? LectraColor.surfaceFloating.opacity(0.68) : LectraColor.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct DocumentOptionsSheetView: View {
    let documentTitle: String
    let onDuplicate: () -> Void
    let onMove: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    Text(documentTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)
                        .foregroundColor(LectraColor.textPrimary)
                    Spacer(minLength: 0)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(LectraColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 0) {
                    optionRow(title: "Duplicate", icon: "plus.square.on.square") {
                        dismiss()
                        onDuplicate()
                    }
                    optionRow(title: "Move", icon: "arrowshape.turn.up.right") {
                        dismiss()
                        onMove()
                    }
                    optionRow(title: "Export", icon: "square.and.arrow.up") {
                        dismiss()
                        onExport()
                    }
                    optionRow(title: "Move to Trash", icon: "trash", isDestructive: true) {
                        dismiss()
                        onDelete()
                    }
                }
                .background(LectraColor.surfaceFloating.opacity(0.84))
                .overlay(
                    RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous)
                        .stroke(LectraColor.edgeStroke, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Spacer(minLength: 0)
            }
            .padding(16)
            .background {
                LectraColor.background.ignoresSafeArea()
                LectraGradient.appBackdrop.opacity(0.64).ignoresSafeArea()
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.fraction(0.48)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func optionRow(title: String, icon: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 22)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.system(size: 14, weight: .regular))
            .foregroundColor(isDestructive ? LectraColor.accentDestructive : LectraColor.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 54)
        }
        .buttonStyle(.plain)

        if !isDestructive {
            Divider()
                .background(LectraColor.edgeStroke)
                .padding(.leading, 14)
        }
    }
}

struct MoveDocumentSheetView: View {
    let documentTitle: String
    let folders: [LocalFolder]
    let currentFolderId: UUID?
    let isLockedToImportedFolder: Bool
    let importedFolderName: String
    let onMove: (UUID?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: LectraSpacing.md) {
                Text(isLockedToImportedFolder
                     ? "This document is managed by its import source."
                     : "Choose where this document should live.")
                    .font(LectraTypography.body)
                    .foregroundColor(LectraColor.textSecondary)

                ScrollView {
                    VStack(spacing: LectraSpacing.sm) {
                        destinationRows
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
            .padding(LectraSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                LectraColor.background.ignoresSafeArea()
                LectraGradient.appBackdrop.opacity(0.70).ignoresSafeArea()
            }
            .navigationTitle(isLockedToImportedFolder ? "Locked Document" : "Move \"\(documentTitle)\"")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(LectraColor.accentSoft)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var destinationRows: some View {
        if isLockedToImportedFolder {
            CanvascopeMoveDestinationRow(
                title: importedFolderName,
                subtitle: "Imported documents stay in this protected folder.",
                icon: "lock.fill",
                tint: LectraColor.accentSoft,
                isSelected: true,
                isLocked: true
            )
        } else {
            Button {
                onMove(nil)
                dismiss()
            } label: {
                CanvascopeMoveDestinationRow(
                    title: "Documents",
                    subtitle: nil,
                    icon: "tray.full",
                    tint: LectraColor.accentCool,
                    isSelected: currentFolderId == nil,
                    isLocked: false
                )
            }
            .buttonStyle(.plain)

            ForEach(folders) { folder in
                Button {
                    onMove(folder.id)
                    dismiss()
                } label: {
                    CanvascopeMoveDestinationRow(
                        title: folder.name,
                        subtitle: nil,
                        icon: folder.iconSystemName ?? "folder.fill",
                        tint: LectraColor.accent,
                        isSelected: currentFolderId == folder.id,
                        isLocked: false
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct BulkMoveDocumentsSheetView: View {
    let selectedCount: Int
    let folders: [LocalFolder]
    let onMove: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: LectraSpacing.md) {
                Text("Choose a destination for the selected documents.")
                    .font(LectraTypography.body)
                    .foregroundColor(LectraColor.textSecondary)

                ScrollView {
                    VStack(spacing: LectraSpacing.sm) {
                        Button {
                            onMove(nil)
                            dismiss()
                        } label: {
                            CanvascopeMoveDestinationRow(
                                title: "Documents",
                                subtitle: nil,
                                icon: "tray.full",
                                tint: LectraColor.accentCool,
                                isSelected: false,
                                isLocked: false
                            )
                        }
                        .buttonStyle(.plain)

                        ForEach(folders) { folder in
                            Button {
                                onMove(folder.id)
                                dismiss()
                            } label: {
                                CanvascopeMoveDestinationRow(
                                    title: folder.name,
                                    subtitle: nil,
                                    icon: folder.iconSystemName ?? "folder.fill",
                                    tint: LectraColor.accent,
                                    isSelected: false,
                                    isLocked: false
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
            .padding(LectraSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                LectraColor.background.ignoresSafeArea()
                LectraGradient.appBackdrop.opacity(0.70).ignoresSafeArea()
            }
            .navigationTitle("Move \(selectedCount) Document\(selectedCount == 1 ? "" : "s")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(LectraColor.accentSoft)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct CanvascopeMoveDestinationRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    let tint: Color
    let isSelected: Bool
    let isLocked: Bool

    var body: some View {
        HStack(spacing: LectraSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LectraTypography.bodyEmphasis)
                    .foregroundColor(LectraColor.textPrimary)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(LectraTypography.captionMedium)
                        .foregroundColor(LectraColor.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if isLocked {
                Image(systemName: "lock.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(LectraColor.textTertiary)
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(LectraColor.accentSoft)
            }
        }
        .padding(.horizontal, LectraSpacing.md)
        .frame(minHeight: subtitle == nil ? 58 : 72)
        .background(
            RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous)
                .fill(isSelected ? LectraColor.sidebarSelection.opacity(0.88) : LectraColor.surfaceFloating.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous)
                .stroke(isSelected ? LectraColor.accentSoft.opacity(0.34) : LectraColor.edgeStroke, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous))
    }
}

struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// ProfileAvatarView has been moved to Shared/Components/ProfileAvatarView.swift

// MARK: - Document Picker (Files app)

struct DocumentPickerView: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes,
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
