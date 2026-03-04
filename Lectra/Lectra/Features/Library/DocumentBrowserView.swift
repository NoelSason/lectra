//
//  DocumentBrowserView.swift
//  Lectra
//
//  Goodnotes-inspired library shell for browsing folders and PDF documents.
//  PDF editing remains in PDFAnnotationView.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit
import PDFKit

// UUID needs Identifiable for fullScreenCover(item:)
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

struct SavedLocalDocument: Codable {
    let id: UUID
    let title: String
    let localPath: String
    var createdAt: Date?
    var updatedAt: Date?
}

struct SavedLocalFolder: Codable {
    let id: UUID
    var name: String
    var createdAt: Date
    var colorHex: Int?
    var iconSystemName: String?
}

struct LocalFolder: Identifiable {
    let id: UUID
    var name: String
    var createdAt: Date
    var colorHex: Int?
    var iconSystemName: String?
}

struct SharePayload: Identifiable {
    let id = UUID()
    let urls: [URL]
}

private struct LibraryBackupSnapshot: Codable {
    struct Item: Codable {
        let id: UUID
        let title: String
        let createdAt: Date
        let updatedAt: Date
        let relativePDFPath: String?
        let folderId: UUID?
    }

    let createdAt: Date
    let source: String
    let folders: [SavedLocalFolder]
    let items: [Item]
}

