//
//  DocumentBrowserView.swift
//  Lectra
//
//  The home screen – a grid of PDF documents fetched from Supabase,
//  plus an option to import PDFs from the Files app for local testing.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

// UUID needs Identifiable for fullScreenCover(item:)
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

struct SavedLocalDocument: Codable {
    let id: UUID
    let title: String
    let localPath: String
}

struct SavedLocalFolder: Codable {
    let id: UUID
    let name: String
    let createdAt: Date
}

struct LocalFolder: Identifiable {
    let id: UUID
    let name: String
    let createdAt: Date
}

struct SharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

struct DocumentBrowserView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var documents: [LocalDocument] = []
    @State private var folders: [LocalFolder] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showFilePicker = false
    @State private var editorDocumentId: UUID?       // drives the fullScreenCover
    @State private var showCreateMenu = false
    @State private var showAccountSheet = false
    @State private var showCreateFolderAlert = false
    @State private var newFolderName = ""
    @State private var featureNotice: String?
    @State private var currentFolderId: UUID?
    @State private var documentFolderMap: [String: String] = [:]
    @State private var selectedDocumentForOptions: LocalDocument?
    @State private var moveDocumentId: UUID?
    @State private var sharePayload: SharePayload?

    private let repository = DocumentRepository()
    private let localPDFsDefaultsKey = "lectra_local_pdfs"
    private let localFoldersDefaultsKey = "lectra_local_folders"
    private let documentFolderMapDefaultsKey = "lectra_document_folder_map"
    private let titleOverridesDefaultsKey = "lectra_document_title_overrides"
    private let createMenuFollowUpDelay: TimeInterval = 0.14
    private let carouselSpacing: CGFloat = 16
    private let minCarouselCardWidth: CGFloat = 240
    private let maxCarouselCardWidth: CGFloat = 420

    /// Helper to find a document by id.
    private func document(for id: UUID) -> LocalDocument? {
        documents.first { $0.id == id }
    }

    private var currentFolder: LocalFolder? {
        guard let currentFolderId else { return nil }
        return folders.first(where: { $0.id == currentFolderId })
    }

    private var visibleFolders: [LocalFolder] {
        currentFolderId == nil ? folders : []
    }

    private var visibleDocuments: [LocalDocument] {
        documents.filter { folderId(for: $0) == currentFolderId }
    }

    private func folderId(for document: LocalDocument) -> UUID? {
        guard let stored = documentFolderMap[document.id.uuidString] else { return nil }
        return UUID(uuidString: stored)
    }

    private func presentCreateMenu() {
        withAnimation(LectraMotion.overlayPresent) {
            showCreateMenu = true
        }
    }

    private func dismissCreateMenu() {
        withAnimation(LectraMotion.overlayDismiss) {
            showCreateMenu = false
        }
    }

    private func dismissCreateMenuThen(_ action: @escaping () -> Void) {
        guard showCreateMenu else {
            action()
            return
        }

        dismissCreateMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + createMenuFollowUpDelay, execute: action)
    }

    private func openFolder(_ folder: LocalFolder) {
        withAnimation(LectraMotion.screenSwap) {
            currentFolderId = folder.id
        }
    }

    private func returnToVaultRoot() {
        withAnimation(LectraMotion.screenSwap) {
            currentFolderId = nil
        }
    }

    private func presentEditor(for documentId: UUID) {
        withAnimation(LectraMotion.screenSwap) {
            editorDocumentId = documentId
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LectraGradient.appBackdrop.ignoresSafeArea()
                vaultAtmosphere

                if isLoading && documents.isEmpty && folders.isEmpty {
                    loadingView
                        .transition(.opacity)
                } else {
                    documentGrid
                        .transition(.opacity.combined(with: .scale(scale: 0.99)))
                }
            }
            .navigationTitle(currentFolder?.name ?? "Lectra Vault")
            .navigationBarTitleDisplayMode(currentFolderId == nil ? .large : .inline)
            .toolbarBackground(Color(hex: 0x0F1728), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if currentFolderId != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            returnToVaultRoot()
                        } label: {
                            Label("Vault", systemImage: "chevron.left")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .frame(height: LectraSizing.minHitTarget)
                                .background(Color.white.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAccountSheet = true
                    } label: {
                        ProfileAvatarView(
                            avatarURL: authManager.avatarURL,
                            fallbackName: authManager.userName ?? authManager.userEmail
                        )
                        .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay {
                if showCreateMenu {
                    ZStack {
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .onTapGesture {
                                dismissCreateMenu()
                            }

                        CreateItemPopupView(
                            onNotebook: {
                                dismissCreateMenuThen {
                                    createBlankLocalDocument(title: "Notebook")
                                }
                            },
                            onTextDoc: {
                                dismissCreateMenuThen {
                                    createBlankLocalDocument(title: "Text Doc")
                                }
                            },
                            onWhiteboard: {
                                dismissCreateMenuThen {
                                    createBlankLocalDocument(title: "Whiteboard")
                                }
                            },
                            onImport: {
                                dismissCreateMenuThen {
                                    showFilePicker = true
                                }
                            },
                            onFolder: {
                                dismissCreateMenuThen {
                                    showCreateFolderAlert = true
                                }
                            }
                        )
                        .transition(LectraMotion.overlayTransition)
                    }
                }
            }
            .sheet(isPresented: $showFilePicker) {
                DocumentPickerView { url in
                    importLocalPDF(from: url, folderId: currentFolderId)
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
                ShareSheetView(items: [payload.url])
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
                Text("Add a new folder to Lectra Vault.")
            }
            .alert("Not Available Yet", isPresented: .init(get: {
                featureNotice != nil
            }, set: { isPresented in
                if !isPresented {
                    featureNotice = nil
                }
            })) {
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
            .task {
                await loadDocuments()
            }
        }
        .preferredColorScheme(.dark)
        .animation(LectraMotion.screenSwap, value: isLoading)
        .animation(LectraMotion.screenSwap, value: currentFolderId)
        .animation(showCreateMenu ? LectraMotion.overlayPresent : LectraMotion.overlayDismiss, value: showCreateMenu)
    }

    // MARK: - Subviews

    private var vaultAtmosphere: some View {
        ZStack {
            Circle()
                .fill(LectraColor.accent.opacity(0.12))
                .frame(width: 500, height: 500)
                .blur(radius: 70)
                .offset(x: -220, y: -260)

            Circle()
                .fill(LectraColor.accentCool.opacity(0.12))
                .frame(width: 420, height: 420)
                .blur(radius: 65)
                .offset(x: 220, y: 210)
        }
        .allowsHitTesting(false)
    }

    private var loadingView: some View {
        VStack(spacing: LectraSpacing.md) {
            ProgressView()
                .tint(LectraColor.accentCool)
                .scaleEffect(1.2)
            Text("Loading documents…")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(LectraColor.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var documentGrid: some View {
        GeometryReader { proxy in
            let cardWidth = idealCardWidth(for: proxy.size.width)

            ScrollView {
                VStack(alignment: .leading, spacing: LectraSpacing.lg) {
                    studioHeader

                    if visibleFolders.isEmpty && visibleDocuments.isEmpty {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )
                            .overlay(
                                VStack(spacing: 10) {
                                    Image(systemName: "sparkles.rectangle.stack")
                                        .font(.system(size: 27, weight: .semibold))
                                        .foregroundColor(LectraColor.accentCool)
                                    Text("Create your first file or folder")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundColor(LectraColor.textPrimary)
                                    Text("Use the add card below to start a notebook, import a PDF, or create a folder.")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(LectraColor.textSecondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 20)
                                }
                                .padding(.vertical, 18)
                            )
                            .transition(.opacity)
                    }

                    if !visibleFolders.isEmpty {
                        sectionHeader(title: "Folders", count: visibleFolders.count)
                        horizontalCardRail {
                            ForEach(visibleFolders) { folder in
                                folderCell(for: folder)
                                    .frame(width: cardWidth)
                                    .scrollTransition(.interactive, axis: .horizontal) { view, phase in
                                        view
                                            .scaleEffect(phase.isIdentity ? 1 : 0.97)
                                            .opacity(phase.isIdentity ? 1 : 0.92)
                                    }
                            }
                        }
                    }

                    sectionHeader(title: "Files", count: visibleDocuments.count)
                    horizontalCardRail {
                        ForEach(visibleDocuments) { doc in
                            documentCell(for: doc)
                                .frame(width: cardWidth)
                                .scrollTransition(.interactive, axis: .horizontal) { view, phase in
                                    view
                                        .scaleEffect(phase.isIdentity ? 1 : 0.97)
                                        .opacity(phase.isIdentity ? 1 : 0.92)
                                }
                        }

                        AddItemCardView {
                            presentCreateMenu()
                        }
                        .frame(width: cardWidth)
                    }
                }
                .padding(LectraSpacing.md)
            }
        }
    }

    private func idealCardWidth(for availableWidth: CGFloat) -> CGFloat {
        let proposed = availableWidth * 0.46
        return min(max(proposed, minCarouselCardWidth), maxCarouselCardWidth)
    }

    @ViewBuilder
    private func horizontalCardRail<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: carouselSpacing) {
                content()
            }
            .scrollTargetLayout()
            .padding(.horizontal, LectraSpacing.md)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
    }

    private var studioHeader: some View {
        HStack(alignment: .top, spacing: LectraSpacing.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text(currentFolder?.name ?? "Lectra Vault")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundColor(LectraColor.textPrimary)
                    .lineLimit(1)
                Text("\(visibleDocuments.count) files · \(visibleFolders.count) folders")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(LectraColor.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text("Create")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(LectraColor.textSecondary)

                Text("Tap +")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [LectraColor.accent, Color(hex: 0xD93F38)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(hex: 0x121A2E, opacity: 0.86))
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LectraGradient.spotlight.opacity(0.52))
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(LectraColor.textPrimary)
            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(LectraColor.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
            Spacer()
        }
    }

    @ViewBuilder
    private func folderCell(for folder: LocalFolder) -> some View {
        FolderCardView(folder: folder)
        .onTapGesture {
            openFolder(folder)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open folder \(folder.name)")
        .accessibilityAddTraits(.isButton)
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items: items, into: folder.id)
        }
        .transition(LectraMotion.cardTransition)
    }

    @ViewBuilder
    private func documentCell(for doc: LocalDocument) -> some View {
        DocumentCardView(
            document: doc,
            onOptionsTap: {
                selectedDocumentForOptions = doc
            }
        )
        .onTapGesture {
            handleDocumentTap(doc)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open file \(doc.title)")
        .accessibilityAddTraits(.isButton)
        .draggable(doc.id.uuidString)
        .transition(LectraMotion.cardTransition)
    }

    private func handleDrop(items: [String], into folderId: UUID) -> Bool {
        let documentIDs = items.compactMap(UUID.init(uuidString:))
        guard !documentIDs.isEmpty else { return false }

        withAnimation(LectraMotion.gridReflow) {
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

        // Load local content immediately so launch from home screen feels instant.
        let savedLocalDocs = loadSavedLocalDocuments()
        withAnimation(LectraMotion.screenSwap) {
            documents = savedLocalDocs
        }
        applyTitleOverrides()
        pruneFolderMappingForCurrentData()
        if let currentFolderId, !folders.contains(where: { $0.id == currentFolderId }) {
            withAnimation(LectraMotion.screenSwap) {
                self.currentFolderId = nil
            }
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
                withAnimation(LectraMotion.gridReflow) {
                    documents = merged
                }
                applyTitleOverrides()

                // Check local cache for each fetched doc
                for doc in documents where doc.status != .local {
                    if repository.isPDFCachedLocally(documentId: doc.id) {
                        doc.localPDFURL = repository.localPDFURL(for: doc.id)
                    }
                }

                pruneFolderMappingForCurrentData()
                if let currentFolderId, !folders.contains(where: { $0.id == currentFolderId }) {
                    withAnimation(LectraMotion.screenSwap) {
                        self.currentFolderId = nil
                    }
                }
            }
        } catch {
            await MainActor.run {
                // Keep local content visible; only surface an error if the screen is empty.
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

        for s in saved {
            let fileURL = documentsDir.appendingPathComponent(s.localPath)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let doc = LocalDocument(title: s.title, localURL: fileURL, id: s.id)
                // The explicit UUID preserves the identity and document loading paths.
                savedLocalDocs.append(doc)
            }
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
            // Need to download first
            Task {
                await MainActor.run {
                    withAnimation(LectraMotion.quick) {
                        doc.status = .downloading
                        documents = Array(documents)
                    }
                }

                do {
                    let url = try await repository.downloadPDF(
                        storagePath: doc.storagePath,
                        documentId: doc.id
                    )

                    await MainActor.run {
                        withAnimation(LectraMotion.quick) {
                            doc.localPDFURL = url
                            doc.status = .pendingAnnotation
                            documents = Array(documents)
                        }
                    }

                    try? await Task.sleep(nanoseconds: 100_000_000)
                    await MainActor.run {
                        presentEditor(for: doc.id)
                    }
                } catch {
                    await MainActor.run {
                        withAnimation(LectraMotion.quick) {
                            doc.status = .error
                            documents = Array(documents)
                        }
                        errorMessage = "Download failed: \(error.localizedDescription)"
                    }
                }
            }
            return
        }

        Task { @MainActor in
            presentEditor(for: doc.id)
        }
    }

    // MARK: - Import Local PDF

    private func importLocalPDF(from url: URL, folderId: UUID? = nil) {
        // Files returned with `asCopy: true` are already inside the app's Inbox.
        // `startAccessingSecurityScopedResource` often returns false for these, causing a silent abort.
        // We can safely read directly from `url`.

        let title = url.deletingPathExtension().lastPathComponent
        let doc = LocalDocument(title: title, localURL: url)

        // Copy to app's documents directory so we have a reliable reference
        let localFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pdfs", isDirectory: true)
            .appendingPathComponent(doc.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: localFolder, withIntermediateDirectories: true)
        let destination = localFolder.appendingPathComponent("original.pdf")

        try? FileManager.default.copyItem(at: url, to: destination)
        doc.localPDFURL = destination
        
        let relativePath = "pdfs/\(doc.id.uuidString)/original.pdf"
        storeLocalDocumentMetadata(docId: doc.id, title: title, relativePath: relativePath, folderId: folderId)

        withAnimation(LectraMotion.gridReflow) {
            documents = [doc] + documents
        }
        
        // Give SwiftUI a moment to process the new item in the list, then open the editor
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            presentEditor(for: doc.id)
        }
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
            withAnimation(LectraMotion.gridReflow) {
                documents = [doc] + documents
            }

            let relativePath = "pdfs/\(doc.id.uuidString)/original.pdf"
            storeLocalDocumentMetadata(
                docId: doc.id,
                title: title,
                relativePath: relativePath,
                folderId: currentFolderId
            )

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                presentEditor(for: doc.id)
            }
        } catch {
            featureNotice = "Could not create a new file: \(error.localizedDescription)"
        }
    }

    private func createFolder(named: String) {
        let trimmed = named.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let folder = LocalFolder(id: UUID(), name: trimmed, createdAt: Date())
        withAnimation(LectraMotion.gridReflow) {
            folders = [folder] + folders
        }
        saveFolders()
    }

    private func loadSavedFolders() {
        guard let data = UserDefaults.standard.data(forKey: localFoldersDefaultsKey),
              let saved = try? JSONDecoder().decode([SavedLocalFolder].self, from: data) else {
            folders = []
            return
        }

        folders = saved
            .map { LocalFolder(id: $0.id, name: $0.name, createdAt: $0.createdAt) }
            .sorted(by: { $0.createdAt > $1.createdAt })
    }

    private func saveFolders() {
        let saved = folders.map { SavedLocalFolder(id: $0.id, name: $0.name, createdAt: $0.createdAt) }
        if let encoded = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(encoded, forKey: localFoldersDefaultsKey)
        }
    }

    private func storeLocalDocumentMetadata(docId: UUID, title: String, relativePath: String, folderId: UUID?) {
        var existingSaved: [SavedLocalDocument] = []
        if let data = UserDefaults.standard.data(forKey: localPDFsDefaultsKey),
           let saved = try? JSONDecoder().decode([SavedLocalDocument].self, from: data) {
            existingSaved = saved
        }

        let updated = SavedLocalDocument(id: docId, title: title, localPath: relativePath)
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

        let applyMove = {
            if let destination {
                documentFolderMap[key] = destination
            } else {
                documentFolderMap.removeValue(forKey: key)
            }
        }

        if shouldAnimate {
            withAnimation(LectraMotion.gridReflow) {
                applyMove()
            }
        } else {
            applyMove()
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

            let duplicated = LocalDocument(title: newTitle, localURL: destination, id: newId)
            withAnimation(LectraMotion.gridReflow) {
                documents = [duplicated] + documents
            }

            let relativePath = "pdfs/\(newId.uuidString)/original.pdf"
            storeLocalDocumentMetadata(
                docId: newId,
                title: newTitle,
                relativePath: relativePath,
                folderId: folderId(for: doc)
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
        sharePayload = SharePayload(url: localURL)
    }

    private func removeDocument(_ doc: LocalDocument) {
        withAnimation(LectraMotion.gridReflow) {
            documents.removeAll(where: { $0.id == doc.id })
            documentFolderMap.removeValue(forKey: doc.id.uuidString)
        }
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
        saveTitleOverride(documentId: doc.id, title: trimmed)

        if doc.status == .local {
            updateSavedLocalDocumentTitle(documentId: doc.id, title: trimmed)
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

    private func updateSavedLocalDocumentTitle(documentId: UUID, title: String) {
        guard let data = UserDefaults.standard.data(forKey: localPDFsDefaultsKey),
              var saved = try? JSONDecoder().decode([SavedLocalDocument].self, from: data),
              let index = saved.firstIndex(where: { $0.id == documentId }) else {
            return
        }

        saved[index] = SavedLocalDocument(
            id: saved[index].id,
            title: title,
            localPath: saved[index].localPath
        )

        if let encoded = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(encoded, forKey: localPDFsDefaultsKey)
        }
    }
}

struct FolderCardView: View {
    let folder: LocalFolder

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x193260), Color(hex: 0x132448)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(VaultGridPattern().opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 6)

                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundColor(LectraColor.accentCool)

                    Text(folder.createdAt.formatted(date: .abbreviated, time: .omitted).uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.82))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.22))
                        .clipShape(Capsule())
                }
                .padding(18)
            }
            .aspectRatio(3/4, contentMode: .fit)

            Text(folder.name)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(LectraColor.textPrimary)
                .lineLimit(1)

            Text(folder.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(LectraColor.textSecondary)
        }
    }
}

