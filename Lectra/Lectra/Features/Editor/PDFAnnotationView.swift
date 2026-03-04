import SwiftUI
import PDFKit
import PencilKit
import QuartzCore

// MARK: - SwiftUI Wrapper

struct PDFAnnotationView: View {
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

    private enum ToolbarDockEdge {
        case left
        case right
        case top
        case bottom

        var isVertical: Bool {
            self == .left || self == .right
        }
    }

    @ObservedObject var document: LocalDocument
    let repository: DocumentRepository
    var onRename: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

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
    @State private var selectedTool: AnnotationTool = .pen
    @State private var selectedColor: AnnotationInkColor = .accent
    @State private var selectedStrokeWidth: CGFloat = 2.0
    @State private var toolbarDockEdge: ToolbarDockEdge = .bottom
    @State private var toolbarSize: CGSize = .zero
    @State private var isToolbarDragging = false
    @State private var canvascopeDeliveryTask: Task<Void, Never>? = nil
    private let canvascopeExportService = CanvascopeExportService()

    var body: some View {
        ZStack {
            LectraGradient.appBackdrop.ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Top Nav Bar
                topBar

                // MARK: - Editor Canvas & Floating Pill
                if let url = document.localPDFURL {
                    ZStack {
                        PDFEditorRepresentable(
                            pdfURL: url,
                            documentId: document.id,
                            repository: repository,
                            currentPage: $currentPage,
                            totalPages: $totalPages,
                            selectedTool: $selectedTool,
                            selectedColor: $selectedColor,
                            selectedStrokeWidth: $selectedStrokeWidth,
                            onScroll: { triggerPageIndicator() }
                        )
                        .ignoresSafeArea(.keyboard)

                        GeometryReader { proxy in
                            floatingToolbar(in: proxy)
                        }
                        
                        // Page Indicator Bubble
                        if showPageIndicator {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
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
                                        .padding(.trailing, LectraSpacing.lg)
                                        .padding(.bottom, LectraSpacing.lg)
                                }
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            .allowsHitTesting(false)
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

            // MARK: - Save Overlay
            if isSaving {
                ZStack {
                    Color.black.opacity(0.62).ignoresSafeArea()
                    VStack(spacing: LectraSpacing.md) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.5)
                        Text("Saving & Syncing…")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
                .transition(.opacity)
            }

            // MARK: - Save Feedback Toast
            if let msg = saveMessage {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding()
                        .background(saveMessageStyle.backgroundColor)
                        .cornerRadius(LectraRadius.button)
                        .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .animation(LectraMotion.quick, value: isSaving)
        .animation(LectraMotion.indicatorFade, value: showPageIndicator)
        .animation(LectraMotion.toast, value: saveMessage)
        .animation(LectraMotion.quick, value: isRenamingTitle)
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
        .simultaneousGesture(toolbarDragGesture(in: proxy.size))
    }

    private func toolbarPosition(in proxy: GeometryProxy) -> CGPoint {
        let safe = proxy.safeAreaInsets
        let margin: CGFloat = LectraSpacing.md
        let halfWidth = toolbarSize.width * 0.5
        let halfHeight = toolbarSize.height * 0.5

        let minX = safe.leading + margin + halfWidth
        let maxX = proxy.size.width - safe.trailing - margin - halfWidth
        let minY = safe.top + margin + halfHeight
        let maxY = proxy.size.height - safe.bottom - margin - halfHeight

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

    private func toolbarDragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named("ToolbarDragZone"))
            .onChanged { value in
                if !isToolbarDragging {
                    isToolbarDragging = true
                }
                let newEdge = toolbarDockEdge(for: value.location, in: size)
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
                let newEdge = toolbarDockEdge(for: value.location, in: size)
                withAnimation(LectraMotion.toolbarDock) {
                    toolbarDockEdge = newEdge
                }
            }
    }

    private func toolbarDockEdge(for location: CGPoint, in size: CGSize) -> ToolbarDockEdge {
        let leftZone = size.width * 0.33
        let rightZone = size.width * 0.67
        let topZone = size.height * 0.28

        if location.y <= topZone {
            return .top
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

    private var toolName: String {
        switch selectedTool {
        case .pen:
            return "Pen"
        case .highlighter:
            return "Highlighter"
        case .eraser:
            return "Eraser"
        case .lasso:
            return "Lasso"
        }
    }

    private var toolIcon: String {
        switch selectedTool {
        case .pen:
            return "pencil.tip"
        case .highlighter:
            return "highlighter"
        case .eraser:
            return "eraser"
        case .lasso:
            return "lasso"
        }
    }

    private var strokeWidthLabel: String {
        String(format: "%.1f pt", selectedStrokeWidth)
    }

    // MARK: - Top Nav Bar

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    Task { @MainActor in await saveAndSync() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                        Text("Vault")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 13)
                    .frame(height: LectraSizing.minHitTarget)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
                }
                .disabled(isSaving)

                Spacer(minLength: 4)

                Group {
                    if isRenamingTitle {
                        TextField("Document title", text: $titleDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.13))
                            )
                            .frame(maxWidth: 380, minHeight: LectraSizing.minHitTarget)
                            .focused($isTitleFieldFocused)
                            .submitLabel(.done)
                            .onSubmit { commitTitleRename() }
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    } else {
                        Button {
                            beginTitleRename()
                        } label: {
                            VStack(spacing: 2) {
                                Text(document.title)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                    .foregroundColor(.white)
                                Text("Tap title to rename")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(.white.opacity(0.74))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: LectraSizing.minHitTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 4)

                Button {
                    Task { @MainActor in await exportToCanvascope() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 15, weight: .bold))
                        Text("Canvascope")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .frame(height: LectraSizing.minHitTarget)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
                }
                .disabled(isSaving || isExportingToCanvascope)

                Button {
                    shareDocument()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                }
                .disabled(isSaving || isExportingToCanvascope)
            }

            HStack(spacing: 8) {
                Label {
                    Text("Page \(currentPage + 1) of \(max(totalPages, 1))")
                } icon: {
                    Image(systemName: "doc.text")
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())

                Label {
                    Text("\(toolName) \(strokeWidthLabel)")
                } icon: {
                    Image(systemName: toolIcon)
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())

                Spacer()
            }
        }
        .padding(.horizontal, LectraSpacing.lg)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color(hex: 0x1B2A48),
                        Color(hex: 0x101A2D)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                LectraGradient.spotlight.opacity(0.28)
                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 1)
            }
            .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - Save & Sync

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
    private func saveLocally() async {
        await MainActor.run {
            withAnimation(LectraMotion.quick) {
                isSaving = true
            }
        }
        NotificationCenter.default.post(name: .lectraSaveRequested, object: nil)
        // Give UIKit time to flatten and dump to disk
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await MainActor.run {
            withAnimation(LectraMotion.quick) {
                isSaving = false
            }
        }
    }