private enum LibrarySection: String, CaseIterable, Identifiable {
    case documents
    case favorites
    case shared
    case marketplace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .documents: return "Documents"
        case .favorites: return "Favorites"
        case .shared: return "Shared"
        case .marketplace: return "Marketplace"
        }
    }

    var icon: String {
        switch self {
        case .documents: return "folder"
        case .favorites: return "bookmark"
        case .shared: return "person.2"
        case .marketplace: return "storefront"
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
    @State private var showAccountMenu = false
    @State private var showAccountSheet = false
    @State private var showCreateFolderAlert = false
    @State private var newFolderName = ""

    @State private var showCloudSettingsModal = false
    @State private var showSettingsModal = false
    @State private var showSearchOverlay = false
    @State private var searchText = ""
    @State private var activeFolderOptionsID: UUID?

    @State private var selectedDocumentForOptions: LocalDocument?
    @State private var moveDocumentId: UUID?
    @State private var editorDocumentId: UUID?
    @State private var sharePayload: SharePayload?

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
    @State private var isICloudAvailable = false
    @State private var lastCloudSyncDate = Date()
    @State private var lastBackupDate = Date().addingTimeInterval(-20 * 60)

    private let repository = DocumentRepository()

    private let localPDFsDefaultsKey = "lectra_local_pdfs"
    private let localFoldersDefaultsKey = "lectra_local_folders"
    private let documentFolderMapDefaultsKey = "lectra_document_folder_map"
    private let titleOverridesDefaultsKey = "lectra_document_title_overrides"
    private let recentDocumentsDefaultsKey = "lectra_recently_opened_documents"
    private let cloudSyncEnabledDefaultsKey = "lectra_cloud_sync_enabled"
    private let autoBackupEnabledDefaultsKey = "lectra_auto_backup_enabled"
    private let lastCloudSyncDefaultsKey = "lectra_last_cloud_sync"
    private let lastBackupDefaultsKey = "lectra_last_backup"

    private var sidebarWidth: CGFloat {
        isSidebarCollapsed ? 86 : 292
    }

    private var currentFolder: LocalFolder? {
        guard let currentFolderId else { return nil }
        return folders.first(where: { $0.id == currentFolderId })
    }

    private var documentsInScope: [LocalDocument] {
        documents.filter { folderId(for: $0) == currentFolderId }
    }

    private var filteredFolders: [LocalFolder] {
        guard currentFolderId == nil else { return [] }
        guard activeSection == .documents else { return [] }
        guard documentFilter != .documents else { return [] }

        switch sortMode {
        case .name, .type:
            return folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .dateCreated, .lastModified:
            return folders.sorted { $0.createdAt > $1.createdAt }
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

    private var libraryCardWidth: CGFloat {
        currentFolderId == nil ? 220 : 202
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: libraryCardWidth, maximum: libraryCardWidth), spacing: 26, alignment: .top)]
    }

    private var searchResults: [LocalDocument] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return recentlyOpenedDocuments
        }
        return filteredDocuments.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    private var recentlyOpenedDocuments: [LocalDocument] {
        recentlyOpenedDocumentIds.compactMap { id in
            documents.first(where: { $0.id == id })
        }
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                sidebar
                    .frame(width: sidebarWidth)

                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 1)

                mainPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color.black)
            }
            .background(Color.black.ignoresSafeArea())

            if showSettingsModal {
                modalBackdrop {
                    showSettingsModal = false
                }

                AppSettingsModalView {
                    showSettingsModal = false
                }
            }

            if showCloudSettingsModal {
                modalBackdrop {
                    showCloudSettingsModal = false
                }

                CloudBackupSettingsModalView(
                    isCloudSyncEnabled: isCloudSyncEnabled,
                    isAutoBackupEnabled: isAutoBackupEnabled,
                    onSetCloudSyncEnabled: { isEnabled in
                        setCloudSyncEnabled(isEnabled)
                    },
                    onSetAutoBackupEnabled: { isEnabled in
                        setAutoBackupEnabled(isEnabled)
                    },
                    onManualBackup: {
                        Task {
                            await runManualBackup()
                        }
                    },
                    onClose: {
                    showCloudSettingsModal = false
                    }
                )
            }

            if let message = backgroundSyncToast {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(LectraColor.success.opacity(0.92))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .padding(.bottom, 26)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPickerView(contentTypes: filePickerContentTypes) { url in
                importPickedFile(from: url, folderId: currentFolderId)
            }
        }
        .sheet(isPresented: $showAccountSheet) {
            AccountSheetView()
                .environmentObject(authManager)
        }
        .sheet(item: $selectedDocumentForOptions) { doc in
            DocumentOptionsSheetView(
                documentTitle: doc.title,
                onDuplicate: {
                    duplicateDocument(doc)
                },
                onMove: {
                    moveDocumentId = doc.id
                },
                onExport: {
                    exportDocument(doc)
                },
                onDelete: {
                    removeDocument(doc)
                }
            )
        }
        .sheet(item: $moveDocumentId) { docId in
            if let doc = document(for: docId) {
                MoveDocumentSheetView(
                    documentTitle: doc.title,
                    folders: folders,
                    currentFolderId: folderId(for: doc),
                    onMove: { targetFolderId in
                        moveDocument(documentId: doc.id, to: targetFolderId)
                    }
                )
            }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheetView(items: payload.urls)
        }
        .alert("Create Folder", isPresented: $showCreateFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
            Button("Create") {
                createFolder(named: newFolderName)
                newFolderName = ""
            }
        } message: {
            Text("Add a new folder.")
        }
        .alert(
            "Not Available Yet",
            isPresented: .init(
                get: { featureNotice != nil },
                set: { isPresented in
                    if !isPresented {
                        featureNotice = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                featureNotice = nil
            }
        } message: {
            Text(featureNotice ?? "")
        }
        .fullScreenCover(item: $editorDocumentId) { docId in
            if let doc = document(for: docId) {
                PDFAnnotationView(
                    document: doc,
                    repository: repository,
                    onRename: { newTitle in
                        persistTitleRename(for: doc, newTitle: newTitle)
                    }
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lectraBackgroundSyncCompleted)) { _ in
            guard activeSection == .documents else { return }
            if editorDocumentId == nil {
                showBackgroundSyncToast("Sync complete ✓")
            } else {
                hasPendingBackgroundSyncToast = true
            }
        }
        .onChange(of: editorDocumentId) { _, newValue in
            if newValue == nil, hasPendingBackgroundSyncToast {
                hasPendingBackgroundSyncToast = false
                showBackgroundSyncToast("Sync complete ✓")
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            loadRecentDocuments()
            loadCloudPreferences()
            await loadDocuments()
            if isCloudSyncEnabled {
                await runCloudSync(triggeredByUser: false)
            }
        }
        .onDisappear {
            backgroundSyncToastTask?.cancel()
        }
        .preferredColorScheme(.dark)
    }

    private func showBackgroundSyncToast(_ message: String) {
        backgroundSyncToastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            backgroundSyncToast = message
        }

        backgroundSyncToastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_300_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                backgroundSyncToast = nil
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: isSidebarCollapsed ? 12 : 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isSidebarCollapsed.toggle()
                }
            } label: {
                Image(systemName: isSidebarCollapsed ? "sidebar.right" : "sidebar.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: 0xE84D4D))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            if !isSidebarCollapsed {
                Text("Lectra")
                    .font(.system(size: 34, weight: .semibold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .foregroundStyle(Color.white.opacity(0.95))
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            }

            ForEach(LibrarySection.allCases) { section in
                sidebarRow(for: section)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, isSidebarCollapsed ? 10 : 16)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x1C1618), Color(hex: 0x131417), Color(hex: 0x1A1114)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    @ViewBuilder
    private func sidebarRow(for section: LibrarySection) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectSection(section)
            }
        } label: {
            VStack(alignment: .leading, spacing: isSidebarCollapsed ? 0 : 2) {
                HStack(spacing: isSidebarCollapsed ? 0 : 12) {
                    Image(systemName: section.icon)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 28)

                    if !isSidebarCollapsed {
                        Text(section.title)
                            .font(.system(size: 18, weight: .regular))
                            .lineLimit(1)
                    }

                    if !isSidebarCollapsed {
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: isSidebarCollapsed ? .center : .leading)

                if section == .marketplace && !isSidebarCollapsed {
                    Text("500+ Items for Essential")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.72))
                        .padding(.leading, 40)
                }
            }
            .foregroundColor(Color.white.opacity(0.95))
            .padding(.horizontal, isSidebarCollapsed ? 0 : 10)
            .padding(.vertical, isSidebarCollapsed ? 8 : 10)
            .frame(maxWidth: .infinity, alignment: isSidebarCollapsed ? .center : .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(activeSection == section ? Color(hex: 0x4A222A) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: isSidebarCollapsed ? .center : .leading)
    }

    @ViewBuilder
    private var mainPane: some View {
        switch activeSection {
        case .documents:
            documentsPane
        case .favorites:
            favoritesPane
        case .shared:
            sharedPane
        case .marketplace:
            marketplacePane
        }
    }

    private var documentsPane: some View {
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

            if showSearchOverlay {
                searchOverlay
                    .transition(.opacity)
            }
        }
    }

    private var documentsTopBar: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                HStack(spacing: 14) {
                    if currentFolderId != nil {
                        Button {
                            returnToVaultRoot()
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Documents")
                                    .font(.system(size: 16, weight: .regular))
                            }
                            .foregroundColor(Color(hex: 0xE84D4D))
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Documents")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.96))
                    }

                    Spacer(minLength: 0)

                    utilityButtons(showSearch: true)
                }

                if let folderName = currentFolder?.name {
                    Text(folderName)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .lineLimit(1)
                }
            }

            HStack(spacing: 12) {
                filterMenu

                Spacer(minLength: 0)

                newButton
                viewModeButton
                cloudButton
            }
        }
    }

    private var favoritesPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            genericTopBar(title: "Favorites", filterTitle: "All", includeSearch: false)
                .padding(.horizontal, 18)
                .padding(.top, 10)

            Spacer()
            GenericEmptyStateView(
                symbol: "folder.badge.star",
                title: "Find things quicker with Favorites",
                subtitle: "Simply tap star to add documents or bookmark a page."
            )
            .frame(maxWidth: .infinity)
            Spacer()
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

    private var marketplacePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Marketplace")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.96))

                GoodnotesSearchBar(text: .constant(""), placeholder: "Search for a product, creator, brand, character", isEditable: false)

                HStack(spacing: 22) {
                    ForEach(["Home", "Creators", "Brand Collab", "Work", "Study", "Life"], id: \.self) { tab in
                        Text(tab)
                            .font(.system(size: 16, weight: tab == "Home" ? .semibold : .regular))
                            .foregroundColor(tab == "Home" ? Color(hex: 0xE84D4D) : Color.white.opacity(0.72))
                            .overlay(alignment: .bottom) {
                                if tab == "Home" {
                                    Rectangle()
                                        .fill(Color(hex: 0xE84D4D))
                                        .frame(height: 2)
                                        .offset(y: 8)
                                }
                            }
                    }

                    Spacer(minLength: 0)

                    Text("Saved")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(hex: 0xE84D4D))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(hex: 0x33171D))
                        .clipShape(Capsule())
                }

                Text("Featured Items")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)

                HStack(spacing: 30) {
                    MarketplaceFeatureIcon(symbol: "gift.fill", title: "Subscriber\nSpecials", tint: Color(hex: 0xC76A6A))
                    MarketplaceFeatureIcon(symbol: "lungs.fill", title: "Anatomy", tint: Color(hex: 0xE7D78E))
                    MarketplaceFeatureIcon(symbol: "checklist", title: "To-do List", tint: Color(hex: 0xD7A2A2))
                    MarketplaceFeatureIcon(symbol: "signature", title: "Lectra\nOriginals", tint: Color(hex: 0xD89595))
                }

                MarketplaceHeroBanner()

                Text("Happy International Women's Day!")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)

                ScrollView(.horizontal) {
                    HStack(spacing: 16) {
                        ForEach(marketplaceCards) { card in
                            MarketplaceProductCard(item: card)
                                .frame(width: 300)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }

    private func genericTopBar(title: String, filterTitle: String, includeSearch: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Text(title)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.96))

                Spacer(minLength: 0)

                utilityButtons(showSearch: includeSearch)
            }

            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 14, weight: .bold))
                    Text(filterTitle)
                        .font(.system(size: 16, weight: .regular))
                }
                .foregroundColor(Color(hex: 0xE84D4D))

                Spacer(minLength: 0)

                viewModeButton
                cloudButton
            }
        }
    }

    private var documentsGridView: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 34) {
                ForEach(filteredFolders) { folder in
                    folderGridCard(for: folder)
                }

                ForEach(filteredDocuments) { doc in
                    documentGridCard(for: doc)
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
                        openFolder(folder)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(hex: 0xD97A7A))
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(folder.name)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white)
                                Text(folder.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(Color.white.opacity(0.55))
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.4))
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 58)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        GoodnotesFolderCardView(
            folderName: folder.name,
            subtitle: folder.createdAt.formatted(date: .abbreviated, time: .shortened),
            accent: folderAccentColor(for: folder),
            iconSystemName: folder.iconSystemName,
            isOptionsVisible: activeFolderOptionsID == folder.id,
            onOpen: {
                openFolder(folder)
            },
            onOptionsTap: {
                if activeFolderOptionsID == folder.id {
                    activeFolderOptionsID = nil
                } else {
                    activeFolderOptionsID = folder.id
                }
            }
        )
        .frame(width: libraryCardWidth, alignment: .leading)
        .popover(
            isPresented: Binding(
                get: { activeFolderOptionsID == folder.id },
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
            handleDrop(items: items, into: folder.id)
        }
    }

    @ViewBuilder
    private func documentGridCard(for doc: LocalDocument) -> some View {
        DocumentCardView(
            document: doc,
            subtitle: formattedDocumentDate(for: doc),
            onOptionsTap: {
                selectedDocumentForOptions = doc
            }
        )
        .frame(width: libraryCardWidth, alignment: .leading)
        .onTapGesture {
            handleDocumentTap(doc)
        }
        .draggable(doc.id.uuidString)
    }

    private func documentListRow(for doc: LocalDocument) -> some View {
        Button {
            handleDocumentTap(doc)
        } label: {
            HStack(spacing: 12) {
                MiniDocumentPreview(document: doc)
                    .frame(width: 48, height: 64)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(doc.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Button {
                            selectedDocumentForOptions = doc
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(Color(hex: 0xE84D4D))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                    }

                    Text(formattedDocumentDate(for: doc))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.55))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 72)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func utilityButtons(showSearch: Bool) -> some View {
        HStack(spacing: 16) {
            if showSearch {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showSearchOverlay = true
                        searchText = ""
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(hex: 0xE84D4D))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            }

            Button {
                featureNotice = "Notifications panel is coming soon."
            } label: {
                Image(systemName: "bell")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(hex: 0xE84D4D))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            Button {
                showAccountMenu = true
            } label: {
                ProfileAvatarView(
                    avatarURL: authManager.avatarURL,
                    fallbackName: authManager.userName ?? authManager.userEmail,
                    size: 18
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAccountMenu, arrowEdge: .top) {
                AccountMenuPopoverView(
                    userName: authManager.userName ?? "User",
                    onViewAccount: {
                        showAccountMenu = false
                        showAccountSheet = true
                    },
                    onSettings: {
                        showAccountMenu = false
                        showSettingsModal = true
                    },
                    onCloudBackup: {
                        showAccountMenu = false
                        showCloudSettingsModal = true
                    },
                    onSignOut: {
                        showAccountMenu = false
                        Task { @MainActor in
                            await authManager.signOut()
                        }
                    }
                )
                .presentationCompactAdaptation(.popover)
            }
        }
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
                    .font(.system(size: 16, weight: .regular))
            }
            .foregroundColor(Color(hex: 0xE84D4D))
            .frame(minHeight: 44)
        }
    }

    private var filterTitle: String {
        if currentFolderId != nil {
            return "All"
        }
        return documentFilter.title
    }

    private var newButton: some View {
        Button {
            showCreateMenu = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                Text("New")
                    .font(.system(size: 17, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background(Color(hex: 0xD94141))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
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
                onQuickRecord: {
                    showCreateMenu = false
                    createBlankLocalDocument(title: "Quick Record")
                },
                onQuickNote: {
                    showCreateMenu = false
                    createBlankLocalDocument(title: "QuickNote")
                },
                onScanDocuments: {
                    showCreateMenu = false
                    filePickerContentTypes = [.pdf, .image]
                    showFilePicker = true
                },
                onStudySet: {
                    showCreateMenu = false
                    createFolder(named: "Study Set")
                },
                onImage: {
                    showCreateMenu = false
                    filePickerContentTypes = [.image]
                    showFilePicker = true
                },
                onTakePhoto: {
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
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(hex: 0xE84D4D))
                .frame(width: 44, height: 44)
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
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(hex: 0xE84D4D))
                .frame(width: 44, height: 44)
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
                    showCloudSettingsModal = true
                }
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(Color(hex: 0xE84D4D))
            Text("Loading documents")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.white.opacity(0.65))
        }
    }

    private var emptyDocumentsView: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder")
                .font(.system(size: 32, weight: .thin))
                .foregroundColor(Color.white.opacity(0.75))
            Text("No items yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Text("Tap New to create a notebook or import a document.")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color.white.opacity(0.65))
        }
    }

    private var searchOverlay: some View {
        ZStack {
            Color.black.opacity(0.98)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showSearchOverlay = false
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text(currentFolder?.name ?? "Documents")
                                .font(.system(size: 16, weight: .regular))
                        }
                        .foregroundColor(Color(hex: 0xE84D4D))
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }

                GoodnotesSearchBar(text: $searchText, placeholder: "Search", isEditable: true)

                HStack {
                    Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Recently Opened Documents" : "Search Results")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer(minLength: 0)

                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       !recentlyOpenedDocuments.isEmpty {
                        Button("Clear") {
                            clearRecentDocuments()
                        }
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(Color(hex: 0xE84D4D))
                    }
                }

                if searchResults.isEmpty {
                    Spacer(minLength: 0)
                    Text("No documents found")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.65))
                    Spacer(minLength: 0)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 14) {
                            ForEach(searchResults) { doc in
                                Button {
                                    showSearchOverlay = false
                                    handleDocumentTap(doc)
                                } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        MiniDocumentPreview(document: doc)
                                            .frame(width: 148, height: 192)
                                        Text(doc.title)
                                            .font(.system(size: 14, weight: .regular))
                                            .foregroundColor(.white)
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

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func modalBackdrop(onDismiss: @escaping () -> Void) -> some View {
        Color.black.opacity(0.62)
            .ignoresSafeArea()
            .onTapGesture(perform: onDismiss)
    }

    private func selectSection(_ section: LibrarySection) {
        activeSection = section
        showSearchOverlay = false

        if section != .documents {
            currentFolderId = nil
        }
    }

    private func openFolder(_ folder: LocalFolder) {
        withAnimation(.easeInOut(duration: 0.18)) {
            currentFolderId = folder.id
            documentFilter = .all
        }
    }

    private func returnToVaultRoot() {
        withAnimation(.easeInOut(duration: 0.18)) {
            currentFolderId = nil
        }
    }

    private func document(for id: UUID) -> LocalDocument? {
        documents.first(where: { $0.id == id })
    }

    private func folderId(for document: LocalDocument) -> UUID? {
        guard let stored = documentFolderMap[document.id.uuidString] else { return nil }
        return UUID(uuidString: stored)
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

        let index = abs(folder.id.uuidString.hashValue) % palette.count
        return palette[index]
    }

    private func formattedDocumentDate(for document: LocalDocument) -> String {
        document.updatedAt.formatted(date: .abbreviated, time: .shortened)
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

    private func clearRecentDocuments() {
        recentlyOpenedDocumentIds = []
        saveRecentDocuments()
    }

    private func loadCloudPreferences() {
        let defaults = UserDefaults.standard
        isICloudAvailable = FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil
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
        await MainActor.run {
            isICloudAvailable = FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil
        }

        if !isCloudSyncEnabled {
            if triggeredByUser {
                await MainActor.run {
                    featureNotice = "Enable Cloud Sync in Cloud & Backup Settings first."
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

        await MainActor.run {
            lastCloudSyncDate = Date()
            UserDefaults.standard.set(lastCloudSyncDate, forKey: lastCloudSyncDefaultsKey)
        }

        guard isAutoBackupEnabled || triggeredByUser else { return }

        do {
            let backupTarget = try createLibraryBackupSnapshot()
            await MainActor.run {
                lastBackupDate = Date()
                UserDefaults.standard.set(lastBackupDate, forKey: lastBackupDefaultsKey)
                if triggeredByUser {
                    featureNotice = "Sync complete. Backup saved to \(backupTarget)."
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
            let backupTarget = try createLibraryBackupSnapshot()
            await MainActor.run {
                lastBackupDate = Date()
                UserDefaults.standard.set(lastBackupDate, forKey: lastBackupDefaultsKey)
                featureNotice = "Backup saved to \(backupTarget)."
            }
        } catch {
            await MainActor.run {
                featureNotice = "Manual backup failed: \(error.localizedDescription)"
            }
        }
    }

    private func createLibraryBackupSnapshot() throws -> String {
        let fileManager = FileManager.default
        let backupRoot = backupRootURL()
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let snapshotFolder = backupRoot.appendingPathComponent("snapshot-\(timestamp)", isDirectory: true)
        try fileManager.createDirectory(at: snapshotFolder, withIntermediateDirectories: true)

        var snapshotItems: [LibraryBackupSnapshot.Item] = []
        snapshotItems.reserveCapacity(documents.count)

        for doc in documents {
            var relativePDFPath: String?

            if let localURL = doc.localPDFURL,
               fileManager.fileExists(atPath: localURL.path) {
                let docBackupFolder = snapshotFolder.appendingPathComponent(doc.id.uuidString, isDirectory: true)
                try fileManager.createDirectory(at: docBackupFolder, withIntermediateDirectories: true)

                let destination = docBackupFolder.appendingPathComponent("document.pdf")
                try? fileManager.removeItem(at: destination)
                try fileManager.copyItem(at: localURL, to: destination)
                relativePDFPath = "\(doc.id.uuidString)/document.pdf"
            }

            snapshotItems.append(
                .init(
                    id: doc.id,
                    title: doc.title,
                    createdAt: doc.createdAt,
                    updatedAt: doc.updatedAt,
                    relativePDFPath: relativePDFPath,
                    folderId: folderId(for: doc)
                )
            )
        }

        let snapshot = LibraryBackupSnapshot(
            createdAt: Date(),
            source: backupRoot.path.contains("/Mobile Documents/") ? "iCloud Drive" : "On Device",
            folders: folders.map {
                SavedLocalFolder(
                    id: $0.id,
                    name: $0.name,
                    createdAt: $0.createdAt,
                    colorHex: $0.colorHex,
                    iconSystemName: $0.iconSystemName
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

    private func backupRootURL() -> URL {
        let fileManager = FileManager.default
        if isCloudSyncEnabled,
           let ubiquitousRoot = fileManager.url(forUbiquityContainerIdentifier: nil) {
            let iCloudBackupRoot = ubiquitousRoot
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("LectraBackups", isDirectory: true)
            return iCloudBackupRoot
        }

        return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LectraBackups", isDirectory: true)
    }

    private func handleDrop(items: [String], into folderId: UUID) -> Bool {
        let documentIDs = items.compactMap(UUID.init(uuidString:))
        guard !documentIDs.isEmpty else { return false }

        withAnimation(.easeInOut(duration: 0.18)) {
            for documentId in documentIDs {
                moveDocument(documentId: documentId, to: folderId, shouldAnimate: false)
            }
        }
        return true
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
        pruneFolderMappingForCurrentData()

        if let currentFolderId,
           !folders.contains(where: { $0.id == currentFolderId }) {
            self.currentFolderId = nil
        }

        isLoading = false

        await refreshRemoteDocuments()
    }

    private func refreshRemoteDocuments() async {
        do {
            let items = try await repository.fetchDocuments()
            let fetched = items.map { LocalDocument(from: $0) }
            let currentLocalDocs = documents.filter { $0.status == .local }
            let merged = mergeDocuments(fetched: fetched, local: currentLocalDocs)

            await MainActor.run {
                documents = merged
                applyTitleOverrides()

                for doc in documents where doc.status != .local {
                    if repository.isPDFCachedLocally(documentId: doc.id) {
                        doc.localPDFURL = repository.localPDFURL(for: doc.id)
                    }
                }

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
            let fileURL = documentsDir.appendingPathComponent(savedItem.localPath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

            let fileAttributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileCreated = fileAttributes?[.creationDate] as? Date
            let fileModified = fileAttributes?[.modificationDate] as? Date

            let createdAt = savedItem.createdAt ?? fileCreated ?? fileModified ?? Date()
            let updatedAt = savedItem.updatedAt ?? fileModified ?? createdAt

            let doc = LocalDocument(
                title: savedItem.title,
                localURL: fileURL,
                id: savedItem.id,
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

    // MARK: - Document Tap

    private func handleDocumentTap(_ doc: LocalDocument) {
        guard doc.localPDFURL != nil else {
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
                    }

                    try? await Task.sleep(nanoseconds: 80_000_000)
                    await MainActor.run {
                        markDocumentAsRecentlyOpened(doc.id)
                        editorDocumentId = doc.id
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

        markDocumentAsRecentlyOpened(doc.id)
        editorDocumentId = doc.id
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

    private func importLocalPDF(from url: URL, folderId: UUID? = nil) {
        let title = url.deletingPathExtension().lastPathComponent
        let doc = LocalDocument(title: title, localURL: url)

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
                folderId: folderId,
                createdAt: doc.createdAt,
                updatedAt: doc.updatedAt
            )

            documents = [doc] + documents

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000)
                markDocumentAsRecentlyOpened(doc.id)
                editorDocumentId = doc.id
            }
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

            let relativePath = "pdfs/\(doc.id.uuidString)/original.pdf"
            storeLocalDocumentMetadata(
                docId: doc.id,
                title: title,
                relativePath: relativePath,
                folderId: folderId,
                createdAt: doc.createdAt,
                updatedAt: doc.updatedAt
            )

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000)
                markDocumentAsRecentlyOpened(doc.id)
                editorDocumentId = doc.id
            }
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

            let relativePath = "pdfs/\(doc.id.uuidString)/original.pdf"
            storeLocalDocumentMetadata(
                docId: doc.id,
                title: title,
                relativePath: relativePath,
                folderId: currentFolderId,
                createdAt: doc.createdAt,
                updatedAt: doc.updatedAt
            )

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000)
                markDocumentAsRecentlyOpened(doc.id)
                editorDocumentId = doc.id
            }
        } catch {
            featureNotice = "Could not create a new file: \(error.localizedDescription)"
        }
    }

    private func createFolder(named: String) {
        let trimmed = named.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let folder = LocalFolder(
            id: UUID(),
            name: trimmed,
            createdAt: Date(),
            colorHex: nil,
            iconSystemName: nil
        )
        folders = [folder] + folders
        saveFolders()
    }

    private func loadSavedFolders() {
        guard let data = UserDefaults.standard.data(forKey: localFoldersDefaultsKey),
              let saved = try? JSONDecoder().decode([SavedLocalFolder].self, from: data) else {
            folders = []
            return
        }

        folders = saved
            .map {
                LocalFolder(
                    id: $0.id,
                    name: $0.name,
                    createdAt: $0.createdAt,
                    colorHex: $0.colorHex,
                    iconSystemName: $0.iconSystemName
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func saveFolders() {
        let saved = folders.map {
            SavedLocalFolder(
                id: $0.id,
                name: $0.name,
                createdAt: $0.createdAt,
                colorHex: $0.colorHex,
                iconSystemName: $0.iconSystemName
            )
        }
        if let encoded = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(encoded, forKey: localFoldersDefaultsKey)
        }
    }

    private func renameFolder(folderId: UUID, to proposedName: String) {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let idx = folders.firstIndex(where: { $0.id == folderId }) else { return }
        guard folders[idx].name != trimmed else { return }
        folders[idx].name = trimmed
        saveFolders()
    }

    private func updateFolderColor(folderId: UUID, colorHex: Int) {
        guard let idx = folders.firstIndex(where: { $0.id == folderId }) else { return }
        folders[idx].colorHex = colorHex
        folders[idx].createdAt = Date()
        saveFolders()
    }

    private func updateFolderIcon(folderId: UUID, iconSystemName: String) {
        guard let idx = folders.firstIndex(where: { $0.id == folderId }) else { return }
        folders[idx].iconSystemName = iconSystemName
        saveFolders()
    }

    private func moveFolderToTop(folderId: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderId }) else { return }
        folders[idx].createdAt = Date()
        folders.sort { $0.createdAt > $1.createdAt }
        saveFolders()
    }

    private func deleteFolder(folderId: UUID) {
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

    private func storeLocalDocumentMetadata(
        docId: UUID,
        title: String,
        relativePath: String,
        folderId: UUID?,
        createdAt: Date,
        updatedAt: Date
    ) {
        var existingSaved: [SavedLocalDocument] = []
        if let data = UserDefaults.standard.data(forKey: localPDFsDefaultsKey),
           let saved = try? JSONDecoder().decode([SavedLocalDocument].self, from: data) {
            existingSaved = saved
        }

        let updated = SavedLocalDocument(
            id: docId,
            title: title,
            localPath: relativePath,
            createdAt: createdAt,
            updatedAt: updatedAt
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
        let destination = folderId?.uuidString
        let currentDestination = documentFolderMap[key]
        guard currentDestination != destination else { return }

        if let destination {
            documentFolderMap[key] = destination
        } else {
            documentFolderMap.removeValue(forKey: key)
        }

        saveDocumentFolderMap()
    }

    private func moveDocument(documentId: UUID, to folderId: UUID?) {
        moveDocument(documentId: documentId, to: folderId, shouldAnimate: true)
    }

    private func duplicateDocument(_ doc: LocalDocument) {
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

    private func removeDocument(_ doc: LocalDocument) {
        documents.removeAll(where: { $0.id == doc.id })
        documentFolderMap.removeValue(forKey: doc.id.uuidString)
        saveDocumentFolderMap()

        removeSavedLocalDocument(documentId: doc.id)
        removeTitleOverride(documentId: doc.id)

        let localFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pdfs", isDirectory: true)
            .appendingPathComponent(doc.id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: localFolder)
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
            createdAt: saved[index].createdAt,
            updatedAt: updatedAt
        )

        if let encoded = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(encoded, forKey: localPDFsDefaultsKey)
        }
    }
}

private struct GoodnotesFolderCardView: View {
    let folderName: String
    let subtitle: String
    let accent: Color
    let iconSystemName: String?
    let isOptionsVisible: Bool
    let onOpen: () -> Void
    let onOptionsTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(accent)
                    .frame(height: 128)
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(accent.opacity(0.9))
                            .frame(width: 62, height: 16)
                            .offset(x: 12, y: -7)
                    }
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .overlay {
                        if let iconSystemName {
                            Image(systemName: iconSystemName)
                                .font(.system(size: 26, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.58))
                        }
                    }

                Image(systemName: "star")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.8))
                    .padding(10)
            }
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .onTapGesture(perform: onOpen)

            HStack(spacing: 4) {
                Text(folderName)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .onTapGesture(perform: onOpen)

                Button(action: onOptionsTap) {
                    Image(systemName: isOptionsVisible ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: 0xE84D4D))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }

            Text(subtitle)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Color.white.opacity(0.58))
        }
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
                TextField("Folder name", text: $draftName)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

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
                                        .foregroundColor(.white)
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
                                    .fill(Color.white.opacity(icon == selectedIcon ? 0.2 : 0.08))
                                    .frame(width: 38, height: 34)
                                Image(systemName: icon)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 0) {
                FolderMenuActionRow(title: "Move", icon: "arrow.right.square", action: onMove)
                FolderMenuActionRow(title: "Open in New Window", icon: "menubar.dock.rectangle", action: onOpenInWindow)
                FolderMenuActionRow(title: "Export", icon: "square.and.arrow.up", action: onExport)
                FolderMenuActionRow(title: "Move to Trash", icon: "trash", isDestructive: true, showDivider: false, action: onMoveToTrash)
            }
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(12)
        .frame(width: 320)
        .background(Color(hex: 0x1F2024, opacity: 0.97))
        .onAppear {
            draftName = folderName
        }
        .onChange(of: folderName) { _, newValue in
            draftName = newValue
        }
        .onSubmit {
            onRename(draftName)
        }
        .onDisappear {
            onRename(draftName)
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
            .foregroundColor(isDestructive ? Color(hex: 0xE84D4D) : .white)
            .padding(.horizontal, 12)
            .frame(height: 44)
        }
        .buttonStyle(.plain)

        if showDivider {
            Divider()
                .background(Color.white.opacity(0.12))
                .padding(.leading, 12)
        }
    }
}

private struct MiniDocumentPreview: View {
    @ObservedObject var document: LocalDocument

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white)
            .overlay(
                Group {
                    if let url = document.localPDFURL,
                       let pdfDoc = PDFDocument(url: url),
                       let page = pdfDoc.page(at: 0) {
                        PDFThumbnailRepresentable(page: page)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        VStack(spacing: 3) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Color.gray.opacity(0.7))
                            Text("PDF")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color.gray.opacity(0.7))
                        }
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct GoodnotesSearchBar: View {
    @Binding var text: String
    let placeholder: String
    let isEditable: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Color.white.opacity(0.48))

            if isEditable {
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white)
            } else {
                Text(placeholder)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.48))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(Color(hex: 0x171A22))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                    .fill(Color(hex: 0x321A33).opacity(0.65))
                    .frame(width: 146, height: 146)

                Image(systemName: symbol)
                    .font(.system(size: 32, weight: .regular))
                    .foregroundColor(Color(hex: 0xE3D58E))
            }

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            Text(subtitle)
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(Color.white.opacity(0.6))
        }
    }
}

