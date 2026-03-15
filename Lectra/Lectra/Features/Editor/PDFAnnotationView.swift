import SwiftUI
import PDFKit
import PencilKit
import QuartzCore
import Combine

// MARK: - SwiftUI Wrapper

struct PDFAnnotationView: View {
    private struct ToastAction {
        let title: String
        let handler: () -> Void
    }

    private enum ToastStyle {
        case success
        case info
        case error

        var backgroundColor: Color {
            switch self {
            case .success:
                return LectraColor.success.opacity(0.9)
            case .info:
                return Color(hex: 0x2E8DFF, opacity: 0.92)
            case .error:
                return LectraColor.accent.opacity(0.95)
            }
        }
    }

    @ObservedObject var document: LocalDocument
    let repository: DocumentRepository
    var initialPage: Int? = nil
    var onRename: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var gradescopeManager: GradescopeManager
    @StateObject private var editorBridge = PDFEditorBridge()

    @State private var currentPage: Int = 0
    @State private var totalPages: Int = 1
    @State private var isSaving = false
    @State private var isExportingToCanvascope = false
    @State private var saveMessage: String?
    @State private var saveMessageStyle: ToastStyle = .success
    @State private var isRenamingTitle = false
    @State private var titleDraft = ""
    @FocusState private var isTitleFieldFocused: Bool
    
    // Page Indicator State
    @State private var showPageIndicator: Bool = false
    @State private var indicatorTask: Task<Void, Never>? = nil
    