    @MainActor
    private func saveAndSync() async {
        await saveLocally()
        setToast("Saved ✓", style: .success, autoHideAfter: 2.0)

        await MainActor.run {
            dismiss()
        }
    }
    
    // MARK: - Sharing
    
    private func shareDocument() {
        Task { @MainActor in
            await saveLocally()

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

        await saveLocally()

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
    private func setToast(_ message: String, style: ToastStyle, autoHideAfter: TimeInterval?) {
        withAnimation(LectraMotion.toast) {
            saveMessageStyle = style
            saveMessage = message
        }

        guard let autoHideAfter else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + autoHideAfter) {
            guard saveMessage == message else { return }
            withAnimation(LectraMotion.toast) {
                saveMessage = nil
            }
        }
    }
}

// MARK: - Notification Name
extension Notification.Name {
    static let lectraSaveRequested = Notification.Name("lectraSaveRequested")
}

// MARK: - PDFEditorRepresentable (UIKit Bridge)

struct PDFEditorRepresentable: UIViewControllerRepresentable {
    let pdfURL: URL
    let documentId: UUID
    let repository: DocumentRepository
    @Binding var currentPage: Int
    @Binding var totalPages: Int
    @Binding var selectedTool: AnnotationTool
    @Binding var selectedColor: AnnotationInkColor
    @Binding var selectedStrokeWidth: CGFloat
    var onScroll: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> PageAnnotationViewController {
        let vc = PageAnnotationViewController()
        vc.pdfURL = pdfURL
        vc.documentId = documentId
        vc.repository = repository
        vc.coordinator = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: PageAnnotationViewController, context: Context) {
        if vc.currentPageIndex != currentPage && !vc.isScrollingProgrammatically {
            vc.navigateToPage(currentPage)
        }

        vc.setTool(
            selectedTool,
            color: selectedColor,
            width: selectedStrokeWidth
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
                let nextTool: AnnotationTool = self.parent.selectedTool == .eraser ? .pen : .eraser
                withAnimation(LectraMotion.quick) {
                    self.parent.selectedTool = nextTool
                }
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

    var cgBlendMode: CGBlendMode {
        switch self {
        case .normal:
            return .normal
        case .multiply:
            return .multiply
        }
    }
}

private struct InkColorComponents: Codable {
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

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

private struct InkPoint: Codable {
    var x: CGFloat
    var y: CGFloat
    var force: CGFloat
}

private struct InkStroke: Codable {
    var points: [InkPoint]
    var width: CGFloat
    var color: InkColorComponents
    var blendMode: InkBlendMode
}

private struct InkPageDrawing: Codable {
    var strokes: [InkStroke] = []

    var isEmpty: Bool {
        strokes.isEmpty
    }
}

private struct InkDrawingStore: Codable {
    var version: Int
    var pages: [Int: InkPageDrawing]
}

private struct InkToolDescriptor {
    enum Mode {
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

    static let `default` = InkToolDescriptor(annotationTool: .pen, inkColor: .black, width: 2.0)

    init(annotationTool: AnnotationTool, inkColor: AnnotationInkColor, width: CGFloat) {
        switch annotationTool {
        case .pen:
            mode = .pen
            color = inkColor.inkUIColor.withAlphaComponent(1.0)
            self.width = min(max(width, 0.5), 2.0)
            blendMode = .normal
            eraserRadius = 0
        case .highlighter:
            mode = .highlighter
            color = inkColor.inkUIColor.withAlphaComponent(0.35)
            self.width = min(max(width * 1.8, 1.5), 20.0)
            blendMode = .multiply
            eraserRadius = 0
        case .eraser:
            mode = .eraser
            color = .clear
            self.width = min(max(width, 2.0), 24.0)
            blendMode = .normal
            eraserRadius = max(self.width * 5.0, 14.0)
        case .lasso:
            mode = .lasso
            color = .clear
            self.width = min(max(width, 2.0), 24.0)
            blendMode = .normal
            eraserRadius = 0
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
    var onDrawingChanged: ((InkPageDrawing) -> Void)?
    var tool: InkToolDescriptor = .default

    private(set) var drawing = InkPageDrawing()

    private var strokeLayers: [CAShapeLayer] = []
    private var activeStrokePoints: [InkPoint] = []
    private var activeStrokeWidth: CGFloat = 1.0
    private var activeStrokeColor = InkColorComponents(red: 0, green: 0, blue: 0, alpha: 1)
    private var activeBlendMode: InkBlendMode = .normal
    private var activeStrokeLayer: CAShapeLayer?

    private lazy var pencilGesture: PencilStrokeGestureRecognizer = {
        let gesture = PencilStrokeGestureRecognizer(target: self, action: #selector(handlePencilGesture(_:)))
        gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        gesture.cancelsTouchesInView = true
        gesture.delaysTouchesBegan = false
        gesture.delaysTouchesEnded = false
        return gesture
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true
        layer.shouldRasterize = false
        layer.drawsAsynchronously = false
        addGestureRecognizer(pencilGesture)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildStrokePaths()
    }

    func setDrawing(_ drawing: InkPageDrawing) {
        self.drawing = drawing
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
            if tool.mode == .eraser {
                erase(at: first.point)
            } else if tool.mode != .lasso {
                beginStroke(at: first.point, force: first.force)
                for sample in samples.dropFirst() {
                    appendStroke(at: sample.point, force: sample.force)
                }
            }
        case .changed:
            if tool.mode == .eraser {
                for sample in samples {
                    erase(at: sample.point)
                }
            } else if tool.mode != .lasso {
                for sample in samples {
                    appendStroke(at: sample.point, force: sample.force)
                }
            }
        case .ended:
            if tool.mode != .eraser && tool.mode != .lasso {
                for sample in samples {
                    appendStroke(at: sample.point, force: sample.force)
                }
                finishStroke()
            }
        case .cancelled, .failed:
            discardActiveStroke()
        default:
            break
        }
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

    private func strokePath(for stroke: InkStroke) -> UIBezierPath {
        let points = stroke.points.map { denormalizedPoint(for: $0) }
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
    
    var pdfURL: URL!
    var documentId: UUID!
    var repository: DocumentRepository!
    weak var coordinator: PDFEditorRepresentable.Coordinator?

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

    private var currentTool: InkToolDescriptor = .default
    private var saveObserver: NSObjectProtocol?
    private let pagePadding: CGFloat = 20.0

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

        // Listen for save requests from SwiftUI
        saveObserver = NotificationCenter.default.addObserver(
            forName: .lectraSaveRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.saveEverything()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // If the view just got bounds, setup pages
        if pageViews.isEmpty && view.bounds.height > 0 {
            setupPages()
            navigateToPage(currentPageIndex, animated: false)
        }
    }

    deinit {
        if let obs = saveObserver {
            NotificationCenter.default.removeObserver(obs)
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

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        // Rely on auto resizing to allow us to define exact frames manually.
        scrollView.addSubview(containerView)
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

        scrollView.minimumZoomScale = 1.0 // Fully zoomed-out fits perfectly inside the screen limits
        scrollView.maximumZoomScale = 5.0
        scrollView.zoomScale = 1.0

        currentPageIndex = min(max(currentPageIndex, 0), max(pageViews.count - 1, 0))
        updateVisiblePages()
        coordinator?.pageDidChange(to: currentPageIndex, total: pageViews.count)
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
        let slotWidth = viewWidth + pagePadding
        let scale = min(viewWidth / bounds.width, viewHeight / bounds.height)
        let scaledWidth = bounds.width * scale
        let scaledHeight = bounds.height * scale
        let xOffset = (viewWidth - scaledWidth) * 0.5
        let yOffset = (viewHeight - scaledHeight) * 0.5
        let frame = CGRect(
            x: CGFloat(index) * slotWidth + xOffset,
            y: yOffset,
            width: scaledWidth,
            height: scaledHeight
        )

        let pageView = PageView(pageIndex: index)
        pageView.frame = frame
        pageView.canvasView.tool = currentTool
        pageView.canvasView.setDrawing(drawing)
        pageView.canvasView.onDrawingChanged = { [weak self] updatedDrawing in
            self?.pageDrawings[index] = updatedDrawing
        }

        containerView.addSubview(pageView)
        pageViews.append(pageView)
        pageDescriptors.append(PageDescriptor(kind: descriptor.kind, pageBounds: bounds))
        displayScales.append(scale)
        pageDrawings[index] = drawing
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
        let slotWidth = viewWidth + pagePadding
        let contentWidth = max(0, CGFloat(pageViews.count) * slotWidth - pagePadding)
        containerView.frame = CGRect(x: 0, y: 0, width: contentWidth, height: viewHeight)
        scrollView.contentSize = containerView.bounds.size
    }

    func setTool(_ tool: AnnotationTool, color: AnnotationInkColor, width: CGFloat) {
        currentTool = InkToolDescriptor(annotationTool: tool, inkColor: color, width: width)
        pageViews.forEach { $0.canvasView.tool = currentTool }
    }

    // MARK: - Scrolling, Visibility, and Zooming
    
    private func updateVisiblePages() {
        let visibleRect = scrollView.convert(scrollView.bounds, to: containerView)
        // Expand visible rect to pre-render adjacent pages lazily
        let prefetchRect = visibleRect.insetBy(dx: -view.bounds.width * 0.5, dy: 0)
        
        var closestPage = currentPageIndex
        var minDistance: CGFloat = .greatestFiniteMagnitude
        let centerX = visibleRect.midX
        
        for (i, pageView) in pageViews.enumerated() {
            if prefetchRect.intersects(pageView.frame) {
                if !pageView.isRendered {
                    renderPage(i, into: pageView)
                }
            } else {
                pageView.clear()
            }
            
            let dist = abs(pageView.frame.midX - centerX)
            if dist < minDistance {
                minDistance = dist
                closestPage = i
            }
        }
        
        if closestPage != currentPageIndex {
            currentPageIndex = closestPage
            // Update SWIFTUI only if we're not manually scrolling via the API
            if !isScrollingProgrammatically {
                coordinator?.pageDidChange(to: closestPage, total: pageViews.count)
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
    }
    
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        if abs(scrollView.zoomScale - scrollView.minimumZoomScale) < 0.01 {
            let slotWidth = view.bounds.width + pagePadding
            
            let estimatedPage = targetContentOffset.pointee.x / slotWidth
            var page = round(estimatedPage)
            
            // Allow flicking to smoothly turn pages
            if velocity.x > 0.3 {
                if currentPageIndex == pageViews.count - 1 {
                    let newPageIndex = appendBlankPage()
                    targetContentOffset.pointee.x = CGFloat(newPageIndex) * slotWidth
                    coordinator?.pageDidChange(to: newPageIndex, total: pageViews.count)
                    return
                }
                page = ceil(estimatedPage)
            } else if velocity.x < -0.3 {
                page = floor(estimatedPage)
            }
            
            page = max(0, min(page, CGFloat(pageViews.count - 1)))
            targetContentOffset.pointee.x = page * slotWidth
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
        refreshVisibleCanvasResolution(forceRedraw: true)
    }

    // MARK: - Navigation

    func navigateToPage(_ index: Int, animated: Bool = true) {
        guard index >= 0, index < pageViews.count else { return }
        
        isScrollingProgrammatically = true
        let slotWidth = view.bounds.width + pagePadding
        
        let targetX = CGFloat(index) * slotWidth
        
        if scrollView.zoomScale != 1.0 {
            scrollView.setZoomScale(1.0, animated: animated)
        }
        
        let visibleX = max(0, min(targetX, scrollView.contentSize.width - scrollView.bounds.width))
        let visibleY: CGFloat = 0
        
        scrollView.setContentOffset(CGPoint(x: visibleX, y: visibleY), animated: animated)
        if !animated {
            isScrollingProgrammatically = false
        }
    }

    // MARK: - Save Everything

    private func saveEverything() {
        // Capture drawing state from all loaded page views
        for (i, pageView) in pageViews.enumerated() {
            pageDrawings[i] = pageView.canvasView.currentDrawing()
        }

        saveDrawingsToDisk()

        if let annotatedData = createFlattenedPDF() {
            let localURL = repository.localPDFURL(for: documentId)
                .deletingLastPathComponent()
                .appendingPathComponent("annotated.pdf")
            try? annotatedData.write(to: localURL)
        }
    }

    // MARK: - Flatten Drawings onto PDF

    private func createFlattenedPDF() -> Data? {
        guard let pdfDocument = pdfDocument, !pageDescriptors.isEmpty else { return nil }

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
            if case let .pdf(documentPageIndex) = descriptor.kind,
               let page = pdfDocument.page(at: documentPageIndex) {
                page.draw(with: .mediaBox, to: pdfContext)
            }
            pdfContext.restoreGState()

            if let drawing = pageDrawings[pageIndex], !drawing.isEmpty {
                let displayScale = max(
                    displayScales.indices.contains(pageIndex) ? displayScales[pageIndex] : 1.0,
                    0.001
                )
                renderVectorInkDrawing(
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

    private func renderVectorInkDrawing(
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
                let path = smoothedPath(from: points)
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

    private func smoothedPath(from points: [CGPoint]) -> CGPath {
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