private struct CreateMenuPopoverView: View {
    let onNotebook: () -> Void
    let onTextDoc: () -> Void
    let onWhiteboard: () -> Void
    let onImport: () -> Void
    let onFolder: () -> Void
    let onQuickRecord: () -> Void
    let onQuickNote: () -> Void
    let onScanDocuments: () -> Void
    let onStudySet: () -> Void
    let onImage: () -> Void
    let onTakePhoto: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)

            VStack(spacing: 0) {
                PopoverActionRow(title: "Notebook", icon: "book.closed", action: onNotebook)
                PopoverActionRow(title: "Text Doc", icon: "doc.text", action: onTextDoc)
                PopoverActionRow(title: "Whiteboard", icon: "square.grid.3x3", action: onWhiteboard)
                PopoverActionRow(title: "Folder", icon: "folder", showDivider: false, action: onFolder)
            }
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Import")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.white.opacity(0.58))

            VStack(spacing: 0) {
                PopoverActionRow(title: "Import PDF", icon: "square.and.arrow.down", action: onImport)
                PopoverActionRow(title: "Scan Documents", icon: "doc.viewfinder", action: onScanDocuments)
                PopoverActionRow(title: "Image", icon: "photo", action: onImage)
                PopoverActionRow(title: "Take Photo", icon: "camera", showDivider: false, action: onTakePhoto)
            }
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Quick Actions")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.white.opacity(0.58))

            VStack(spacing: 0) {
                PopoverActionRow(title: "QuickNote", icon: "square.and.pencil", action: onQuickNote)
                PopoverActionRow(title: "Quick Record", icon: "mic.badge.plus", action: onQuickRecord)
                PopoverActionRow(title: "Study Set", icon: "rectangle.stack.badge.play", showDivider: false, action: onStudySet)
            }
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(14)
        .frame(width: 322)
        .background(Color(hex: 0x1E1F23, opacity: 0.97))
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
                .foregroundColor(Color.white.opacity(0.58))

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
                .foregroundColor(Color.white.opacity(0.58))

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
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(14)
        .frame(width: 286)
        .background(Color(hex: 0x1E1F23, opacity: 0.97))
    }

    private func layoutPill(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : Color.white.opacity(0.72))
            .padding(.horizontal, 12)
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color(hex: 0xE84D4D) : Color.white.opacity(0.08))
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
                .foregroundColor(.white)

            HStack(spacing: 8) {
                Image(systemName: isCloudSyncEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isCloudSyncEnabled ? Color(hex: 0x35B77A) : Color(hex: 0xC45454))
                Text(
                    isCloudSyncEnabled
                    ? (isICloudAvailable ? "Enabled (iCloud available)" : "Enabled (local fallback)")
                    : "Disabled"
                )
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Last sync: \(lastSyncDate.formatted(date: .omitted, time: .shortened))")
                Text("Last backup: \(lastBackupDate.formatted(date: .omitted, time: .shortened))")
            }
            .font(.system(size: 12, weight: .regular))
            .foregroundColor(Color.white.opacity(0.62))

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
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 320)
        .background(Color(hex: 0x1E1F23, opacity: 0.97))
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
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(isDisabled ? Color.white.opacity(0.06) : Color(hex: 0xE84D4D))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct AccountMenuPopoverView: View {
    let userName: String
    let onViewAccount: () -> Void
    let onSettings: () -> Void
    let onCloudBackup: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: 0xA88F63))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(initials)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(userName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Special Edition")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color(hex: 0xDDA5A5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: 0x3A252A))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)

                Button("View Account", action: onViewAccount)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.7))
            }
            .padding(10)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(spacing: 0) {
                PopoverActionRow(title: "Settings", icon: "slider.horizontal.3", action: onSettings)
                PopoverActionRow(title: "Cloud & Backup", icon: "icloud", action: onCloudBackup)
                PopoverActionRow(
                    title: "Sign Out",
                    icon: "rectangle.portrait.and.arrow.right",
                    showDivider: false,
                    isDestructive: true,
                    action: onSignOut
                )
            }
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(12)
        .frame(width: 320)
        .background(Color(hex: 0x1F2024, opacity: 0.97))
    }

    private var initials: String {
        let comps = userName.split(separator: " ").prefix(2)
        let letters = comps.compactMap { $0.first }
        guard !letters.isEmpty else { return "NS" }
        return String(letters).uppercased()
    }
}