    @MainActor
    private func triggerPageIndicator() {
        if !showPageIndicator {
            withAnimation(LectraMotion.indicatorFade) {
                showPageIndicator = true
            }
        }
        indicatorTask?.cancel()
        indicatorTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled {
                withAnimation(LectraMotion.indicatorFade) {
                    showPageIndicator = false
                }
            }
        }
    }
    
    // Custom Tool Picker State
    @State private var selectedTool: AnnotationTool = EditorPreferencesStore.shared.load().selectedTool
    @State private var selectedColor: AnnotationInkColor = EditorPreferencesStore.shared.load().selectedColor
    @State private var selectedStrokeWidth: CGFloat = EditorPreferencesStore.shared.load().selectedStrokeWidth
    @State private var highlighterOpacity: CGFloat = EditorPreferencesStore.shared.load().highlighterOpacity
    @State private var selectedEraserMode: EraserMode = EditorPreferencesStore.shared.load().selectedEraserMode
    @State private var toolbarDockEdge: EditorToolbarDockEdge = EditorPreferencesStore.shared.load().dockEdge(for: .landscapeRegular)
    @State private var currentDockProfile: EditorDockProfile = .landscapeRegular
    @State private var editorPreferences = EditorPreferencesStore.shared.load()
    @State private var toolbarSize: CGSize = .zero
    @State private var isToolbarDragging = false
    @State private var canvascopeDeliveryTask: Task<Void, Never>? = nil
    @State private var showGradescopeSubmitSheet = false
    @State private var showDocumentSearchSheet = false
    @State private var documentSearchQuery = ""
    @State private var documentSearchResults: [DocumentSearchResult] = []
    @State private var isSearchingDocument = false
    @State private var showOutlineSheet = false
    @State private var outlineItems: [DocumentOutlineDestination] = []
    @State private var toastAction: ToastAction?
    private let canvascopeExportService = CanvascopeExportService()

    var body: some View {
        GeometryReader { rootProxy in
            ZStack {
                LectraGradient.appBackdrop.ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar

                    if let url = document.localPDFURL {
                        ZStack {
                            PDFEditorRepresentable(
                                pdfURL: url,
                                documentId: document.id,
                                repository: repository,
                                bridge: editorBridge,
                                currentPage: $currentPage,
                                totalPages: $totalPages,
                                selectedTool: $selectedTool,
                                selectedColor: $selectedColor,
                                selectedStrokeWidth: $selectedStrokeWidth,
                                highlighterOpacity: $highlighterOpacity,
                                selectedEraserMode: $selectedEraserMode,
                                initialPage: initialPage ?? max(document.lastOpenedPage, 0),
                                onScroll: { triggerPageIndicator() },
                                onPencilSqueeze: { performPencilSqueezeAction() },
                                onAutoAppendedBlankPage: { handleAutoAppendedBlankPage() }
                            )
                            .ignoresSafeArea(.keyboard)

                            GeometryReader { proxy in
                                floatingToolbar(in: proxy)
                            }

                            if showPageIndicator {
                                VStack {
                                    Spacer()
                                    HStack {
                                        Text("Page \(currentPage + 1) / \(max(totalPages, 1))")
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 9)
                                            .background(
                                                Capsule()
                                                    .fill(Color(hex: 0x0E1628, opacity: 0.9))
                                            )
                                            .overlay(
                                                Capsule()
                                                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                                            )
                                            .padding(.leading, LectraSpacing.lg)
                                            .padding(.bottom, LectraSpacing.lg)
                                        Spacer()
                                    }
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                                .allowsHitTesting(false)
                            }

                            if let msg = saveMessage {
                                VStack {
                                    Spacer()
                                    HStack(spacing: 12) {
                                        Text(msg)
                                            .font(.subheadline.bold())
                                            .foregroundColor(.white)

                                        if let toastAction {
                                            Button(toastAction.title, action: toastAction.handler)
                                                .font(.subheadline.bold())
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(Color.white.opacity(0.18))
                                                .clipShape(Capsule())
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(saveMessageStyle.backgroundColor)
                                    .clipShape(RoundedRectangle(cornerRadius: LectraRadius.button, style: .continuous))
                                    .padding(.bottom, 100)
                                }
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .coordinateSpace(name: "ToolbarDragZone")
                    } else {
                        Spacer()
                        Text("PDF not available")
                            .foregroundColor(LectraColor.textSecondary)
                        Spacer()
                    }
                }
            }
            .onAppear {
                currentPage = initialPage ?? max(document.lastOpenedPage, 0)
                outlineItems = loadOutlineItems()
                updateDockState(for: rootProxy.size)
            }
            .onChange(of: rootProxy.size) { _, newSize in
                updateDockState(for: newSize)
            }
        }
        .preferredColorScheme(.dark)
        .animation(LectraMotion.indicatorFade, value: showPageIndicator)
        .animation(LectraMotion.toast, value: saveMessage)
        .animation(LectraMotion.quick, value: isRenamingTitle)
        .sheet(isPresented: $showGradescopeSubmitSheet) {
            GradescopeSubmitSheet(document: document, repository: repository)
                .environmentObject(gradescopeManager)
        }
        .sheet(isPresented: $showDocumentSearchSheet) {
            documentSearchSheet
        }
        .sheet(isPresented: $showOutlineSheet) {
            outlineSheet
        }
        .onChange(of: selectedTool) { oldValue, newValue in
            if oldValue == .hand, newValue.isAnnotationTool {
                postAccessibilityAnnouncement("\(newValue.rawValue.capitalized) selected")
            }
            persistEditorPreferences()
            if newValue == .lasso && !editorPreferences.hasSeenLassoHint {
                editorPreferences.hasSeenLassoHint = true
                persistEditorPreferences()
                setToast("Lasso is ready. Circle strokes to select them.", style: .info, autoHideAfter: 2.8)
            }
        }
        .onChange(of: selectedColor) { _, _ in persistEditorPreferences() }
        .onChange(of: selectedStrokeWidth) { _, _ in persistEditorPreferences() }
        .onChange(of: highlighterOpacity) { _, _ in persistEditorPreferences() }
        .onChange(of: selectedEraserMode) { _, _ in persistEditorPreferences() }
        .onChange(of: toolbarDockEdge) { _, _ in persistEditorPreferences() }
        .onDisappear {
            indicatorTask?.cancel()
            canvascopeDeliveryTask?.cancel()
            if isRenamingTitle {
                commitTitleRename()
            }
        }
    }

    private func floatingToolbar(in proxy: GeometryProxy) -> some View {
        FloatingToolPickerView(
            selectedTool: $selectedTool,
            selectedColor: $selectedColor,
            selectedStrokeWidth: $selectedStrokeWidth,
            highlighterOpacity: $highlighterOpacity,
            selectedEraserMode: $selectedEraserMode,
            isVertical: toolbarDockEdge.isVertical
        )
        .background(
            GeometryReader { toolbarProxy in
                Color.clear
                    .onAppear {
                        toolbarSize = toolbarProxy.size
                    }
                    .onChange(of: toolbarProxy.size) { _, newSize in
                        toolbarSize = newSize
                    }
            }
        )
        .position(toolbarPosition(in: proxy))
        .simultaneousGesture(toolbarDragGesture(in: proxy.size, safeAreaInsets: proxy.safeAreaInsets))
    }

    private func toolbarPosition(in proxy: GeometryProxy) -> CGPoint {
        let safe = proxy.safeAreaInsets
        let edgeMargin: CGFloat = toolbarDockEdge == .bottom ? (safe.bottom + 28) : LectraSpacing.lg
        let halfWidth = toolbarSize.width * 0.5
        let halfHeight = toolbarSize.height * 0.5

        let minX = safe.leading + LectraSpacing.lg + halfWidth
        let maxX = proxy.size.width - safe.trailing - LectraSpacing.lg - halfWidth
        let minY = safe.top + LectraSpacing.lg + halfHeight
        let maxY = proxy.size.height - edgeMargin - halfHeight

        let midSafeX = safe.leading + ((proxy.size.width - safe.leading - safe.trailing) * 0.5)
        let midSafeY = safe.top + ((proxy.size.height - safe.top - safe.bottom) * 0.5)

        switch toolbarDockEdge {
        case .left:
            return CGPoint(
                x: clamped(minX, min: minX, max: maxX),
                y: clamped(midSafeY, min: minY, max: maxY)
            )
        case .right:
            return CGPoint(
                x: clamped(maxX, min: minX, max: maxX),
                y: clamped(midSafeY, min: minY, max: maxY)
            )
        case .top:
            return CGPoint(
                x: clamped(midSafeX, min: minX, max: maxX),
                y: clamped(minY, min: minY, max: maxY)
            )
        case .bottom:
            return CGPoint(
                x: clamped(midSafeX, min: minX, max: maxX),
                y: clamped(maxY, min: minY, max: maxY)
            )
        }
    }

    private func toolbarDragGesture(in size: CGSize, safeAreaInsets: EdgeInsets) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named("ToolbarDragZone"))
            .onChanged { value in
                if !isToolbarDragging {
                    isToolbarDragging = true
                }
                let newEdge = toolbarDockEdge(for: value.location, in: size, safeAreaInsets: safeAreaInsets)
                if newEdge != toolbarDockEdge {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        toolbarDockEdge = newEdge
                    }
                }
            }
            .onEnded { value in
                isToolbarDragging = false
                let newEdge = toolbarDockEdge(for: value.location, in: size, safeAreaInsets: safeAreaInsets)
                withAnimation(LectraMotion.toolbarDock) {
                    toolbarDockEdge = newEdge
                }
            }
    }

    private func toolbarDockEdge(
        for location: CGPoint,
        in size: CGSize,
        safeAreaInsets: EdgeInsets
    ) -> EditorToolbarDockEdge {
        let leftZone = safeAreaInsets.leading + (size.width - safeAreaInsets.leading - safeAreaInsets.trailing) * 0.25
        let rightZone = safeAreaInsets.leading + (size.width - safeAreaInsets.leading - safeAreaInsets.trailing) * 0.75
        let topZone = safeAreaInsets.top + (size.height - safeAreaInsets.top - safeAreaInsets.bottom) * 0.24
        let bottomZone = size.height - safeAreaInsets.bottom - (size.height * 0.18)

        if location.y <= topZone {
            return .top
        }

        if location.y >= bottomZone {
            return .bottom
        }

        if location.x <= leftZone {
            return .left
        }

        if location.x >= rightZone {
            return .right
        }

        return .bottom
    }

    private func clamped(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        let lower = Swift.min(minValue, maxValue)
        let upper = Swift.max(minValue, maxValue)
        return Swift.min(Swift.max(value, lower), upper)
    }

    private func updateDockState(for size: CGSize) {
        let resolvedProfile = EditorDockProfile.resolve(for: size)
        guard resolvedProfile != currentDockProfile else { return }
        currentDockProfile = resolvedProfile
        toolbarDockEdge = editorPreferences.dockEdge(for: resolvedProfile)
    }

    // MARK: - Top Nav Bar

    private var topBar: some View {
        EditorTopBar(
            documentTitle: document.title,
            titleDraft: $titleDraft,
            isRenamingTitle: isRenamingTitle,
            isReadMode: selectedTool == .hand,
            isSaving: isSaving,
            isExportingToCanvascope: isExportingToCanvascope,
            canUndo: editorBridge.canUndo,
            canRedo: editorBridge.canRedo,
            syncStatus: syncStatusDescriptor,
            hasOutline: !outlineItems.isEmpty,
            handedness: editorPreferences.handedness,
            squeezeAction: editorPreferences.squeezeAction,
            onBack: {
                Task { @MainActor in await saveAndSync() }
            },
            onUndo: { editorBridge.undo() },
            onRedo: { editorBridge.redo() },
            onBeginRename: beginTitleRename,
            onCommitRename: commitTitleRename,
            onShowSearch: { showDocumentSearchSheet = true },
            onShowOutline: { showOutlineSheet = true },
            onSetHandedness: { handedness in
                editorPreferences.handedness = handedness
                toolbarDockEdge = EditorToolbarDockEdge.defaultEdge(for: handedness)
                persistEditorPreferences()
            },
            onSetSqueezeAction: { action in
                editorPreferences.squeezeAction = action
                persistEditorPreferences()
            },
            onExportCanvascope: {
                Task { @MainActor in await exportToCanvascope() }
            },
            onShowGradescope: { showGradescopeSubmitSheet = true },
            onShare: shareDocument,
            isTitleFocused: $isTitleFieldFocused
        )
    }

    // MARK: - Save & Sync

    private var syncStatusDescriptor: EditorSyncStatusDescriptor? {
        switch document.syncState {
        case .idle:
            return nil
        case .savingLocal, .flattening:
            return EditorSyncStatusDescriptor(title: "Saving", color: Color(hex: 0x2E8DFF))
        case .queuedUpload:
            return EditorSyncStatusDescriptor(title: "Queued", color: Color(hex: 0xD0A13A))
        case .uploading:
            return EditorSyncStatusDescriptor(title: "Uploading", color: Color(hex: 0x2E8DFF))
        case .synced:
            return EditorSyncStatusDescriptor(title: "Synced", color: LectraColor.success)
        case .failed:
            return EditorSyncStatusDescriptor(
                title: "Retry",
                color: LectraColor.accent,
                action: {
                    Task { await DocumentSyncCoordinator.shared.retry(documentId: document.id) }
                }
            )
        }
    }

    private func beginTitleRename() {
        titleDraft = document.title
        withAnimation(LectraMotion.quick) {
            isRenamingTitle = true
        }
        isTitleFieldFocused = true
    }

    private func commitTitleRename() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            withAnimation(LectraMotion.quick) {
                isRenamingTitle = false
            }
            isTitleFieldFocused = false
            titleDraft = document.title
            return
        }

        if trimmed != document.title {
            document.title = trimmed
            onRename?(trimmed)
        }

        withAnimation(LectraMotion.quick) {
            isRenamingTitle = false
        }
        isTitleFieldFocused = false
    }

    @MainActor
    private func saveLocally(showBlockingOverlay: Bool = true) async -> Bool {
        if showBlockingOverlay {
            withAnimation(LectraMotion.quick) {
                isSaving = true
            }
        }
        var didSucceed = false
        do {
            let startingMetadata = DocumentLocalMetadata(
                syncState: .savingLocal,
                syncErrorMessage: nil,
                dirtyPageIndexes: Array(document.dirtyPageIndexes).sorted(),
                lastLocalEditAt: document.lastLocalEditAt,
                lastRemoteSyncAt: document.lastRemoteSyncAt,
                lastOpenedPage: currentPage,
                thumbnailRevision: document.thumbnailRevision,
                searchIndexRevision: document.searchIndexRevision
            )
            document.apply(metadata: startingMetadata)
            repository.saveLocalMetadata(startingMetadata, documentId: document.id)

            let result = try await editorBridge.exportCurrentDocument()
            document.updatedAt = result.localEditAt
            let metadata = DocumentLocalMetadata(
                syncState: document.isRemoteBacked ? .queuedUpload : .synced,
                syncErrorMessage: nil,
                dirtyPageIndexes: result.dirtyPageIndexes,
                lastLocalEditAt: result.localEditAt,
                lastRemoteSyncAt: document.lastRemoteSyncAt,
                lastOpenedPage: result.lastOpenedPage,
                thumbnailRevision: document.thumbnailRevision + 1,
                searchIndexRevision: document.searchIndexRevision + 1
            )
            document.apply(metadata: metadata)

            if let pdfURL = document.localPDFURL {
                ThumbnailCache.shared.warmThumbnail(
                    documentId: document.id,
                    pdfURL: pdfURL,
                    revision: metadata.thumbnailRevision
                )
            }

            await DocumentSyncCoordinator.shared.registerLocalSave(
                result: result,
                documentId: document.id,
                title: document.title,
                rowId: document.isRemoteBacked ? document.supabaseRowId : nil,
                itemData: document.sourceDocumentData,
                userId: authManager.userId
            )
            didSucceed = true
        } catch {
            setToast(error.localizedDescription, style: .error, autoHideAfter: 3.0)
        }
        if showBlockingOverlay {
            withAnimation(LectraMotion.quick) {
                isSaving = false
            }
        }
        return didSucceed
    }

    @MainActor
    private func saveAndSync() async {
        guard await saveLocally(showBlockingOverlay: true) else { return }
        dismiss()
    }
    
    // MARK: - Sharing
    
    private func shareDocument() {
        Task { @MainActor in
            guard await saveLocally(showBlockingOverlay: true) else { return }

            guard let finalURL = preferredExportURL() else { return }
            
            let activityVC = UIActivityViewController(activityItems: [finalURL], applicationActivities: nil)
            
            // For iPad, we need a popover source, but we can just use the window scenes for a hacky center popover
            if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
               let window = windowScene.windows.first(where: { $0.isKeyWindow }),
               var topVC = window.rootViewController {
                
                while let presented = topVC.presentedViewController {
                    topVC = presented
                }
                
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = topVC.view
                    popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                
                topVC.present(activityVC, animated: true, completion: nil)
            }
        }
    }

    @MainActor
    private func exportToCanvascope() async {
        guard !isExportingToCanvascope else { return }
        canvascopeDeliveryTask?.cancel()
        isExportingToCanvascope = true
        defer { isExportingToCanvascope = false }

        guard await saveLocally(showBlockingOverlay: false) else { return }

        guard let exportURL = preferredExportURL() else {
            setToast("PDF not available for export.", style: .error, autoHideAfter: 2.6)
            return
        }

        setToast("Sending to Canvascope…", style: .info, autoHideAfter: nil)

        do {
            let receipt = try await canvascopeExportService.uploadToCanvascope(fileURL: exportURL)
            setToast("Queued for Canvascope download", style: .success, autoHideAfter: 2.8)
            trackCanvascopeDelivery(uploadId: receipt.uploadId)
        } catch let exportError as CanvascopeExportError {
            switch exportError {
            case .noActiveReceiver:
                setToast("Open Canvascope extension on desktop", style: .info, autoHideAfter: 3.0)
            case .notAuthenticated:
                setToast("Please sign in again to export.", style: .error, autoHideAfter: 2.8)
            case .fileTooLarge:
                setToast("File too large to export (25 MB max).", style: .error, autoHideAfter: 2.8)
            case .network(let message):
                setToast("Network error: \(message)", style: .error, autoHideAfter: 3.0)
            case .server(let message):
                setToast(message, style: .error, autoHideAfter: 3.0)
            case .invalidResponse:
                setToast("Unexpected export response. Try again.", style: .error, autoHideAfter: 3.0)
            }
        } catch {
            setToast("Export failed. Try again.", style: .error, autoHideAfter: 2.8)
        }
    }

    private func trackCanvascopeDelivery(uploadId: String) {
        canvascopeDeliveryTask?.cancel()
        canvascopeDeliveryTask = Task {
            do {
                guard let status = try await canvascopeExportService.awaitTerminalStatus(uploadId: uploadId) else {
                    return
                }
                if Task.isCancelled { return }
                await MainActor.run {
                    switch status.status {
                    case "downloaded":
                        setToast("Downloaded on your laptop in Canvascope ✓", style: .success, autoHideAfter: 3.2)
                    case "canceled":
                        setToast("Canvascope download canceled", style: .info, autoHideAfter: 2.8)
                    default:
                        break
                    }
                }
            } catch {
                // Ignore background status polling failures to avoid noisy toasts.
            }
        }
    }

    private func preferredExportURL() -> URL? {
        let annotatedURL = repository.localPDFURL(for: document.id)
            .deletingLastPathComponent()
            .appendingPathComponent("annotated.pdf")

        if FileManager.default.fileExists(atPath: annotatedURL.path) {
            return annotatedURL
        }

        return document.localPDFURL
    }

    @MainActor
    private func setToast(
        _ message: String,
        style: ToastStyle,
        autoHideAfter: TimeInterval?,
        action: ToastAction? = nil
    ) {
        withAnimation(LectraMotion.toast) {
            saveMessageStyle = style
            saveMessage = message
            toastAction = action
        }
        postAccessibilityAnnouncement(message)

        guard let autoHideAfter else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + autoHideAfter) {
            guard saveMessage == message else { return }
            withAnimation(LectraMotion.toast) {
                saveMessage = nil
                toastAction = nil
            }
        }
    }

    private func persistEditorPreferences() {
        editorPreferences.noteSelectedTool(selectedTool)
        editorPreferences.selectedColor = selectedColor
        editorPreferences.selectedStrokeWidth = selectedStrokeWidth
        editorPreferences.highlighterOpacity = highlighterOpacity
        editorPreferences.selectedEraserMode = selectedEraserMode
        editorPreferences.setDockEdge(toolbarDockEdge, for: currentDockProfile)
        EditorPreferencesStore.shared.save(editorPreferences)
    }

    private func preferredReturnAnnotationTool() -> AnnotationTool {
        switch editorPreferences.lastAnnotationTool {
        case .eraser, .hand:
            return .pen
        case .pen, .highlighter, .lasso:
            return editorPreferences.lastAnnotationTool
        }
    }

    @MainActor
    private func handleAutoAppendedBlankPage() {
        setToast(
            "New page added",
            style: .info,
            autoHideAfter: 4.5,
            action: ToastAction(title: "Undo") {
                if editorBridge.undoLastAutoAppendedBlankPage() {
                    setToast("Removed blank page", style: .info, autoHideAfter: 2.4)
                }
            }
        )
    }

    private func loadOutlineItems() -> [DocumentOutlineDestination] {
        guard let pdfURL = document.localPDFURL,
              let pdfDocument = PDFDocument(url: pdfURL),
              let root = pdfDocument.outlineRoot else {
            return []
        }

        var destinations: [DocumentOutlineDestination] = []

        func walk(_ outline: PDFOutline, depth: Int) {
            for index in 0..<outline.numberOfChildren {
                guard let child = outline.child(at: index) else { continue }
                let pageIndex = child.destination?.page.flatMap { page in
                    pdfDocument.index(for: page)
                }
                if let pageIndex {
                    destinations.append(
                        DocumentOutlineDestination(
                            title: child.label ?? "Untitled",
                            pageIndex: pageIndex,
                            depth: depth
                        )
                    )
                }
                walk(child, depth: depth + 1)
            }
        }

        walk(root, depth: 0)
        return destinations
    }

    private func performPencilSqueezeAction() {
        switch editorPreferences.squeezeAction {
        case .togglePenEraser:
            withAnimation(LectraMotion.quick) {
                let activeTool = selectedTool == .hand ? preferredReturnAnnotationTool() : selectedTool
                selectedTool = activeTool == .eraser ? preferredReturnAnnotationTool() : .eraser
            }
            if !editorPreferences.hasSeenSqueezeHint {
                editorPreferences.hasSeenSqueezeHint = true
                persistEditorPreferences()
                setToast("Pencil squeeze now toggles your active tool.", style: .info, autoHideAfter: 2.6)
            }
        case .undo:
            editorBridge.undo()
        case .redo:
            editorBridge.redo()
        }
    }

    private func searchCurrentDocument() {
        guard let pdfURL = document.localPDFURL else { return }
        let query = documentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            documentSearchResults = []
            return
        }
        let documentId = document.id
        let title = document.title

        isSearchingDocument = true
        Task {
            defer {
                Task { @MainActor in
                    isSearchingDocument = false
                }
            }

            let results: [DocumentSearchResult] = await Task.detached(priority: .userInitiated) {
                guard let pdfDocument = PDFDocument(url: pdfURL) else { return [] }
                var matches: [DocumentSearchResult] = []
                for index in 0..<pdfDocument.pageCount {
                    let text = pdfDocument.page(at: index)?.string?
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !text.isEmpty else { continue }
                    let nsText = text as NSString
                    let range = nsText.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
                    guard range.location != NSNotFound else { continue }
                    let start = max(range.location - 48, 0)
                    let end = min(range.location + range.length + 48, nsText.length)
                    let snippetRange = NSRange(location: start, length: max(end - start, 0))
                    matches.append(
                        DocumentSearchResult(
                            documentId: documentId,
                            title: title,
                            subtitle: "Page \(index + 1)",
                            snippet: nsText.substring(with: snippetRange),
                            pageIndex: index,
                            kind: .pageText
                        )
                    )
                }
                return matches
            }.value

            await MainActor.run {
                documentSearchResults = results
            }
        }
    }

    private var documentSearchSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                PDFEditorSearchBar(text: $documentSearchQuery)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .onChange(of: documentSearchQuery) { _, _ in
                        searchCurrentDocument()
                    }

                if isSearchingDocument {
                    ProgressView()
                        .tint(.white)
                } else if documentSearchResults.isEmpty {
                    Spacer()
                    Text(documentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Start typing to search this PDF." : "No matches found.")
                        .foregroundColor(Color.white.opacity(0.7))
                    Spacer()
                } else {
                    List(documentSearchResults) { result in
                        Button {
                            if let pageIndex = result.pageIndex {
                                currentPage = pageIndex
                            }
                            showDocumentSearchSheet = false
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(result.subtitle)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                if let snippet = result.snippet {
                                    Text(snippet)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Color.white.opacity(0.72))
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
            }
            .background(Color(hex: 0x0E1628).ignoresSafeArea())
            .navigationTitle("Search PDF")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showDocumentSearchSheet = false
                    }
                    .foregroundColor(LectraColor.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    private var outlineSheet: some View {
        NavigationStack {
            List(outlineItems) { item in
                Button {
                    currentPage = item.pageIndex
                    showOutlineSheet = false
                } label: {
                    HStack(spacing: 12) {
                        Text(item.title)
                            .foregroundColor(.white)
                            .padding(.leading, CGFloat(item.depth) * 12)
                        Spacer(minLength: 0)
                        Text("P\(item.pageIndex + 1)")
                            .foregroundColor(Color.white.opacity(0.54))
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: 0x0E1628).ignoresSafeArea())
            .navigationTitle("Outline")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showOutlineSheet = false
                    }
                    .foregroundColor(LectraColor.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Notification Name
extension Notification.Name {
    static let lectraBackgroundSyncCompleted = Notification.Name("lectraBackgroundSyncCompleted")
}

private struct DocumentOutlineDestination: Identifiable, Hashable {
    let title: String
    let pageIndex: Int
    let depth: Int

    var id: String { "\(pageIndex)-\(title)-\(depth)" }
}

@MainActor
final class PDFEditorBridge: ObservableObject {
    enum BridgeError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Editor is not ready yet. Please try again."
            }
        }
    }

    weak var controller: PageAnnotationViewController?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    func attach(controller: PageAnnotationViewController) {
        self.controller = controller
    }

    func updateUndoRedo(canUndo: Bool, canRedo: Bool) {
        self.canUndo = canUndo
        self.canRedo = canRedo
    }

    func exportCurrentDocument() async throws -> DocumentSaveResult {
        guard let controller else { throw BridgeError.unavailable }
        return try await controller.prepareSaveResult()
    }

    func undo() {
        controller?.undoLastAction()
    }

    func redo() {
        controller?.redoLastAction()
    }

    @discardableResult
    func undoLastAutoAppendedBlankPage() -> Bool {
        controller?.undoLastAutoAppendedBlankPage() ?? false
    }
}

private struct PDFEditorSearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color.white.opacity(0.48))

            TextField("Search pages", text: $text)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .foregroundColor(.white)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.white.opacity(0.48))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(Color(hex: 0x171A22))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - PDFEditorRepresentable (UIKit Bridge)

struct PDFEditorRepresentable: UIViewControllerRepresentable {
    let pdfURL: URL
    let documentId: UUID
    let repository: DocumentRepository
    let bridge: PDFEditorBridge
    @Binding var currentPage: Int
    @Binding var totalPages: Int
    @Binding var selectedTool: AnnotationTool
    @Binding var selectedColor: AnnotationInkColor
    @Binding var selectedStrokeWidth: CGFloat
    @Binding var highlighterOpacity: CGFloat
    @Binding var selectedEraserMode: EraserMode
    let initialPage: Int
    var onScroll: (() -> Void)? = nil
    var onTypewriterAutoAdvance: ((Int, CGPoint) -> Void)? = nil
    var onPencilSqueeze: (() -> Void)? = nil
    var onAutoAppendedBlankPage: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> PageAnnotationViewController {
        let vc = PageAnnotationViewController()
        vc.pdfURL = pdfURL
        vc.documentId = documentId
        vc.repository = repository
        vc.coordinator = context.coordinator
        vc.currentPageIndex = initialPage
        vc.undoRedoDidChange = { [weak bridge] canUndo, canRedo in
            Task { @MainActor in
                bridge?.updateUndoRedo(canUndo: canUndo, canRedo: canRedo)
            }
        }
        vc.onTypewriterAutoAdvance = { [weak coordinator = context.coordinator] pageIndex, offset in
            coordinator?.typewriterAutoAdvanceDidTrigger(pageIndex: pageIndex, offset: offset)
        }
        vc.onAutoAppendedBlankPage = onAutoAppendedBlankPage
        bridge.attach(controller: vc)
        return vc
    }

    func updateUIViewController(_ vc: PageAnnotationViewController, context: Context) {
        if vc.currentPageIndex != currentPage && !vc.isScrollingProgrammatically {
            vc.navigateToPage(currentPage)
        }

        vc.setTool(
            selectedTool,
            color: selectedColor,
            width: selectedStrokeWidth,
            highlighterOpacity: highlighterOpacity,
            eraserMode: selectedEraserMode
        )
    }

    class Coordinator {
        let parent: PDFEditorRepresentable
        init(parent: PDFEditorRepresentable) { self.parent = parent }

        func pageDidChange(to index: Int, total: Int) {
            DispatchQueue.main.async {
                if self.parent.currentPage != index {
                    self.parent.currentPage = index
                }
                if self.parent.totalPages != total {
                    self.parent.totalPages = total
                }
                self.parent.onScroll?()
            }
        }
        
        func scrollViewDidScroll() {
            DispatchQueue.main.async {
                self.parent.onScroll?()
            }
        }

        func togglePenAndEraserFromPencilSqueeze() {
            DispatchQueue.main.async {
                self.parent.onPencilSqueeze?()
            }
        }

        func typewriterAutoAdvanceDidTrigger(pageIndex: Int, offset: CGPoint) {
            DispatchQueue.main.async {
                self.parent.onTypewriterAutoAdvance?(pageIndex, offset)
            }
        }
    }
}

// MARK: - PageView
private final class TiledPDFPageView: UIView {
    private var pdfPage: PDFPage?
    private var pageBounds: CGRect = .zero
    private let stateLock = NSLock()

    override class var layerClass: AnyClass { CATiledLayer.self }

    private var tiledLayer: CATiledLayer {
        layer as! CATiledLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isOpaque = true
        contentMode = .redraw

        let screenScale = UIScreen.main.scale
        tiledLayer.levelsOfDetail = 4
        tiledLayer.levelsOfDetailBias = 5
        tiledLayer.tileSize = CGSize(width: 512 * screenScale, height: 512 * screenScale)
        tiledLayer.contentsScale = screenScale
    }

    required init?(coder: NSCoder) { fatalError() }

    func setPage(_ page: PDFPage?) {
        stateLock.lock()
        pdfPage = page
        pageBounds = page?.bounds(for: .mediaBox) ?? .zero
        stateLock.unlock()
        if page == nil {
            layer.contents = nil
        }
        tiledLayer.setNeedsDisplay()
    }

    func setBlankPage(bounds: CGRect) {
        stateLock.lock()
        pdfPage = nil
        pageBounds = bounds
        stateLock.unlock()
        layer.contents = nil
        tiledLayer.setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        tiledLayer.setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        UIColor.white.setFill()
        context.fill(rect)

        stateLock.lock()
        let page = pdfPage
        let bounds = pageBounds
        stateLock.unlock()

        guard let page, !bounds.isEmpty else { return }

        let scaleX = self.bounds.width / bounds.width
        let scaleY = self.bounds.height / bounds.height

        context.saveGState()
        context.translateBy(x: 0, y: self.bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.scaleBy(x: scaleX, y: scaleY)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
    }
}

private enum InkBlendMode: String, Codable {
    case normal
    case multiply

    nonisolated var cgBlendMode: CGBlendMode {
        switch self {
        case .normal:
            return .normal
        case .multiply:
            return .multiply
        }
    }
}

private struct InkColorComponents: Codable, Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(color: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    nonisolated var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

private struct InkPoint: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var force: CGFloat
}

private struct InkStroke: Codable, Equatable {
    var points: [InkPoint]
    var width: CGFloat
    var color: InkColorComponents
    var blendMode: InkBlendMode
}

private struct InkPageDrawing: Codable, Equatable {
    var strokes: [InkStroke] = []

    nonisolated var isEmpty: Bool {
        strokes.isEmpty
    }
}

private struct InkDrawingStore: Codable {
    var version: Int
    var pages: [Int: InkPageDrawing]
}

private struct InkToolDescriptor {
    enum Mode {
        case hand
        case pen
        case highlighter
        case eraser
        case lasso
    }

    var mode: Mode
    var color: UIColor
    var width: CGFloat
    var blendMode: InkBlendMode
    var eraserRadius: CGFloat
    var eraserMode: EraserMode

    static let `default` = InkToolDescriptor(annotationTool: .pen, inkColor: .black, width: 2.0)

    init(
        annotationTool: AnnotationTool,
        inkColor: AnnotationInkColor,
        width: CGFloat,
        highlighterOpacity: CGFloat = 0.35,
        eraserMode: EraserMode = .stroke
    ) {
        switch annotationTool {
        case .hand:
            mode = .hand
            color = .clear
            self.width = 0
            blendMode = .normal
            eraserRadius = 0
            self.eraserMode = .stroke
        case .pen:
            mode = .pen
            color = inkColor.inkUIColor.withAlphaComponent(1.0)
            self.width = min(max(width, 0.5), 2.0)
            blendMode = .normal
            eraserRadius = 0
            self.eraserMode = .stroke
        case .highlighter:
            mode = .highlighter
            color = inkColor.inkUIColor.withAlphaComponent(min(max(highlighterOpacity, 0.1), 0.85))
            self.width = min(max(width * 1.8, 1.5), 20.0)
            blendMode = .multiply
            eraserRadius = 0
            self.eraserMode = .stroke
        case .eraser:
            mode = .eraser
            color = .clear
            self.width = min(max(width, 0.8), 12.0)
            blendMode = .normal
            self.eraserMode = eraserMode
            eraserRadius = max(self.width * 1.2, 2.0)
        case .lasso:
            mode = .lasso
            color = .clear
            self.width = min(max(width, 2.0), 24.0)
            blendMode = .normal
            eraserRadius = 0
            self.eraserMode = .stroke
        }
    }
}

private final class PencilStrokeGestureRecognizer: UIGestureRecognizer {
    private(set) var sampledTouches: [UITouch] = []
    private(set) var latestTouch: UITouch?
    private var activeTouch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first(where: { $0.type == .pencil }) else { return }
        if let activeTouch, activeTouch !== touch { return }
        activeTouch = touch
        captureSamples(for: touch, event: event)
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let activeTouch, touches.contains(where: { $0 === activeTouch }) else { return }
        captureSamples(for: activeTouch, event: event)
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let activeTouch, touches.contains(where: { $0 === activeTouch }) else { return }
        captureSamples(for: activeTouch, event: event)
        state = .ended
        self.activeTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let activeTouch, touches.contains(where: { $0 === activeTouch }) else { return }
        captureSamples(for: activeTouch, event: event)
        state = .cancelled
        self.activeTouch = nil
    }

    override func reset() {
        super.reset()
        sampledTouches.removeAll(keepingCapacity: true)
        latestTouch = nil
        activeTouch = nil
    }

    private func captureSamples(for touch: UITouch, event: UIEvent) {
        latestTouch = touch
        sampledTouches = event.coalescedTouches(for: touch) ?? [touch]
    }
}

private final class VectorInkCanvasView: UIView {
    private struct LassoSelection {
        let strokeIndexes: [Int]
        let sourceStrokes: [InkStroke]
        let bounds: CGRect
    }

    private enum LassoInteraction {
        case drawingPath
        case moving(startPoint: CGPoint, selection: LassoSelection)
        case resizing(handle: LassoSelectionHandle, selection: LassoSelection)
    }

    var onDrawingChanged: ((InkPageDrawing) -> Void)?
    var tool: InkToolDescriptor = .default {
        didSet {
            if tool.mode == .eraser {
                if let center = eraserPreviewCenter {
                    updateEraserPreview(at: center)
                } else {
                    configureEraserPreviewAppearance()
                }
            } else if tool.mode != .lasso {
                hideEraserPreview()
                cancelLassoInteraction(keepSelection: false)
            } else {
                hideEraserPreview()
            }
        }
    }

    private(set) var drawing = InkPageDrawing()

    private var strokeLayers: [CAShapeLayer] = []
    private var activeStrokePoints: [InkPoint] = []
    private var activeStrokeWidth: CGFloat = 1.0
    private var activeStrokeColor = InkColorComponents(red: 0, green: 0, blue: 0, alpha: 1)
    private var activeBlendMode: InkBlendMode = .normal
    private var activeStrokeLayer: CAShapeLayer?
    private let eraserPreviewLayer = CAShapeLayer()
    private var eraserPreviewCenter: CGPoint?
    private let lassoPreviewLayer = CAShapeLayer()
    private let selectionOutlineLayer = CAShapeLayer()
    private var selectionHandleLayers: [LassoSelectionHandle: CAShapeLayer] = [:]
    private var previewStrokeLayers: [CAShapeLayer] = []
    private let selectionActionsView = UIStackView()
    private let duplicateSelectionButton = UIButton(type: .system)
    private let deleteSelectionButton = UIButton(type: .system)
    private var activeLassoPoints: [CGPoint] = []
    private var activeSelection: LassoSelection?
    private var lassoInteraction: LassoInteraction?
    private var previewSelectionPoints: [Int: [CGPoint]] = [:]

    private lazy var pencilGesture: PencilStrokeGestureRecognizer = {
        let gesture = PencilStrokeGestureRecognizer(target: self, action: #selector(handlePencilGesture(_:)))
        gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        gesture.cancelsTouchesInView = true
        gesture.delaysTouchesBegan = false
        gesture.delaysTouchesEnded = false
        return gesture
    }()

    private lazy var pencilHoverGesture: UIHoverGestureRecognizer = {
        let gesture = UIHoverGestureRecognizer(target: self, action: #selector(handlePencilHoverGesture(_:)))
        gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        gesture.cancelsTouchesInView = false
        return gesture
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true
        layer.shouldRasterize = false
        layer.drawsAsynchronously = false
        configureEraserPreviewLayer()
        configureLassoLayers()
        configureSelectionActionsView()
        addGestureRecognizer(pencilGesture)
        addGestureRecognizer(pencilHoverGesture)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildStrokePaths()
        if tool.mode == .eraser, let center = eraserPreviewCenter {
            updateEraserPreview(at: center)
        }
        updateSelectionOverlay()
    }

    func setDrawing(_ drawing: InkPageDrawing) {
        self.drawing = drawing
        cancelLassoInteraction(keepSelection: false)
        rebuildStrokeLayers()
    }

    func currentDrawing() -> InkPageDrawing {
        drawing
    }

    func refreshForZoom(zoomScale: CGFloat, forceRedraw: Bool = false) {
        let targetScale = UIScreen.main.scale * max(zoomScale, 1.0)
        if abs(layer.contentsScale - targetScale) > 0.1 || forceRedraw {
            layer.contentsScale = targetScale
            for strokeLayer in strokeLayers {
                strokeLayer.contentsScale = targetScale
                strokeLayer.shouldRasterize = false
            }
            activeStrokeLayer?.contentsScale = targetScale
            lassoPreviewLayer.contentsScale = targetScale
            selectionOutlineLayer.contentsScale = targetScale
            previewStrokeLayers.forEach {
                $0.contentsScale = targetScale
                $0.shouldRasterize = false
            }
            for handleLayer in selectionHandleLayers.values {
                handleLayer.contentsScale = targetScale
                handleLayer.shouldRasterize = false
            }
            if forceRedraw {
                rebuildStrokePaths()
            }
        }
    }

    @objc
    private func handlePencilGesture(_ gesture: PencilStrokeGestureRecognizer) {
        let samples = pencilSamples(from: gesture)
        switch gesture.state {
        case .began:
            guard let first = samples.first else { return }
            if tool.mode == .hand {
                cancelLassoInteraction(keepSelection: false)
            } else if tool.mode == .eraser {
                updateEraserPreview(at: first.point)
                erase(at: first.point)
            } else if tool.mode == .lasso {
                hideEraserPreview()
                beginLassoInteraction(at: first.point)
                for sample in samples.dropFirst() {
                    updateLassoInteraction(to: sample.point)
                }
            } else {
                hideEraserPreview()
                beginStroke(at: first.point, force: first.force)
                for sample in samples.dropFirst() {
                    appendStroke(at: sample.point, force: sample.force)
                }
            }
        case .changed:
            if tool.mode == .hand {
                return
            } else if tool.mode == .eraser {
                for sample in samples {
                    updateEraserPreview(at: sample.point)
                    erase(at: sample.point)
                }
            } else if tool.mode == .lasso {
                hideEraserPreview()
                for sample in samples {
                    updateLassoInteraction(to: sample.point)
                }
            } else {
                hideEraserPreview()
                for sample in samples {
                    appendStroke(at: sample.point, force: sample.force)
                }
            }
        case .ended:
            hideEraserPreview()
            if tool.mode == .lasso {
                if let lastPoint = samples.last?.point {
                    updateLassoInteraction(to: lastPoint)
                }
                finishLassoInteraction()
            } else if tool.mode != .eraser && tool.mode != .hand {
                for sample in samples {
                    appendStroke(at: sample.point, force: sample.force)
                }
                finishStroke()
            }
        case .cancelled, .failed:
            hideEraserPreview()
            if tool.mode == .lasso {
                cancelLassoInteraction(keepSelection: true)
            } else {
                discardActiveStroke()
            }
        default:
            break
        }
    }

    @objc
    private func handlePencilHoverGesture(_ gesture: UIHoverGestureRecognizer) {
        guard tool.mode == .eraser else {
            hideEraserPreview()
            return
        }

        switch gesture.state {
        case .began, .changed:
            updateEraserPreview(at: gesture.location(in: self))
        case .ended, .cancelled, .failed:
            hideEraserPreview()
        default:
            break
        }
    }

    private func configureEraserPreviewLayer() {
        eraserPreviewLayer.fillColor = UIColor(white: 0.45, alpha: 0.26).cgColor
        eraserPreviewLayer.strokeColor = UIColor.white.withAlphaComponent(0.98).cgColor
        eraserPreviewLayer.lineWidth = eraserPreviewStrokeWidth(for: 8.0)
        eraserPreviewLayer.shadowColor = UIColor.black.withAlphaComponent(0.55).cgColor
        eraserPreviewLayer.shadowOffset = .zero
        eraserPreviewLayer.shadowRadius = 1.6
        eraserPreviewLayer.shadowOpacity = 1.0
        eraserPreviewLayer.isHidden = true
        eraserPreviewLayer.zPosition = 10_000
        eraserPreviewLayer.contentsScale = UIScreen.main.scale
        layer.addSublayer(eraserPreviewLayer)
    }

    private func configureLassoLayers() {
        lassoPreviewLayer.fillColor = UIColor.clear.cgColor
        lassoPreviewLayer.strokeColor = UIColor.white.withAlphaComponent(0.94).cgColor
        lassoPreviewLayer.lineWidth = 2
        lassoPreviewLayer.lineDashPattern = [8, 6]
        lassoPreviewLayer.isHidden = true
        lassoPreviewLayer.zPosition = 9_000
        lassoPreviewLayer.contentsScale = UIScreen.main.scale
        layer.addSublayer(lassoPreviewLayer)

        selectionOutlineLayer.fillColor = UIColor.clear.cgColor
        selectionOutlineLayer.strokeColor = LectraColor.accentUIColor.cgColor
        selectionOutlineLayer.lineWidth = 2
        selectionOutlineLayer.lineDashPattern = [10, 6]
        selectionOutlineLayer.isHidden = true
        selectionOutlineLayer.zPosition = 9_200
        selectionOutlineLayer.contentsScale = UIScreen.main.scale
        layer.addSublayer(selectionOutlineLayer)

        for handle in LassoSelectionHandle.allCases {
            let handleLayer = CAShapeLayer()
            handleLayer.fillColor = UIColor.white.cgColor
            handleLayer.strokeColor = LectraColor.accentUIColor.cgColor
            handleLayer.lineWidth = 2
            handleLayer.isHidden = true
            handleLayer.zPosition = 9_250
            handleLayer.contentsScale = UIScreen.main.scale
            layer.addSublayer(handleLayer)
            selectionHandleLayers[handle] = handleLayer
        }
    }

    private func configureSelectionActionsView() {
        selectionActionsView.axis = .horizontal
        selectionActionsView.alignment = .fill
        selectionActionsView.distribution = .fillEqually
        selectionActionsView.spacing = 8
        selectionActionsView.backgroundColor = UIColor(white: 0.08, alpha: 0.92)
        selectionActionsView.layer.cornerRadius = 18
        selectionActionsView.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        selectionActionsView.layer.borderWidth = 1
        selectionActionsView.isHidden = true

        configureSelectionActionButton(
            duplicateSelectionButton,
            title: "Duplicate",
            symbolName: "plus.square.on.square"
        )
        duplicateSelectionButton.addTarget(self, action: #selector(handleDuplicateSelection), for: .touchUpInside)

        configureSelectionActionButton(
            deleteSelectionButton,
            title: "Delete",
            symbolName: "trash"
        )
        deleteSelectionButton.addTarget(self, action: #selector(handleDeleteSelection), for: .touchUpInside)

        selectionActionsView.addArrangedSubview(duplicateSelectionButton)
        selectionActionsView.addArrangedSubview(deleteSelectionButton)
        addSubview(selectionActionsView)
    }

    private func configureSelectionActionButton(_ button: UIButton, title: String, symbolName: String) {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: symbolName)
        configuration.imagePadding = 6
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        button.configuration = configuration
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.accessibilityLabel = title
    }

    private func configureEraserPreviewAppearance() {
        guard tool.mode == .eraser else { return }
        eraserPreviewLayer.fillColor = UIColor(white: 0.45, alpha: 0.26).cgColor
        eraserPreviewLayer.strokeColor = UIColor.white.withAlphaComponent(0.98).cgColor
        let currentRadius = max(tool.eraserRadius, 2.0)
        eraserPreviewLayer.lineWidth = eraserPreviewStrokeWidth(for: currentRadius)
        eraserPreviewLayer.shadowColor = UIColor.black.withAlphaComponent(0.55).cgColor
        eraserPreviewLayer.shadowOffset = .zero
        eraserPreviewLayer.shadowRadius = 1.6
        eraserPreviewLayer.shadowOpacity = 1.0
    }

    private func updateEraserPreview(at point: CGPoint) {
        guard tool.mode == .eraser else {
            hideEraserPreview()
            return
        }
        eraserPreviewCenter = point
        configureEraserPreviewAppearance()

        let radius = max(tool.eraserRadius, 2.0)
        eraserPreviewLayer.lineWidth = eraserPreviewStrokeWidth(for: radius)
        let diameter = radius * 2.0
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: diameter,
            height: diameter
        )
        eraserPreviewLayer.path = UIBezierPath(ovalIn: rect).cgPath
        eraserPreviewLayer.isHidden = false
    }

    private func hideEraserPreview() {
        eraserPreviewCenter = nil
        eraserPreviewLayer.path = nil
        eraserPreviewLayer.isHidden = true
    }

    private func eraserPreviewStrokeWidth(for radius: CGFloat) -> CGFloat {
        // Keep small eraser rings visually light while preserving visibility for larger sizes.
        min(max(radius * 0.16, 0.9), 2.0)
    }

    private func beginLassoInteraction(at point: CGPoint) {
        if let selection = activeSelection,
           let handle = selectionHandle(at: point, within: selection.bounds) {
            prepareSelectionPreview(for: selection)
            lassoInteraction = .resizing(handle: handle, selection: selection)
            return
        }

        if let selection = activeSelection,
           selection.bounds.insetBy(dx: -20, dy: -20).contains(point) {
            prepareSelectionPreview(for: selection)
            lassoInteraction = .moving(startPoint: point, selection: selection)
            return
        }

        cancelLassoInteraction(keepSelection: false)
        activeLassoPoints = [point]
        lassoInteraction = .drawingPath
        lassoPreviewLayer.isHidden = false
        updateLassoPreviewPath()
    }

    private func updateLassoInteraction(to point: CGPoint) {
        switch lassoInteraction {
        case .drawingPath:
            guard let last = activeLassoPoints.last else {
                activeLassoPoints = [point]
                updateLassoPreviewPath()
                return
            }
            guard hypot(last.x - point.x, last.y - point.y) > 3 else { return }
            activeLassoPoints.append(point)
            updateLassoPreviewPath()
        case let .moving(startPoint, selection):
            let translation = CGSize(width: point.x - startPoint.x, height: point.y - startPoint.y)
            previewSelection(
                selection,
                transformedBounds: selection.bounds.offsetBy(dx: translation.width, dy: translation.height)
            )
        case let .resizing(handle, selection):
            previewSelection(
                selection,
                transformedBounds: LassoGeometry.proportionalResizeRect(
                    from: selection.bounds,
                    handle: handle,
                    location: point
                )
            )
        case .none:
            break
        }
    }

    private func finishLassoInteraction() {
        defer { lassoInteraction = nil }

        switch lassoInteraction {
        case .drawingPath:
            let selectedIndexes = drawing.strokes.enumerated().compactMap { index, stroke -> Int? in
                let points = denormalizedPoints(for: stroke)
                return LassoGeometry.strokeIntersectsPolygon(stroke: points, polygon: activeLassoPoints) ? index : nil
            }

            activeLassoPoints.removeAll(keepingCapacity: true)
            lassoPreviewLayer.path = nil
            lassoPreviewLayer.isHidden = true

            guard let selection = buildSelection(from: selectedIndexes) else {
                cancelLassoInteraction(keepSelection: false)
                return
            }
            activeSelection = selection
            updateSelectionOverlay()
        case let .moving(_, selection), let .resizing(_, selection):
            commitPreviewSelection(for: selection)
        case .none:
            break
        }
    }

    private func cancelLassoInteraction(keepSelection: Bool) {
        activeLassoPoints.removeAll(keepingCapacity: true)
        lassoPreviewLayer.path = nil
        lassoPreviewLayer.isHidden = true
        lassoInteraction = nil
        clearSelectionPreview()

        if !keepSelection {
            activeSelection = nil
            selectionOutlineLayer.path = nil
            selectionOutlineLayer.isHidden = true
            selectionHandleLayers.values.forEach {
                $0.path = nil
                $0.isHidden = true
            }
            selectionActionsView.isHidden = true
        }
    }

    private func updateLassoPreviewPath() {
        guard activeLassoPoints.count >= 2 else { return }
        let path = UIBezierPath()
        path.move(to: activeLassoPoints[0])
        for point in activeLassoPoints.dropFirst() {
            path.addLine(to: point)
        }
        lassoPreviewLayer.path = path.cgPath
    }

    private func buildSelection(from indexes: [Int]) -> LassoSelection? {
        let uniqueIndexes = Array(Set(indexes)).sorted()
        guard !uniqueIndexes.isEmpty else { return nil }

        let strokes = uniqueIndexes.compactMap { index -> InkStroke? in
            drawing.strokes.indices.contains(index) ? drawing.strokes[index] : nil
        }
        let pointGroups = strokes.map { denormalizedPoints(for: $0) }

        guard strokes.count == uniqueIndexes.count,
              let bounds = LassoGeometry.boundingRect(for: pointGroups) else {
            return nil
        }

        return LassoSelection(strokeIndexes: uniqueIndexes, sourceStrokes: strokes, bounds: bounds.insetBy(dx: -8, dy: -8))
    }

    private func updateSelectionOverlay() {
        guard let selection = activeSelection else {
            selectionOutlineLayer.path = nil
            selectionOutlineLayer.isHidden = true
            selectionHandleLayers.values.forEach {
                $0.path = nil
                $0.isHidden = true
            }
            selectionActionsView.isHidden = true
            return
        }

        let displayBounds = currentSelectionBounds(defaultingTo: selection.bounds)
        selectionOutlineLayer.path = UIBezierPath(rect: displayBounds).cgPath
        selectionOutlineLayer.isHidden = false

        for handle in LassoSelectionHandle.allCases {
            guard let handleLayer = selectionHandleLayers[handle] else { continue }
            let center = handle.point(in: displayBounds)
            let handleRect = CGRect(x: center.x - 11, y: center.y - 11, width: 22, height: 22)
            handleLayer.path = UIBezierPath(ovalIn: handleRect).cgPath
            handleLayer.isHidden = false
        }

        let actionsWidth: CGFloat = 240
        let actionsHeight: CGFloat = 46
        let clampedX = min(max(displayBounds.midX - (actionsWidth * 0.5), 12), max(bounds.width - actionsWidth - 12, 12))
        let preferredY = displayBounds.minY - actionsHeight - 12
        let fallbackY = displayBounds.maxY + 12
        let originY = preferredY > 8 ? preferredY : min(fallbackY, bounds.height - actionsHeight - 12)
        selectionActionsView.frame = CGRect(x: clampedX, y: originY, width: actionsWidth, height: actionsHeight)
        selectionActionsView.isHidden = false
    }

    private func selectionHandle(at point: CGPoint, within rect: CGRect) -> LassoSelectionHandle? {
        LassoSelectionHandle.allCases.first { handle in
            let center = handle.point(in: rect)
            return hypot(center.x - point.x, center.y - point.y) <= 24
        }
    }

    private func prepareSelectionPreview(for selection: LassoSelection) {
        clearSelectionPreview()
        previewSelectionPoints.removeAll(keepingCapacity: true)

        for index in selection.strokeIndexes {
            guard strokeLayers.indices.contains(index) else { continue }
            strokeLayers[index].opacity = 0.18
        }

        for stroke in selection.sourceStrokes {
            let previewLayer = makeStrokeLayer(color: stroke.color.uiColor, lineWidth: stroke.width)
            previewLayer.zPosition = 9_100
            previewStrokeLayers.append(previewLayer)
            layer.addSublayer(previewLayer)
        }
    }

    private func clearSelectionPreview() {
        previewSelectionPoints.removeAll(keepingCapacity: true)
        previewStrokeLayers.forEach { $0.removeFromSuperlayer() }
        previewStrokeLayers.removeAll(keepingCapacity: true)

        for index in activeSelection?.strokeIndexes ?? [] {
            guard strokeLayers.indices.contains(index) else { continue }
            strokeLayers[index].opacity = 1.0
        }
    }

    private func previewSelection(_ selection: LassoSelection, transformedBounds: CGRect) {
        for (offset, stroke) in selection.sourceStrokes.enumerated() {
            guard previewStrokeLayers.indices.contains(offset) else { continue }
            let sourcePoints = denormalizedPoints(for: stroke)
            let transformedPoints = LassoGeometry.scaled(
                points: sourcePoints,
                from: selection.bounds,
                to: transformedBounds
            )
            previewSelectionPoints[selection.strokeIndexes[offset]] = transformedPoints
            previewStrokeLayers[offset].path = previewPath(for: transformedPoints).cgPath
            previewStrokeLayers[offset].lineWidth = stroke.width
        }

        activeSelection = LassoSelection(
            strokeIndexes: selection.strokeIndexes,
            sourceStrokes: selection.sourceStrokes,
            bounds: transformedBounds
        )
        updateSelectionOverlay()
    }

    private func currentSelectionBounds(defaultingTo selectionBounds: CGRect) -> CGRect {
        if let previewBounds = LassoGeometry.boundingRect(for: Array(previewSelectionPoints.values)) {
            return previewBounds.insetBy(dx: -8, dy: -8)
        }
        return selectionBounds
    }

    private func commitPreviewSelection(for selection: LassoSelection) {
        guard !previewSelectionPoints.isEmpty else {
            clearSelectionPreview()
            updateSelectionOverlay()
            return
        }

        var updatedDrawing = drawing
        for (offset, index) in selection.strokeIndexes.enumerated() {
            guard updatedDrawing.strokes.indices.contains(index),
                  let transformedPoints = previewSelectionPoints[index] else { continue }
            let originalStroke = selection.sourceStrokes[offset]
            let transformedInkPoints = zip(originalStroke.points, transformedPoints).map { originalPoint, transformedPoint in
                InkPoint(
                    x: min(max(transformedPoint.x / max(bounds.width, 1), 0), 1),
                    y: min(max(transformedPoint.y / max(bounds.height, 1), 0), 1),
                    force: originalPoint.force
                )
            }
            updatedDrawing.strokes[index] = InkStroke(
                points: transformedInkPoints,
                width: originalStroke.width,
                color: originalStroke.color,
                blendMode: originalStroke.blendMode
            )
        }

        clearSelectionPreview()
        drawing = updatedDrawing
        rebuildStrokeLayers()
        if let refreshedSelection = buildSelection(from: selection.strokeIndexes) {
            activeSelection = refreshedSelection
            updateSelectionOverlay()
        } else {
            cancelLassoInteraction(keepSelection: false)
        }
        onDrawingChanged?(drawing)
    }

    @objc
    private func handleDuplicateSelection() {
        guard let selection = activeSelection else { return }
        let pointGroups = selection.sourceStrokes.map { denormalizedPoints(for: $0) }
        let translatedGroups = LassoGeometry.duplicated(pointGroups: pointGroups)

        var duplicatedStrokes: [InkStroke] = []
        duplicatedStrokes.reserveCapacity(selection.sourceStrokes.count)

        for (offset, originalStroke) in selection.sourceStrokes.enumerated() {
            let translatedPoints = translatedGroups[offset]
            let transformedInkPoints = zip(originalStroke.points, translatedPoints).map { originalPoint, transformedPoint in
                InkPoint(
                    x: min(max(transformedPoint.x / max(bounds.width, 1), 0), 1),
                    y: min(max(transformedPoint.y / max(bounds.height, 1), 0), 1),
                    force: originalPoint.force
                )
            }
            duplicatedStrokes.append(
                InkStroke(
                    points: transformedInkPoints,
                    width: originalStroke.width,
                    color: originalStroke.color,
                    blendMode: originalStroke.blendMode
                )
            )
        }

        let newIndexes = Array(drawing.strokes.count..<(drawing.strokes.count + duplicatedStrokes.count))
        drawing.strokes.append(contentsOf: duplicatedStrokes)
        rebuildStrokeLayers()
        activeSelection = buildSelection(from: newIndexes)
        updateSelectionOverlay()
        onDrawingChanged?(drawing)
    }

    @objc
    private func handleDeleteSelection() {
        guard let selection = activeSelection else { return }
        drawing.strokes = LassoGeometry.removing(items: drawing.strokes, at: selection.strokeIndexes)
        cancelLassoInteraction(keepSelection: false)
        rebuildStrokeLayers()
        onDrawingChanged?(drawing)
    }

    private func pencilSamples(from gesture: PencilStrokeGestureRecognizer) -> [(point: CGPoint, force: CGFloat)] {
        let touches = gesture.sampledTouches.isEmpty
            ? (gesture.latestTouch.map { [$0] } ?? [])
            : gesture.sampledTouches
        return touches.map { touch in
            let force = touch.type == .pencil ? max(touch.force, 0.0) : 1.0
            return (touch.preciseLocation(in: self), force)
        }
    }

    private func beginStroke(at point: CGPoint, force: CGFloat) {
        activeStrokePoints.removeAll(keepingCapacity: true)
        let normalized = normalizedPoint(for: point, force: force)
        activeStrokePoints.append(normalized)

        activeStrokeWidth = tool.mode == .pen
            ? max(tool.width * pressureFactor(for: force), 0.4)
            : tool.width
        activeStrokeColor = InkColorComponents(color: tool.color)
        activeBlendMode = tool.blendMode

        let strokeLayer = makeStrokeLayer(
            color: activeStrokeColor.uiColor,
            lineWidth: activeStrokeWidth
        )
        layer.addSublayer(strokeLayer)
        activeStrokeLayer = strokeLayer
        updateActiveStrokePath()
    }

    private func appendStroke(at point: CGPoint, force: CGFloat) {
        guard let activeStrokeLayer else {
            beginStroke(at: point, force: force)
            return
        }

        let normalized = normalizedPoint(for: point, force: force)
        if let last = activeStrokePoints.last {
            let dx = (last.x - normalized.x) * max(bounds.width, 1)
            let dy = (last.y - normalized.y) * max(bounds.height, 1)
            if hypot(dx, dy) < 0.2 {
                return
            }
        }

        activeStrokePoints.append(normalized)
        if tool.mode == .pen {
            let updatedWidth = max(tool.width * pressureFactor(for: force), 0.4)
            activeStrokeWidth = (activeStrokeWidth * 0.7) + (updatedWidth * 0.3)
            activeStrokeLayer.lineWidth = activeStrokeWidth
        }

        updateActiveStrokePath()
    }

    private func finishStroke() {
        guard let strokeLayer = activeStrokeLayer, !activeStrokePoints.isEmpty else {
            discardActiveStroke()
            return
        }

        let stroke = InkStroke(
            points: activeStrokePoints,
            width: activeStrokeWidth,
            color: activeStrokeColor,
            blendMode: activeBlendMode
        )
        drawing.strokes.append(stroke)
        strokeLayers.append(strokeLayer)
        onDrawingChanged?(drawing)

        activeStrokeLayer = nil
        activeStrokePoints.removeAll(keepingCapacity: true)
    }

    private func discardActiveStroke() {
        activeStrokeLayer?.removeFromSuperlayer()
        activeStrokeLayer = nil
        activeStrokePoints.removeAll(keepingCapacity: true)
    }

    private func erase(at point: CGPoint) {
        switch tool.eraserMode {
        case .stroke:
            eraseByStroke(at: point)
        case .classic:
            eraseByClassic(at: point)
        }
    }

    private func eraseByStroke(at point: CGPoint) {
        guard !drawing.strokes.isEmpty, drawing.strokes.count == strokeLayers.count else { return }

        let radius = tool.eraserRadius
        var keptStrokes: [InkStroke] = []
        var keptLayers: [CAShapeLayer] = []
        var removedAny = false

        for (index, stroke) in drawing.strokes.enumerated() {
            if strokeIntersectsEraser(stroke, point: point, radius: radius) {
                strokeLayers[index].removeFromSuperlayer()
                removedAny = true
                continue
            }
            keptStrokes.append(stroke)
            keptLayers.append(strokeLayers[index])
        }

        guard removedAny else { return }

        drawing.strokes = keptStrokes
        strokeLayers = keptLayers
        onDrawingChanged?(drawing)
    }

    private func eraseByClassic(at point: CGPoint) {
        guard !drawing.strokes.isEmpty else { return }

        let radius = tool.eraserRadius
        var updatedStrokes: [InkStroke] = []
        updatedStrokes.reserveCapacity(drawing.strokes.count)
        var removedAny = false

        for stroke in drawing.strokes {
            let segments = strokeSegments(afterErasing: stroke, at: point, radius: radius)
            if segments.count != 1 || segments.first?.points.count != stroke.points.count {
                removedAny = true
            }
            updatedStrokes.append(contentsOf: segments)
        }

        guard removedAny else { return }

        drawing.strokes = updatedStrokes
        rebuildStrokeLayers()
        onDrawingChanged?(drawing)
    }

    private func strokeSegments(afterErasing stroke: InkStroke, at point: CGPoint, radius: CGFloat) -> [InkStroke] {
        guard !stroke.points.isEmpty else { return [] }

        let threshold = max(radius + stroke.width * 0.5, radius)
        let thresholdSquared = threshold * threshold

        var segments: [InkStroke] = []
        var segmentPoints: [InkPoint] = []

        for sample in stroke.points {
            let candidate = denormalizedPoint(for: sample)
            let dx = candidate.x - point.x
            let dy = candidate.y - point.y
            let shouldErase = (dx * dx) + (dy * dy) <= thresholdSquared

            if shouldErase {
                if !segmentPoints.isEmpty {
                    segments.append(
                        InkStroke(
                            points: segmentPoints,
                            width: stroke.width,
                            color: stroke.color,
                            blendMode: stroke.blendMode
                        )
                    )
                    segmentPoints.removeAll(keepingCapacity: true)
                }
            } else {
                segmentPoints.append(sample)
            }
        }

        if !segmentPoints.isEmpty {
            segments.append(
                InkStroke(
                    points: segmentPoints,
                    width: stroke.width,
                    color: stroke.color,
                    blendMode: stroke.blendMode
                )
            )
        }

        return segments
    }

    private func strokeIntersectsEraser(_ stroke: InkStroke, point: CGPoint, radius: CGFloat) -> Bool {
        guard !stroke.points.isEmpty else { return false }
        let threshold = max(radius + stroke.width * 0.5, radius)
        let thresholdSquared = threshold * threshold

        for sample in stroke.points {
            let candidate = denormalizedPoint(for: sample)
            let dx = candidate.x - point.x
            let dy = candidate.y - point.y
            if (dx * dx) + (dy * dy) <= thresholdSquared {
                return true
            }
        }
        return false
    }

    private func rebuildStrokeLayers() {
        activeStrokeLayer?.removeFromSuperlayer()
        activeStrokeLayer = nil
        activeStrokePoints.removeAll(keepingCapacity: true)

        strokeLayers.forEach { $0.removeFromSuperlayer() }
        strokeLayers.removeAll(keepingCapacity: true)

        for stroke in drawing.strokes {
            let layer = makeStrokeLayer(
                color: stroke.color.uiColor,
                lineWidth: stroke.width
            )
            layer.path = strokePath(for: stroke).cgPath
            self.layer.addSublayer(layer)
            strokeLayers.append(layer)
        }
        updateSelectionOverlay()
    }

    private func rebuildStrokePaths() {
        guard drawing.strokes.count == strokeLayers.count else {
            rebuildStrokeLayers()
            return
        }

        for (index, stroke) in drawing.strokes.enumerated() {
            strokeLayers[index].path = strokePath(for: stroke).cgPath
            strokeLayers[index].lineWidth = stroke.width
        }

        if activeStrokeLayer != nil {
            updateActiveStrokePath()
        }
        updateSelectionOverlay()
    }

    private func updateActiveStrokePath() {
        guard let activeStrokeLayer else { return }
        let stroke = InkStroke(
            points: activeStrokePoints,
            width: activeStrokeWidth,
            color: activeStrokeColor,
            blendMode: activeBlendMode
        )
        activeStrokeLayer.path = strokePath(for: stroke).cgPath
    }

    private func makeStrokeLayer(color: UIColor, lineWidth: CGFloat) -> CAShapeLayer {
        let strokeLayer = CAShapeLayer()
        strokeLayer.fillColor = nil
        strokeLayer.strokeColor = color.cgColor
        strokeLayer.lineWidth = lineWidth
        strokeLayer.lineCap = .round
        strokeLayer.lineJoin = .round
        strokeLayer.contentsScale = UIScreen.main.scale
        strokeLayer.shouldRasterize = false
        strokeLayer.drawsAsynchronously = false
        return strokeLayer
    }

    private func denormalizedPoints(for stroke: InkStroke) -> [CGPoint] {
        stroke.points.map { denormalizedPoint(for: $0) }
    }

    private func strokePath(for stroke: InkStroke) -> UIBezierPath {
        previewPath(for: denormalizedPoints(for: stroke))
    }

    private func previewPath(for points: [CGPoint]) -> UIBezierPath {
        if points.count <= 1 {
            let path = UIBezierPath()
            let center = points.first ?? .zero
            // A tiny segment with round caps renders as a solid dot.
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + 0.01, y: center.y + 0.01))
            return path
        }

        let path = UIBezierPath()
        path.move(to: points[0])

        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }

        for index in 1..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let midpoint = CGPoint(
                x: (current.x + next.x) * 0.5,
                y: (current.y + next.y) * 0.5
            )
            path.addQuadCurve(to: midpoint, controlPoint: current)
        }

        if let last = points.last {
            path.addLine(to: last)
        }
        return path
    }

    private func normalizedPoint(for point: CGPoint, force: CGFloat) -> InkPoint {
        guard bounds.width > 0, bounds.height > 0 else {
            return InkPoint(x: 0, y: 0, force: 1.0)
        }
        let x = min(max(point.x / bounds.width, 0), 1)
        let y = min(max(point.y / bounds.height, 0), 1)
        return InkPoint(x: x, y: y, force: max(force, 0.0))
    }

    private func denormalizedPoint(for point: InkPoint) -> CGPoint {
        CGPoint(
            x: point.x * bounds.width,
            y: point.y * bounds.height
        )
    }

    private func pressureFactor(for force: CGFloat) -> CGFloat {
        let normalizedForce = min(max(force, 0.5), 2.0)
        return 0.9 + (normalizedForce - 1.0) * 0.12
    }
}