struct AddItemCardView: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                Color.white.opacity(0.35),
                                style: StrokeStyle(lineWidth: 2, dash: [7, 9])
                            )
                    )
                    .overlay(VaultGridPattern().opacity(0.12))

                VStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 52, height: 52)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [LectraColor.accent, Color(hex: 0xD93D36)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                    Text("New Item")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(LectraColor.textPrimary)
                }
            }
            .aspectRatio(3/4, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add file or folder")
    }
}

struct CreateItemPopupView: View {
    let onNotebook: () -> Void
    let onTextDoc: () -> Void
    let onWhiteboard: () -> Void
    let onImport: () -> Void
    let onFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LectraSpacing.md) {
            HStack {
                Text("Create in Lectra Vault")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(LectraColor.textPrimary)
                Spacer()
                Image(systemName: "scribble.variable")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(LectraColor.accentCool)
            }

            HStack(spacing: LectraSpacing.sm) {
                PopupActionTile(title: "Notebook", systemImage: "book.closed", badgeText: "NEW", action: onNotebook)
                PopupActionTile(title: "Text Doc", systemImage: "doc.text", badgeText: "NEW", action: onTextDoc)
                PopupActionTile(title: "Whiteboard", systemImage: "square.grid.3x3", badgeText: "NEW", action: onWhiteboard)
            }

            HStack(spacing: LectraSpacing.sm) {
                PopupWideButton(
                    title: "Import PDF",
                    subtitle: "From Files app",
                    systemImage: "square.and.arrow.down",
                    action: onImport
                )
                PopupWideButton(
                    title: "New Folder",
                    subtitle: "Organize your files",
                    systemImage: "folder.badge.plus",
                    action: onFolder
                )
            }
        }
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(hex: 0x0F1628, opacity: 0.98))
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LectraGradient.spotlight.opacity(0.45))
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                VaultGridPattern()
                    .opacity(0.09)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(maxWidth: 760)
        .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 14)
        .padding(LectraSpacing.lg)
    }
}