private struct PopoverActionRow: View {
    let title: String
    let icon: String
    var showDivider: Bool = true
    var isDestructive: Bool = false
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
            .foregroundColor(isDestructive ? Color(hex: 0xE84D4D) : .white)
            .padding(.horizontal, 12)
            .frame(height: 44)
        }
        .buttonStyle(.plain)

        if showDivider {
            Divider()
                .background(Color.white.opacity(0.12))
                .padding(.leading, 12)
        }
    }
}

private struct AppSettingsModalView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Text("Settings")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                Spacer(minLength: 0)
                Button("Done", action: onClose)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Color(hex: 0xE84D4D))
            }
            .padding(.horizontal, 14)
            .frame(height: 62)

            Divider().background(Color.white.opacity(0.12))

            VStack(spacing: 16) {
                settingsGroup(["Document Editing", "Document Privacy", "Stylus & Palm Rejection"])
                settingsGroup(["Document Language", "Handwriting Recognition", "Writing Aids"])
                settingsGroup(["Notification Preferences", "Email to Lectra", "Feedback & Surveys", "Troubleshooting"])
            }
            .padding(14)

            Spacer(minLength: 0)
        }
        .frame(width: 520, height: 460)
        .background(Color(hex: 0x1E1F23, opacity: 0.98))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func settingsGroup(_ rows: [String]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.self) { row in
                HStack {
                    Text(row)
                        .font(.system(size: 16, weight: .regular))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundColor(Color.white.opacity(0.35))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .frame(height: 44)

                if row != rows.last {
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.leading, 12)
                }
            }
        }
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CloudBackupSettingsModalView: View {
    let isCloudSyncEnabled: Bool
    let isAutoBackupEnabled: Bool
    let onSetCloudSyncEnabled: (Bool) -> Void
    let onSetAutoBackupEnabled: (Bool) -> Void
    let onManualBackup: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Text("Cloud & Backup")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                Spacer(minLength: 0)
                Button("Done", action: onClose)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Color(hex: 0xE84D4D))
            }
            .padding(.horizontal, 14)
            .frame(height: 62)

            Divider().background(Color.white.opacity(0.12))

            VStack(spacing: 12) {
                cloudToggleRow(
                    title: "Cloud Sync",
                    subtitle: "Explicit opt-in only",
                    isOn: isCloudSyncEnabled,
                    onToggle: onSetCloudSyncEnabled
                )

                Button(action: onManualBackup) {
                    HStack {
                        Text("Manual Backup Documents")
                            .font(.system(size: 16, weight: .regular))
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(Color(hex: 0xE84D4D))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                cloudToggleRow(
                    title: "Automatic Backup",
                    subtitle: "Run backup after successful sync",
                    isOn: isAutoBackupEnabled,
                    onToggle: onSetAutoBackupEnabled
                )
            }
            .padding(14)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(14)

            Text("Cloud sync stays off until you explicitly enable it. Manual backup always keeps a local snapshot and uses iCloud Drive when available.")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Color.white.opacity(0.65))
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .frame(width: 520, height: 360)
        .background(Color(hex: 0x1E1F23, opacity: 0.98))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func cloudToggleRow(
        title: String,
        subtitle: String,
        isOn: Bool,
        onToggle: @escaping (Bool) -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.6))
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { isOn }, set: onToggle))
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }
}