private final class PageView: UIView {
    private let pdfPageView = TiledPDFPageView()
    let canvasView = VectorInkCanvasView()
    private(set) var isRendered = false
    let pageIndex: Int
    
    init(pageIndex: Int) {
        self.pageIndex = pageIndex
        super.init(frame: .zero)
        
        pdfPageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pdfPageView)

        canvasView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(canvasView)

        NSLayoutConstraint.activate([
            pdfPageView.topAnchor.constraint(equalTo: topAnchor),
            pdfPageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfPageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfPageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            canvasView.topAnchor.constraint(equalTo: topAnchor),
            canvasView.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func render(pdfPage: PDFPage) {
        if isRendered { return }
        isRendered = true
        pdfPageView.setPage(pdfPage)
    }

    func renderBlank(pageBounds: CGRect) {
        if isRendered { return }
        isRendered = true
        pdfPageView.setBlankPage(bounds: pageBounds)
    }
    
    func clear() {
        if !isRendered { return }
        isRendered = false
        pdfPageView.setPage(nil)
    }
}

// MARK: - PageAnnotationViewController (Core UIKit Controller)

class PageAnnotationViewController: UIViewController, UIScrollViewDelegate {
    private struct PageDescriptor {
        enum Kind {
            case pdf(index: Int)
            case blank
        }

        let kind: Kind
        let pageBounds: CGRect
    }

    enum ScrollDirectionMode {
        case horizontal
        case vertical
    }

    private enum ZoomIntent {
        case turnPages
        case panInspect
    }

    private enum SnapAlignment {
        case centered
        case topLeading
    }

    private struct DrawingHistoryStep {
        let pageIndex: Int
        let previous: InkPageDrawing
        let updated: InkPageDrawing
    }

    private struct SavePageDescriptor: Sendable {
        let pdfPageIndex: Int?
        let pageBounds: CGRect
    }
    
    var pdfURL: URL!
    var documentId: UUID!
    var repository: DocumentRepository!
    weak var coordinator: PDFEditorRepresentable.Coordinator?
    var onTypewriterAutoAdvance: ((Int, CGPoint) -> Void)?
    var undoRedoDidChange: ((Bool, Bool) -> Void)?
    var onAutoAppendedBlankPage: (() -> Void)?

    private let scrollView = UIScrollView()
    private let containerView = UIView()
    private var pageViews: [PageView] = []

    // State
    private var pdfDocument: PDFDocument?
    var currentPageIndex: Int = 0
    var isScrollingProgrammatically = false

    private var pageDrawings: [Int: InkPageDrawing] = [:]
    private var legacyDrawings: [Int: PKDrawing] = [:]
    private var pageDescriptors: [PageDescriptor] = []
    private var displayScales: [CGFloat] = []
    private var pageFrames: [CGRect] = []
    private var scrollDirectionMode: ScrollDirectionMode = .horizontal
    private var pendingDoubleTapRecenteringPageIndex: Int?
    private var lastLaidOutViewportSize: CGSize = .zero
    private var undoStack: [DrawingHistoryStep] = []
    private var redoStack: [DrawingHistoryStep] = []
    private var isApplyingHistoryChange = false
    private var lastAutoAppendedBlankPageIndex: Int?

    private var currentTool: InkToolDescriptor = .default
    private let pagePadding: CGFloat = 20.0
    private let zoomedOutThresholdScale: CGFloat = 1.05
    private let zoomedInFlingVelocityThreshold: CGFloat = 1.15
    private let zoomedInBoundaryPullThreshold: CGFloat = 72.0
    private let zoomedInEmptyViewportSnapThreshold: CGFloat = 0.5

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        pdfDocument = PDFDocument(url: pdfURL)
        loadSavedDrawings()

        setupScrollView()
        setupPencilSqueezeInteractionIfAvailable()
        
        // Report total pages mapping
        coordinator?.pageDidChange(to: 0, total: pdfDocument?.pageCount ?? 1)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.height > 0, view.bounds.width > 0 else { return }

        // If the view just got bounds, setup pages
        if pageViews.isEmpty {
            setupPages()
            navigateToPage(currentPageIndex, animated: false)
            lastLaidOutViewportSize = view.bounds.size
            return
        }

        if lastLaidOutViewportSize != view.bounds.size {
            relayoutPages(preservingPageIndex: currentPageIndex)
            lastLaidOutViewportSize = view.bounds.size
        }
    }
    // MARK: - Setup

    private func setupScrollView() {
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.decelerationRate = .fast
        scrollView.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        view.addSubview(scrollView)
        applyScrollDirectionConfiguration()
        installDoubleTapToFitGesture()

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        // Rely on auto resizing to allow us to define exact frames manually.
        scrollView.addSubview(containerView)
    }

    private func applyScrollDirectionConfiguration() {
        switch scrollDirectionMode {
        case .horizontal:
            scrollView.alwaysBounceHorizontal = true
            scrollView.alwaysBounceVertical = false
        case .vertical:
            scrollView.alwaysBounceHorizontal = false
            scrollView.alwaysBounceVertical = true
        }
        scrollView.isDirectionalLockEnabled = true
    }

    private func installDoubleTapToFitGesture() {
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTapToFit(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.numberOfTouchesRequired = 1
        doubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.addGestureRecognizer(doubleTap)
    }

    private func setupPencilSqueezeInteractionIfAvailable() {
        guard #available(iOS 17.5, *) else { return }

        let interaction = UIPencilInteraction()
        interaction.delegate = self
        interaction.isEnabled = true
        view.addInteraction(interaction)
    }

    private func setupPages() {
        guard let pdf = pdfDocument, pdf.pageCount > 0 else { return }

        pageViews.forEach { $0.removeFromSuperview() }
        pageViews.removeAll(keepingCapacity: true)
        pageDescriptors.removeAll(keepingCapacity: true)
        displayScales.removeAll(keepingCapacity: true)
        pageFrames.removeAll(keepingCapacity: true)

        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            let descriptor = PageDescriptor(
                kind: .pdf(index: i),
                pageBounds: page.bounds(for: .mediaBox)
            )
            let canvasSize = displayedCanvasSize(for: descriptor.pageBounds)
            let initialDrawing = initialDrawingForPage(index: i, canvasSize: canvasSize)
            _ = appendPage(descriptor: descriptor, drawing: initialDrawing)
        }

        let highestDrawingPage = max(pageDrawings.keys.max() ?? -1, legacyDrawings.keys.max() ?? -1)
        if highestDrawingPage >= pageViews.count {
            let pagesToAdd = highestDrawingPage - pageViews.count + 1
            for _ in 0..<pagesToAdd {
                _ = appendBlankPage()
            }
        }

        updateContainerLayout()
        lastLaidOutViewportSize = view.bounds.size

        scrollView.minimumZoomScale = 1.0 // Fully zoomed-out fits perfectly inside the screen limits
        scrollView.maximumZoomScale = 5.0
        scrollView.zoomScale = 1.0

        currentPageIndex = min(max(currentPageIndex, 0), max(pageViews.count - 1, 0))
        updateVisiblePages()
        coordinator?.pageDidChange(to: currentPageIndex, total: pageViews.count)
        reportUndoRedoState()
    }

    private func displayedCanvasSize(for pageBounds: CGRect) -> CGSize {
        let bounds = normalizedPageBounds(pageBounds)
        let viewWidth = max(view.bounds.width, 1.0)
        let viewHeight = max(view.bounds.height, 1.0)
        let scale = min(viewWidth / bounds.width, viewHeight / bounds.height)
        return CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    private func initialDrawingForPage(index: Int, canvasSize: CGSize) -> InkPageDrawing {
        if let drawing = pageDrawings[index] {
            return drawing
        }
        if let legacyDrawing = legacyDrawings[index] {
            let migrated = migrateLegacyDrawing(legacyDrawing, canvasSize: canvasSize)
            pageDrawings[index] = migrated
            return migrated
        }
        return InkPageDrawing()
    }

    @discardableResult
    private func appendPage(descriptor: PageDescriptor, drawing: InkPageDrawing) -> Int {
        let index = pageViews.count
        let bounds = normalizedPageBounds(descriptor.pageBounds)
        let viewWidth = max(view.bounds.width, 1.0)
        let viewHeight = max(view.bounds.height, 1.0)
        let scale = min(viewWidth / bounds.width, viewHeight / bounds.height)
        let scaledWidth = bounds.width * scale
        let scaledHeight = bounds.height * scale
        let frame = pageFrameForIndex(
            index,
            scaledWidth: scaledWidth,
            scaledHeight: scaledHeight
        )

        let pageView = PageView(pageIndex: index)
        pageView.frame = frame
        pageView.canvasView.tool = currentTool
        pageView.canvasView.setDrawing(drawing)
        pageView.canvasView.onDrawingChanged = { [weak self] updatedDrawing in
            self?.handleDrawingChanged(at: index, updatedDrawing: updatedDrawing)
        }

        containerView.addSubview(pageView)
        pageViews.append(pageView)
        pageDescriptors.append(PageDescriptor(kind: descriptor.kind, pageBounds: bounds))
        displayScales.append(scale)
        pageFrames.append(frame)
        pageDrawings[index] = drawing
        reportUndoRedoState()
        return index
    }

    @discardableResult
    private func appendBlankPage() -> Int {
        let newIndex = pageViews.count
        let bounds = pageDescriptors.last?.pageBounds ?? fallbackPageBounds()
        let descriptor = PageDescriptor(kind: .blank, pageBounds: bounds)
        let canvasSize = displayedCanvasSize(for: bounds)
        let drawing = initialDrawingForPage(index: newIndex, canvasSize: canvasSize)
        let appendedIndex = appendPage(descriptor: descriptor, drawing: drawing)
        updateContainerLayout()
        return appendedIndex
    }

    private func normalizedPageBounds(_ bounds: CGRect) -> CGRect {
        if bounds.width > 0.0, bounds.height > 0.0 {
            return bounds
        }
        return fallbackPageBounds()
    }

    nonisolated private static func normalizedPageBounds(_ bounds: CGRect) -> CGRect {
        if bounds.width > 0.0, bounds.height > 0.0 {
            return bounds
        }
        return CGRect(x: 0, y: 0, width: 612, height: 792)
    }

    private func fallbackPageBounds() -> CGRect {
        if let page = pdfDocument?.page(at: 0) {
            let bounds = page.bounds(for: .mediaBox)
            if bounds.width > 0.0, bounds.height > 0.0 {
                return bounds
            }
        }
        return CGRect(x: 0, y: 0, width: 612, height: 792)
    }

    private func updateContainerLayout() {
        let viewWidth = max(view.bounds.width, 1.0)
        let viewHeight = max(view.bounds.height, 1.0)
        switch scrollDirectionMode {
        case .horizontal:
            let slotWidth = viewWidth + pagePadding
            let contentWidth = max(0, CGFloat(pageViews.count) * slotWidth - pagePadding)
            containerView.frame = CGRect(x: 0, y: 0, width: contentWidth, height: viewHeight)
        case .vertical:
            let slotHeight = viewHeight + pagePadding
            let contentHeight = max(0, CGFloat(pageViews.count) * slotHeight - pagePadding)
            containerView.frame = CGRect(x: 0, y: 0, width: viewWidth, height: contentHeight)
        }
        scrollView.contentSize = containerView.bounds.size
    }

    private func pageFrameForIndex(_ index: Int, scaledWidth: CGFloat, scaledHeight: CGFloat) -> CGRect {
        let viewWidth = max(view.bounds.width, 1.0)
        let viewHeight = max(view.bounds.height, 1.0)
        let xOffset = (viewWidth - scaledWidth) * 0.5
        let yOffset = (viewHeight - scaledHeight) * 0.5
        switch scrollDirectionMode {
        case .horizontal:
            let slotWidth = viewWidth + pagePadding
            return CGRect(
                x: CGFloat(index) * slotWidth + xOffset,
                y: yOffset,
                width: scaledWidth,
                height: scaledHeight
            )
        case .vertical:
            let slotHeight = viewHeight + pagePadding
            return CGRect(
                x: xOffset,
                y: CGFloat(index) * slotHeight + yOffset,
                width: scaledWidth,
                height: scaledHeight
            )
        }
    }

    private func relayoutPages(preservingPageIndex: Int) {
        guard !pageViews.isEmpty else {
            updateContainerLayout()
            return
        }

        let existingZoomScale = max(scrollView.zoomScale, 0.001)
        let targetPage = min(max(preservingPageIndex, 0), pageViews.count - 1)

        for index in pageViews.indices {
            guard pageDescriptors.indices.contains(index) else { continue }
            let bounds = pageDescriptors[index].pageBounds
            let viewWidth = max(view.bounds.width, 1.0)
            let viewHeight = max(view.bounds.height, 1.0)
            let scale = min(viewWidth / bounds.width, viewHeight / bounds.height)
            let frame = pageFrameForIndex(
                index,
                scaledWidth: bounds.width * scale,
                scaledHeight: bounds.height * scale
            )
            pageViews[index].frame = frame
            if pageFrames.indices.contains(index) {
                pageFrames[index] = frame
            } else {
                pageFrames.append(frame)
            }
            if displayScales.indices.contains(index) {
                displayScales[index] = scale
            } else {
                displayScales.append(scale)
            }
        }

        updateContainerLayout()
        let alignedOffset = targetContentOffsetForPage(
            targetPage,
            zoomScale: existingZoomScale,
            alignment: zoomIntent(for: existingZoomScale) == .turnPages ? zoomedOutSnapAlignment() : .topLeading
        )
        scrollView.contentOffset = alignedOffset
        updateVisiblePages()
    }

    func setTool(
        _ tool: AnnotationTool,
        color: AnnotationInkColor,
        width: CGFloat,
        highlighterOpacity: CGFloat,
        eraserMode: EraserMode
    ) {
        currentTool = InkToolDescriptor(
            annotationTool: tool,
            inkColor: color,
            width: width,
            highlighterOpacity: highlighterOpacity,
            eraserMode: eraserMode
        )
        pageViews.forEach { $0.canvasView.tool = currentTool }
    }

    // MARK: - Scrolling, Visibility, and Zooming

    func setScrollDirectionMode(_ mode: ScrollDirectionMode) {
        guard mode != scrollDirectionMode else { return }
        scrollDirectionMode = mode
        applyScrollDirectionConfiguration()
        relayoutPages(preservingPageIndex: currentPageIndex)
    }

    private func zoomIntent(for zoomScale: CGFloat) -> ZoomIntent {
        zoomScale <= zoomedOutThresholdScale ? .turnPages : .panInspect
    }

    private func primaryAxisCenter(in rect: CGRect) -> CGFloat {
        switch scrollDirectionMode {
        case .horizontal:
            return rect.midX
        case .vertical:
            return rect.midY
        }
    }

    private func primaryAxisCenter(for frame: CGRect) -> CGFloat {
        switch scrollDirectionMode {
        case .horizontal:
            return frame.midX
        case .vertical:
            return frame.midY
        }
    }

    private func primaryAxisVelocity(_ velocity: CGPoint) -> CGFloat {
        switch scrollDirectionMode {
        case .horizontal:
            return velocity.x
        case .vertical:
            return velocity.y
        }
    }

    private func visibleRect(for contentOffset: CGPoint, zoomScale: CGFloat) -> CGRect {
        let normalizedScale = max(zoomScale, 0.001)
        return CGRect(
            x: contentOffset.x / normalizedScale,
            y: contentOffset.y / normalizedScale,
            width: scrollView.bounds.width / normalizedScale,
            height: scrollView.bounds.height / normalizedScale
        )
    }

    private func clampToScrollBounds(_ offset: CGPoint) -> CGPoint {
        let maxX = max(scrollView.contentSize.width - scrollView.bounds.width, 0)
        let maxY = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
        return CGPoint(
            x: min(max(offset.x, 0), maxX),
            y: min(max(offset.y, 0), maxY)
        )
    }

    private func dominantPageIndex(in visibleRect: CGRect) -> Int {
        guard !pageFrames.isEmpty else { return 0 }
        var bestIndex = currentPageIndex
        var bestArea: CGFloat = -1
        for (index, frame) in pageFrames.enumerated() {
            let overlap = frame.intersection(visibleRect)
            let area = max(overlap.width, 0) * max(overlap.height, 0)
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func closestPageIndex(to visibleRect: CGRect) -> Int {
        guard !pageFrames.isEmpty else { return 0 }
        let targetCenter = primaryAxisCenter(in: visibleRect)
        var bestIndex = currentPageIndex
        var minDistance = CGFloat.greatestFiniteMagnitude
        for (index, frame) in pageFrames.enumerated() {
            let distance = abs(primaryAxisCenter(for: frame) - targetCenter)
            if distance < minDistance {
                minDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func pageCoverageInVisibleRect(pageIndex: Int, visibleRect: CGRect) -> CGFloat {
        guard pageFrames.indices.contains(pageIndex) else { return 0 }
        let overlap = pageFrames[pageIndex].intersection(visibleRect)
        let overlapArea = max(overlap.width, 0) * max(overlap.height, 0)
        let visibleArea = max(visibleRect.width * visibleRect.height, 1)
        return overlapArea / visibleArea
    }

    private func zoomedOutSnapAlignment() -> SnapAlignment {
        switch scrollDirectionMode {
        case .horizontal:
            return .centered
        case .vertical:
            return .topLeading
        }
    }

    private func targetContentOffsetForPage(_ index: Int, zoomScale: CGFloat, alignment: SnapAlignment) -> CGPoint {
        guard pageFrames.indices.contains(index) else { return .zero }
        let frame = pageFrames[index]
        let normalizedScale = max(zoomScale, 0.001)
        let viewportWidth = scrollView.bounds.width / normalizedScale
        let viewportHeight = scrollView.bounds.height / normalizedScale

        let contentX: CGFloat
        let contentY: CGFloat
        switch alignment {
        case .centered:
            contentX = frame.midX - viewportWidth * 0.5
            contentY = frame.midY - viewportHeight * 0.5
        case .topLeading:
            switch scrollDirectionMode {
            case .horizontal:
                contentX = frame.minX
                contentY = frame.midY - viewportHeight * 0.5
            case .vertical:
                contentX = frame.midX - viewportWidth * 0.5
                contentY = frame.minY
            }
        }

        let scaledOffset = CGPoint(x: contentX * normalizedScale, y: contentY * normalizedScale)
        return clampToScrollBounds(scaledOffset)
    }

    private func clampedOffset(_ proposedOffset: CGPoint, withinPage pageIndex: Int, zoomScale: CGFloat) -> CGPoint {
        guard pageFrames.indices.contains(pageIndex) else {
            return clampToScrollBounds(proposedOffset)
        }
        let frame = pageFrames[pageIndex]
        let normalizedScale = max(zoomScale, 0.001)
        let viewportWidth = scrollView.bounds.width / normalizedScale
        let viewportHeight = scrollView.bounds.height / normalizedScale
        let proposedX = proposedOffset.x / normalizedScale
        let proposedY = proposedOffset.y / normalizedScale

        let minX = frame.minX
        let maxX = frame.maxX - viewportWidth
        let minY = frame.minY
        let maxY = frame.maxY - viewportHeight

        let resolvedX: CGFloat
        if maxX < minX {
            resolvedX = frame.midX - viewportWidth * 0.5
        } else {
            resolvedX = min(max(proposedX, minX), maxX)
        }

        let resolvedY: CGFloat
        if maxY < minY {
            resolvedY = frame.midY - viewportHeight * 0.5
        } else {
            resolvedY = min(max(proposedY, minY), maxY)
        }

        return clampToScrollBounds(CGPoint(x: resolvedX * normalizedScale, y: resolvedY * normalizedScale))
    }

    private func shouldAllowZoomedInTransition(
        from currentPage: Int,
        to targetPage: Int,
        targetVisibleRect: CGRect,
        velocity: CGPoint,
        zoomScale: CGFloat
    ) -> Bool {
        guard pageFrames.indices.contains(currentPage), targetPage != currentPage else { return false }
        let axisVelocity = primaryAxisVelocity(velocity)
        if abs(axisVelocity) > zoomedInFlingVelocityThreshold {
            return true
        }

        let threshold = zoomedInBoundaryPullThreshold / max(zoomScale, 0.001)
        let currentFrame = pageFrames[currentPage]
        switch scrollDirectionMode {
        case .horizontal:
            if targetPage > currentPage {
                return targetVisibleRect.maxX > currentFrame.maxX + threshold
            }
            return targetVisibleRect.minX < currentFrame.minX - threshold
        case .vertical:
            if targetPage > currentPage {
                return targetVisibleRect.maxY > currentFrame.maxY + threshold
            }
            return targetVisibleRect.minY < currentFrame.minY - threshold
        }
    }

    private func alignToNearestPageIfNeededAfterInteraction() {
        guard !pageFrames.isEmpty else { return }
        let zoomScale = max(scrollView.zoomScale, 0.001)
        guard zoomIntent(for: zoomScale) == .turnPages else { return }

        let currentVisibleRect = visibleRect(for: scrollView.contentOffset, zoomScale: zoomScale)
        // Keep the page that currently occupies most of the viewport and center it precisely.
        let targetPage = dominantPageIndex(in: currentVisibleRect)
        let targetOffset = targetContentOffsetForPage(
            targetPage,
            zoomScale: zoomScale,
            alignment: zoomedOutSnapAlignment()
        )

        let deltaX = abs(targetOffset.x - scrollView.contentOffset.x)
        let deltaY = abs(targetOffset.y - scrollView.contentOffset.y)
        if deltaX > 0.5 || deltaY > 0.5 {
            scrollView.setContentOffset(targetOffset, animated: false)
        }
    }

    private func transitionOffsetForZoomedInPageFlip(
        from currentPage: Int,
        to nextPage: Int,
        proposedOffset: CGPoint,
        zoomScale: CGFloat
    ) -> CGPoint {
        guard pageFrames.indices.contains(nextPage) else {
            return clampToScrollBounds(proposedOffset)
        }
        let normalizedScale = max(zoomScale, 0.001)
        let viewportWidth = scrollView.bounds.width / normalizedScale
        let viewportHeight = scrollView.bounds.height / normalizedScale
        let nextFrame = pageFrames[nextPage]
        let proposedRect = visibleRect(for: proposedOffset, zoomScale: zoomScale)

        var targetX = proposedRect.minX
        var targetY = proposedRect.minY

        switch scrollDirectionMode {
        case .horizontal:
            targetX = nextPage > currentPage ? nextFrame.minX : nextFrame.maxX - viewportWidth
            let yMin = nextFrame.minY
            let yMax = max(nextFrame.maxY - viewportHeight, yMin)
            targetY = min(max(targetY, yMin), yMax)
        case .vertical:
            targetY = nextPage > currentPage ? nextFrame.minY : nextFrame.maxY - viewportHeight
            let xMin = nextFrame.minX
            let xMax = max(nextFrame.maxX - viewportWidth, xMin)
            targetX = min(max(targetX, xMin), xMax)
        }

        let scaled = CGPoint(x: targetX * normalizedScale, y: targetY * normalizedScale)
        return clampToScrollBounds(scaled)
    }
    
    private func updateVisiblePages() {
        let visibleRect = scrollView.convert(scrollView.bounds, to: containerView)
        // Expand visible rect to pre-render adjacent pages lazily
        let prefetchRect: CGRect
        switch scrollDirectionMode {
        case .horizontal:
            prefetchRect = visibleRect.insetBy(dx: -view.bounds.width * 0.5, dy: 0)
        case .vertical:
            prefetchRect = visibleRect.insetBy(dx: 0, dy: -view.bounds.height * 0.5)
        }
        
        var closestPage = currentPageIndex
        var minDistance: CGFloat = .greatestFiniteMagnitude
        let centerAxis = primaryAxisCenter(in: visibleRect)
        var dominantPage = currentPageIndex
        var dominantArea: CGFloat = -1
        
        for (i, pageView) in pageViews.enumerated() {
            if prefetchRect.intersects(pageView.frame) {
                if !pageView.isRendered {
                    renderPage(i, into: pageView)
                }
            } else {
                pageView.clear()
            }
            
            let dist = abs(primaryAxisCenter(for: pageView.frame) - centerAxis)
            if dist < minDistance {
                minDistance = dist
                closestPage = i
            }

            let overlap = pageView.frame.intersection(visibleRect)
            let overlapArea = max(overlap.width, 0) * max(overlap.height, 0)
            if overlapArea > dominantArea {
                dominantArea = overlapArea
                dominantPage = i
            }
        }
        
        let resolvedPage = zoomIntent(for: scrollView.zoomScale) == .turnPages ? closestPage : dominantPage
        if resolvedPage != currentPageIndex {
            currentPageIndex = resolvedPage
            // Update SWIFTUI only if we're not manually scrolling via the API
            if !isScrollingProgrammatically {
                coordinator?.pageDidChange(to: resolvedPage, total: pageViews.count)
            }
        }

        refreshVisibleCanvasResolution()
    }

    private func renderPage(_ index: Int, into pageView: PageView) {
        guard pageDescriptors.indices.contains(index) else { return }
        let descriptor = pageDescriptors[index]
        switch descriptor.kind {
        case let .pdf(pageIndex):
            if let page = pdfDocument?.page(at: pageIndex) {
                pageView.render(pdfPage: page)
            } else {
                pageView.renderBlank(pageBounds: descriptor.pageBounds)
            }
        case .blank:
            pageView.renderBlank(pageBounds: descriptor.pageBounds)
        }
    }

    private func refreshVisibleCanvasResolution(forceRedraw: Bool = false) {
        guard !pageViews.isEmpty else { return }

        let visibleRect = scrollView.convert(scrollView.bounds, to: containerView)
        for pageView in pageViews where pageView.frame.intersects(visibleRect) {
            pageView.canvasView.refreshForZoom(
                zoomScale: scrollView.zoomScale,
                forceRedraw: forceRedraw
            )
        }
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateVisiblePages()
        coordinator?.scrollViewDidScroll()
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isScrollingProgrammatically = false
        alignToNearestPageIfNeededAfterInteraction()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            alignToNearestPageIfNeededAfterInteraction()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        alignToNearestPageIfNeededAfterInteraction()
    }
    
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard !pageViews.isEmpty else { return }

        let zoomScale = max(scrollView.zoomScale, 0.001)
        let currentVisibleRect = visibleRect(for: scrollView.contentOffset, zoomScale: zoomScale)
        let targetVisibleRect = visibleRect(for: targetContentOffset.pointee, zoomScale: zoomScale)
        let currentPage = dominantPageIndex(in: currentVisibleRect)
        let axisVelocity = primaryAxisVelocity(velocity)

        switch zoomIntent(for: zoomScale) {
        case .turnPages:
            var targetPage = closestPageIndex(to: targetVisibleRect)
            if axisVelocity > 0.35 {
                targetPage = min(currentPage + 1, pageViews.count - 1)
            } else if axisVelocity < -0.35 {
                targetPage = max(currentPage - 1, 0)
            }

            if axisVelocity > 0.35 && currentPage == pageViews.count - 1 && targetPage == pageViews.count - 1 {
                let newPageIndex = appendBlankPage()
                lastAutoAppendedBlankPageIndex = newPageIndex
                targetPage = newPageIndex
                coordinator?.pageDidChange(to: newPageIndex, total: pageViews.count)
                onAutoAppendedBlankPage?()
            }

            targetContentOffset.pointee = targetContentOffsetForPage(
                targetPage,
                zoomScale: zoomScale,
                alignment: zoomedOutSnapAlignment()
            )

        case .panInspect:
            let currentPageCoverage = pageCoverageInVisibleRect(pageIndex: currentPage, visibleRect: targetVisibleRect)
            if currentPageCoverage <= zoomedInEmptyViewportSnapThreshold,
               pageFrames.indices.contains(currentPage) {
                let currentFrame = pageFrames[currentPage]
                let direction: Int
                switch scrollDirectionMode {
                case .horizontal:
                    direction = targetVisibleRect.midX >= currentFrame.midX ? 1 : -1
                case .vertical:
                    direction = targetVisibleRect.midY >= currentFrame.midY ? 1 : -1
                }
                let adjacentPage = min(max(currentPage + direction, 0), pageViews.count - 1)
                if adjacentPage != currentPage {
                    targetContentOffset.pointee = transitionOffsetForZoomedInPageFlip(
                        from: currentPage,
                        to: adjacentPage,
                        proposedOffset: targetContentOffset.pointee,
                        zoomScale: zoomScale
                    )
                    return
                }
            }

            let targetPage = dominantPageIndex(in: targetVisibleRect)
            if targetPage == currentPage {
                targetContentOffset.pointee = clampedOffset(
                    targetContentOffset.pointee,
                    withinPage: currentPage,
                    zoomScale: zoomScale
                )
                return
            }

            let allowTransition = shouldAllowZoomedInTransition(
                from: currentPage,
                to: targetPage,
                targetVisibleRect: targetVisibleRect,
                velocity: velocity,
                zoomScale: zoomScale
            )

            if allowTransition {
                let direction = targetPage > currentPage ? 1 : -1
                let nextPage = min(max(currentPage + direction, 0), pageViews.count - 1)
                targetContentOffset.pointee = transitionOffsetForZoomedInPageFlip(
                    from: currentPage,
                    to: nextPage,
                    proposedOffset: targetContentOffset.pointee,
                    zoomScale: zoomScale
                )
            } else {
                targetContentOffset.pointee = clampedOffset(
                    targetContentOffset.pointee,
                    withinPage: currentPage,
                    zoomScale: zoomScale
                )
            }
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        containerView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
        let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
        containerView.center = CGPoint(x: scrollView.contentSize.width * 0.5 + offsetX,
                                       y: scrollView.contentSize.height * 0.5 + offsetY)
        updateVisiblePages()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        applyPendingDoubleTapRecenteringIfNeeded()
        refreshVisibleCanvasResolution(forceRedraw: true)
    }

    @objc
    private func handleDoubleTapToFit(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let fitScale = scrollView.minimumZoomScale
        guard scrollView.zoomScale > fitScale + 0.02 else { return }

        let dominantPage = dominantPageIndex(
            in: visibleRect(for: scrollView.contentOffset, zoomScale: max(scrollView.zoomScale, 0.001))
        )
        pendingDoubleTapRecenteringPageIndex = dominantPage
        scrollView.setZoomScale(fitScale, animated: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            self?.applyPendingDoubleTapRecenteringIfNeeded()
        }
    }

    private func applyPendingDoubleTapRecenteringIfNeeded() {
        guard let targetPage = pendingDoubleTapRecenteringPageIndex else { return }
        guard abs(scrollView.zoomScale - scrollView.minimumZoomScale) < 0.03 else { return }
        pendingDoubleTapRecenteringPageIndex = nil
        let targetOffset = targetContentOffsetForPage(
            targetPage,
            zoomScale: scrollView.minimumZoomScale,
            alignment: zoomedOutSnapAlignment()
        )
        scrollView.setContentOffset(targetOffset, animated: true)
    }

    @discardableResult
    func triggerTypewriterAutoAdvanceIfNeeded(
        pageIndex: Int,
        strokeLocationInPage: CGPoint,
        writingBounds: CGRect,
        lineHeight: CGFloat
    ) -> Bool {
        guard pageFrames.indices.contains(pageIndex), lineHeight > 0 else { return false }
        guard strokeLocationInPage.x >= writingBounds.maxX else { return false }

        let zoomScale = max(scrollView.zoomScale, 0.001)
        let pageFrame = pageFrames[pageIndex]
        let viewportHeight = scrollView.bounds.height / zoomScale
        let currentContentOffset = visibleRect(for: scrollView.contentOffset, zoomScale: zoomScale).origin

        let targetContentX = pageFrame.minX
        let yMin = pageFrame.minY
        let yMax = max(pageFrame.maxY - viewportHeight, yMin)
        let targetContentY = min(max(currentContentOffset.y + lineHeight, yMin), yMax)

        let targetOffset = clampToScrollBounds(
            CGPoint(x: targetContentX * zoomScale, y: targetContentY * zoomScale)
        )
        scrollView.setContentOffset(targetOffset, animated: true)
        onTypewriterAutoAdvance?(pageIndex, targetOffset)
        return true
    }

    // MARK: - Navigation

    func navigateToPage(_ index: Int, animated: Bool = true) {
        guard index >= 0, index < pageViews.count else { return }
        
        isScrollingProgrammatically = true
        let targetOffset = targetContentOffsetForPage(
            index,
            zoomScale: scrollView.minimumZoomScale,
            alignment: zoomedOutSnapAlignment()
        )
        
        if abs(scrollView.zoomScale - scrollView.minimumZoomScale) > 0.01 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: animated)
        }
        
        scrollView.setContentOffset(targetOffset, animated: animated)
        if !animated {
            isScrollingProgrammatically = false
        }
    }

    private func handleDrawingChanged(at index: Int, updatedDrawing: InkPageDrawing) {
        let previous = pageDrawings[index] ?? InkPageDrawing()
        pageDrawings[index] = updatedDrawing
        if index == lastAutoAppendedBlankPageIndex, !updatedDrawing.isEmpty {
            lastAutoAppendedBlankPageIndex = nil
        }

        guard !isApplyingHistoryChange, previous != updatedDrawing else { return }
        undoStack.append(
            DrawingHistoryStep(
                pageIndex: index,
                previous: previous,
                updated: updatedDrawing
            )
        )
        redoStack.removeAll(keepingCapacity: true)
        reportUndoRedoState()
    }

    func undoLastAction() {
        guard let step = undoStack.popLast() else { return }
        applyHistory(step.previous, to: step.pageIndex)
        redoStack.append(step)
        reportUndoRedoState()
    }

    func redoLastAction() {
        guard let step = redoStack.popLast() else { return }
        applyHistory(step.updated, to: step.pageIndex)
        undoStack.append(step)
        reportUndoRedoState()
    }

    @discardableResult
    func undoLastAutoAppendedBlankPage() -> Bool {
        guard let removedIndex = lastAutoAppendedBlankPageIndex,
              pageDescriptors.indices.contains(removedIndex),
              pageViews.indices.contains(removedIndex) else {
            return false
        }

        let hasHistory = undoStack.contains { $0.pageIndex == removedIndex }
            || redoStack.contains { $0.pageIndex == removedIndex }
        let isTerminalBlankPage: Bool
        if case .blank = pageDescriptors[removedIndex].kind {
            isTerminalBlankPage = true
        } else {
            isTerminalBlankPage = false
        }
        let isPageEmpty = pageDrawings[removedIndex]?.isEmpty ?? true
        guard AutoAppendedBlankPageUndoGuard.canUndo(
            candidateIndex: removedIndex,
            totalPageCount: pageViews.count,
            isTerminalBlankPage: isTerminalBlankPage,
            isPageEmpty: isPageEmpty,
            hasHistory: hasHistory
        ) else {
            return false
        }

        pageViews[removedIndex].removeFromSuperview()
        pageViews.remove(at: removedIndex)
        pageDescriptors.remove(at: removedIndex)
        displayScales.remove(at: removedIndex)
        pageFrames.remove(at: removedIndex)
        pageDrawings.removeValue(forKey: removedIndex)
        lastAutoAppendedBlankPageIndex = nil

        currentPageIndex = max(removedIndex - 1, 0)
        relayoutPages(preservingPageIndex: currentPageIndex)
        coordinator?.pageDidChange(to: currentPageIndex, total: pageViews.count)
        reportUndoRedoState()
        return true
    }

    private func applyHistory(_ drawing: InkPageDrawing, to pageIndex: Int) {
        guard pageViews.indices.contains(pageIndex) else { return }
        isApplyingHistoryChange = true
        pageDrawings[pageIndex] = drawing
        pageViews[pageIndex].canvasView.setDrawing(drawing)
        isApplyingHistoryChange = false
    }

    private func reportUndoRedoState() {
        undoRedoDidChange?(!undoStack.isEmpty, !redoStack.isEmpty)
    }

    // MARK: - Save Everything

    @MainActor
    func prepareSaveResult() async throws -> DocumentSaveResult {
        // Capture drawing state from all loaded page views
        for (i, pageView) in pageViews.enumerated() {
            pageDrawings[i] = pageView.canvasView.currentDrawing()
        }

        let snapshotDrawings = pageDrawings
        let drawingsPayload = InkDrawingStore(
            version: 1,
            pages: snapshotDrawings.filter { !$0.value.isEmpty }
        )
        let encodedDrawings = try JSONEncoder().encode(drawingsPayload)
        let displayScalesSnapshot = displayScales
        let descriptorsSnapshot = pageDescriptors.map { descriptor in
            switch descriptor.kind {
            case let .pdf(index):
                return SavePageDescriptor(pdfPageIndex: index, pageBounds: descriptor.pageBounds)
            case .blank:
                return SavePageDescriptor(pdfPageIndex: nil, pageBounds: descriptor.pageBounds)
            }
        }
        let annotatedURL = repository.localAnnotatedPDFURL(for: documentId)
        let drawingsURL = repository.localDrawingsURL(for: documentId)
        let localEditAt = Date()
        let currentPage = currentPageIndex
        let pdfURL = self.pdfURL!

        let annotatedFilePath = try await Task.detached(priority: .userInitiated) { () -> String? in
            try FileManager.default.createDirectory(
                at: drawingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encodedDrawings.write(to: drawingsURL, options: [.atomic])

            guard let annotatedData = Self.createFlattenedPDF(
                pdfURL: pdfURL,
                pageDescriptors: descriptorsSnapshot,
                pageDrawings: snapshotDrawings,
                displayScales: displayScalesSnapshot
            ) else {
                return nil
            }

            try annotatedData.write(to: annotatedURL, options: [.atomic])
            return annotatedURL.path
        }.value

        return DocumentSaveResult(
            documentId: documentId,
            annotatedFilePath: annotatedFilePath,
            localEditAt: localEditAt,
            lastOpenedPage: currentPage,
            dirtyPageIndexes: Array(snapshotDrawings.keys).sorted()
        )
    }

    // MARK: - Flatten Drawings onto PDF

    nonisolated private static func createFlattenedPDF(
        pdfURL: URL,
        pageDescriptors: [SavePageDescriptor],
        pageDrawings: [Int: InkPageDrawing],
        displayScales: [CGFloat]
    ) -> Data? {
        guard !pageDescriptors.isEmpty else { return nil }
        let pdfDocument = PDFDocument(url: pdfURL)

        let mutableData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData) else { return nil }

        var initialBox = normalizedPageBounds(pageDescriptors[0].pageBounds)
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &initialBox, nil) else { return nil }

        for pageIndex in pageDescriptors.indices {
            let descriptor = pageDescriptors[pageIndex]
            let pageRect = normalizedPageBounds(descriptor.pageBounds)

            let mediaBox = pageRect
            let pageInfo: [String: Any] = [
                kCGPDFContextMediaBox as String: NSValue(cgRect: mediaBox)
            ]
            pdfContext.beginPDFPage(pageInfo as CFDictionary)

            pdfContext.saveGState()
            pdfContext.setFillColor(UIColor.white.cgColor)
            pdfContext.fill(pageRect)
            pdfContext.restoreGState()

            pdfContext.saveGState()
            if let documentPageIndex = descriptor.pdfPageIndex,
               let page = pdfDocument?.page(at: documentPageIndex) {
                page.draw(with: .mediaBox, to: pdfContext)
            }
            pdfContext.restoreGState()

            if let drawing = pageDrawings[pageIndex], !drawing.isEmpty {
                let displayScale = max(
                    displayScales.indices.contains(pageIndex) ? displayScales[pageIndex] : 1.0,
                    0.001
                )
                Self.renderVectorInkDrawing(
                    drawing,
                    in: pdfContext,
                    pageRect: pageRect,
                    displayScale: displayScale
                )
            }

            pdfContext.endPDFPage()
        }

        pdfContext.closePDF()
        return mutableData as Data
    }

    nonisolated private static func renderVectorInkDrawing(
        _ drawing: InkPageDrawing,
        in pdfContext: CGContext,
        pageRect: CGRect,
        displayScale: CGFloat
    ) {
        guard !drawing.strokes.isEmpty else { return }

        pdfContext.saveGState()
        pdfContext.setShouldAntialias(true)
        pdfContext.setAllowsAntialiasing(true)
        pdfContext.translateBy(x: 0, y: pageRect.height)
        pdfContext.scaleBy(x: 1.0, y: -1.0)

        for stroke in drawing.strokes {
            let points = stroke.points.map { point in
                CGPoint(
                    x: point.x * pageRect.width,
                    y: point.y * pageRect.height
                )
            }
            guard !points.isEmpty else { continue }

            let color = stroke.color.uiColor
            let lineWidth = max(stroke.width / displayScale, 0.2)

            pdfContext.saveGState()
            pdfContext.setBlendMode(stroke.blendMode.cgBlendMode)
            pdfContext.setStrokeColor(color.cgColor)
            pdfContext.setFillColor(color.cgColor)
            pdfContext.setLineWidth(lineWidth)
            pdfContext.setLineCap(.round)
            pdfContext.setLineJoin(.round)

            if points.count == 1 {
                let point = points[0]
                let dotRect = CGRect(
                    x: point.x - lineWidth * 0.5,
                    y: point.y - lineWidth * 0.5,
                    width: lineWidth,
                    height: lineWidth
                )
                pdfContext.fillEllipse(in: dotRect)
            } else {
                let path = Self.smoothedPath(from: points)
                pdfContext.addPath(path)
                pdfContext.strokePath()
            }

            pdfContext.restoreGState()
        }

        pdfContext.restoreGState()
    }

    private func vectorPoints(for stroke: PKStroke) -> [CGPoint] {
        let transformedPoints = stroke.path.map { point in
            point.location.applying(stroke.transform)
        }
        guard let firstPoint = transformedPoints.first else { return [] }

        var points: [CGPoint] = [firstPoint]
        for point in transformedPoints.dropFirst() {
            if let last = points.last, hypot(last.x - point.x, last.y - point.y) < 0.05 {
                continue
            }
            points.append(point)
        }
        return points
    }

    nonisolated private static func smoothedPath(from points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)

        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }

        if points.count > 2 {
            for index in 1..<(points.count - 1) {
                let current = points[index]
                let next = points[index + 1]
                let midpoint = CGPoint(
                    x: (current.x + next.x) * 0.5,
                    y: (current.y + next.y) * 0.5
                )
                path.addQuadCurve(to: midpoint, control: current)
            }
            if let last = points.last {
                path.addLine(to: last)
            }
        }

        return path
    }

    private func estimatedLineWidth(for stroke: PKStroke) -> CGFloat {
        guard !stroke.path.isEmpty else { return 1.0 }

        let sampleStep = max(stroke.path.count / 24, 1)
        var totalWidth: CGFloat = 0
        var sampleCount = 0

        for index in stride(from: stroke.path.startIndex, to: stroke.path.endIndex, by: sampleStep) {
            let point = stroke.path[index]
            totalWidth += max(point.size.width, point.size.height)
            sampleCount += 1
        }

        let averageWidth = sampleCount > 0 ? totalWidth / CGFloat(sampleCount) : 1.0
        return max(0.4, averageWidth)
    }

    private func blendMode(for stroke: PKStroke) -> CGBlendMode {
        if stroke.ink.inkType == .marker || stroke.ink.color.cgColor.alpha < 0.6 {
            return .multiply
        }
        return .normal
    }

    // MARK: - Local Drawing Persistence

    private func saveDrawingsToDisk() {
        let populatedPages = pageDrawings.filter { !$0.value.isEmpty }
        let payload = InkDrawingStore(version: 1, pages: populatedPages)
        if let encoded = try? JSONEncoder().encode(payload) {
            try? repository.saveDrawingsLocally(data: encoded, documentId: documentId)
        }
    }

    private func loadSavedDrawings() {
        guard let data = repository.loadLocalDrawings(documentId: documentId) else { return }

        if let decoded = try? JSONDecoder().decode(InkDrawingStore.self, from: data) {
            pageDrawings = decoded.pages
            legacyDrawings = [:]
            return
        }

        if let decodedPages = try? JSONDecoder().decode([Int: InkPageDrawing].self, from: data) {
            pageDrawings = decodedPages
            legacyDrawings = [:]
            return
        }

        if let legacyDecoded = try? JSONDecoder().decode([Int: Data].self, from: data) {
            for (page, drawingData) in legacyDecoded {
                if let drawing = try? PKDrawing(data: drawingData) {
                    legacyDrawings[page] = drawing
                }
            }
        }
    }

    private func migrateLegacyDrawing(_ drawing: PKDrawing, canvasSize: CGSize) -> InkPageDrawing {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return InkPageDrawing()
        }

        var migratedStrokes: [InkStroke] = []
        for stroke in drawing.strokes {
            let points = vectorPoints(for: stroke)
            guard !points.isEmpty else { continue }

            let normalizedPoints = points.map { point in
                InkPoint(
                    x: min(max(point.x / canvasSize.width, 0), 1),
                    y: min(max(point.y / canvasSize.height, 0), 1),
                    force: 1.0
                )
            }

            let color = stroke.ink.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            let blendMode: InkBlendMode = blendMode(for: stroke) == .multiply ? .multiply : .normal
            let migrated = InkStroke(
                points: normalizedPoints,
                width: estimatedLineWidth(for: stroke),
                color: InkColorComponents(color: color),
                blendMode: blendMode
            )
            migratedStrokes.append(migrated)
        }

        return InkPageDrawing(strokes: migratedStrokes)
    }
}

@available(iOS 17.5, *)
extension PageAnnotationViewController: UIPencilInteractionDelegate {
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        // Treat squeeze as a discrete gesture and toggle once when the interaction ends.
        guard squeeze.phase == .ended else { return }
        coordinator?.togglePenAndEraserFromPencilSqueeze()
    }
}