struct PopupActionTile: View {
    let title: String
    let systemImage: String
    let badgeText: String?
    let action: () -> Void

    init(title: String, systemImage: String, badgeText: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.badgeText = badgeText
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: LectraSpacing.sm) {
                    Image(systemName: systemImage)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(LectraColor.accentCool)
                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(LectraColor.textPrimary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 128)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(hex: 0x202B44, opacity: 0.9))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [LectraColor.accent, Color(hex: 0xD83C37)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .clipShape(Capsule())
                        .offset(x: -8, y: 8)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct PopupWideButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: LectraSpacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(LectraColor.accentCool)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(LectraColor.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, LectraSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: 0x202B44, opacity: 0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct VaultGridPattern: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let step: CGFloat = 22
                var x: CGFloat = 0
                while x <= proxy.size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                    x += step
                }
                var y: CGFloat = 0
                while y <= proxy.size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    y += step
                }
            }
            .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
        }
        .allowsHitTesting(false)
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
            VStack(spacing: LectraSpacing.md) {
                HStack(spacing: LectraSpacing.sm) {
                    Text(documentTitle)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(LectraColor.textPrimary)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(LectraColor.textTertiary)
                            .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, LectraSpacing.md)

                VStack(spacing: 0) {
                    optionRow(title: "Duplicate", systemImage: "plus.square.on.square") {
                        dismiss()
                        onDuplicate()
                    }
                    optionRow(title: "Move", systemImage: "arrowshape.turn.up.right") {
                        dismiss()
                        onMove()
                    }
                    optionRow(title: "Export", systemImage: "square.and.arrow.up") {
                        dismiss()
                        onExport()
                    }
                    optionRow(title: "Move to Trash", systemImage: "trash", isDestructive: true) {
                        dismiss()
                        onDelete()
                    }
                }
                .background(Color(hex: 0x1A2439))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))

                Spacer(minLength: 0)
            }
            .padding(LectraSpacing.md)
            .background(LectraGradient.appBackdrop.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .presentationDetents([.fraction(0.55)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func optionRow(title: String, systemImage: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: LectraSpacing.md) {
                Image(systemName: systemImage)
                    .frame(width: 26)
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
            }
            .foregroundColor(isDestructive ? LectraColor.accent : LectraColor.textPrimary)
            .padding(.horizontal, LectraSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        }
        .buttonStyle(.plain)

        if !isDestructive {
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, LectraSpacing.md)
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
                        Text("Vault Root")
                        Spacer()
                        if currentFolderId == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .foregroundColor(LectraColor.textPrimary)

                ForEach(folders) { folder in
                    Button {
                        onMove(folder.id)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(Color(hex: 0x57A8FF))
                            Text(folder.name)
                                .foregroundColor(LectraColor.textPrimary)
                            Spacer()
                            if currentFolderId == folder.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(LectraColor.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LectraGradient.appBackdrop.ignoresSafeArea())
            .navigationTitle("Move \"\(documentTitle)\"")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(LectraColor.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
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
                        image.resizable().scaledToFill()
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
        .overlay(
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.65), LectraColor.accentCool.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
    }

    private var fallbackAvatar: some View {
        ZStack {
            Circle().fill(Color(hex: 0x40392D))
            Text(fallbackInitial)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundColor(Color(hex: 0xF4D35E))
        }
    }

    private var fallbackInitial: String {
        if let initial = fallbackName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .first {
            return String(initial).uppercased()
        }
        return "G"
    }
}

struct AccountSheetView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: LectraSpacing.lg) {
                ProfileAvatarView(
                    avatarURL: authManager.avatarURL,
                    fallbackName: authManager.userName ?? authManager.userEmail,
                    size: 88
                )
                .padding(.top, LectraSpacing.xl)

                VStack(spacing: LectraSpacing.xs) {
                    Text(authManager.userName ?? "Google Account")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(LectraColor.textPrimary)
                    Text(authManager.userEmail ?? "Signed in")
                        .font(.subheadline)
                        .foregroundColor(LectraColor.textSecondary)
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
                        .clipShape(RoundedRectangle(cornerRadius: LectraRadius.button))
                }
                .buttonStyle(.plain)
            }
            .padding(LectraSpacing.lg)
            .background(LectraGradient.appBackdrop.ignoresSafeArea())
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(LectraColor.accent)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Document Picker (Files app)

struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [UTType.pdf],
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