private struct MarketplaceFeatureIcon: View {
    let symbol: String
    let title: String
    let tint: Color

    var body: some View {
        VStack(spacing: 7) {
            Circle()
                .fill(Color.white)
                .frame(width: 94, height: 94)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(tint)
                )

            Text(title)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

private struct MarketplaceHeroBanner: View {
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Happy International Women's Day!")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Text("Celebrate your journey and explore tools designed for your growth")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.9))

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 210, height: 42)
                    .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x5E1F47))

            ZStack {
                Color(hex: 0xE3B8B8)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundColor(Color(hex: 0x8E2C2C))
            }
            .frame(width: 360)
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MarketplaceCardItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let price: String
    let tint: Color
}

private struct MarketplaceProductCard: View {
    let item: MarketplaceCardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(item.tint)
                .frame(height: 170)
                .overlay(
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.white.opacity(0.8))
                )

            Text(item.subtitle)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Color.white.opacity(0.8))
            Text(item.title)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.white)
                .lineLimit(2)
            Text(item.price)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color(hex: 0xE84D4D))
        }
    }
}

private let marketplaceCards: [MarketplaceCardItem] = [
    MarketplaceCardItem(
        title: "Sleep Pattern Tracker",
        subtitle: "Lectra Originals",
        price: "$0.99",
        tint: Color(hex: 0xF0BE9D)
    ),
    MarketplaceCardItem(
        title: "Ethereal Essence Covers",
        subtitle: "Happy Girl Digital Diaries",
        price: "$1.49",
        tint: Color(hex: 0xE39EB2)
    ),
    MarketplaceCardItem(
        title: "Golden Rose Notebook",
        subtitle: "InspErates",
        price: "$6.99",
        tint: Color(hex: 0xF1D3C6)
    ),
    MarketplaceCardItem(
        title: "Believe in Yourself Covers",
        subtitle: "Lectra Community",
        price: "$3.49",
        tint: Color(hex: 0xE7E4AE)
    )
]

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
                        .foregroundColor(.white)
                    Spacer(minLength: 0)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.5))
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
                .background(Color(hex: 0x1A1B1F))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Color.black.ignoresSafeArea())
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
            .foregroundColor(isDestructive ? Color(hex: 0xEA5454) : .white)
            .padding(.horizontal, 14)
            .frame(height: 54)
        }
        .buttonStyle(.plain)

        if !isDestructive {
            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.leading, 14)
        }
    }
}

struct MoveDocumentSheetView: View {
    let documentTitle: String
    let folders: [LocalFolder]
    let currentFolderId: UUID?
    let onMove: (UUID?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onMove(nil)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "tray.full")
                        Text("Documents")
                        Spacer(minLength: 0)
                        if currentFolderId == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .foregroundColor(.white)

                ForEach(folders) { folder in
                    Button {
                        onMove(folder.id)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(Color(hex: 0xD44A4A))
                            Text(folder.name)
                                .foregroundColor(.white)
                            Spacer(minLength: 0)
                            if currentFolderId == folder.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color(hex: 0xE84D4D))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Move \"\(documentTitle)\"")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color(hex: 0xE84D4D))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ProfileAvatarView: View {
    let avatarURL: String?
    let fallbackName: String?
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let avatarURL,
               let url = URL(string: avatarURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        fallbackAvatar
                    @unknown default:
                        fallbackAvatar
                    }
                }
            } else {
                fallbackAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallbackAvatar: some View {
        ZStack {
            Circle().fill(Color(hex: 0xA88F63))
            Text(fallbackInitial)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundColor(.white)
        }
    }

    private var fallbackInitial: String {
        if let initial = fallbackName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .first {
            return String(initial).uppercased()
        }
        return "N"
    }
}

struct AccountSheetView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ProfileAvatarView(
                    avatarURL: authManager.avatarURL,
                    fallbackName: authManager.userName ?? authManager.userEmail,
                    size: 84
                )
                .padding(.top, 24)

                VStack(spacing: 6) {
                    Text(authManager.userName ?? "Google Account")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)
                    Text(authManager.userEmail ?? "Signed in")
                        .font(.subheadline)
                        .foregroundColor(Color.white.opacity(0.62))
                }

                Spacer(minLength: 0)

                Button(role: .destructive) {
                    Task { @MainActor in
                        await authManager.signOut()
                        dismiss()
                    }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.red.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color(hex: 0xE84D4D))
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

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
