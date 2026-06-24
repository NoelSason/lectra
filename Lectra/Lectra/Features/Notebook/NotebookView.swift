//
//  NotebookView.swift
//  Lectra
//
//  The in-app notebook editor: a Jupyter-like surface where cells run real
//  Python on-device via PyodideRuntime. Add / edit / reorder / delete cells,
//  run them (state persists across cells, like a kernel), and share the result
//  as a valid `.ipynb`. Styled with Lectra design tokens.
//

import SwiftUI
import UniformTypeIdentifiers

struct NotebookView: View {
    @StateObject private var document: NotebookDocument
    @StateObject private var runtime = PyodideRuntime()
    @ObservedObject private var store = NotebookStore.shared

    @Environment(\.dismiss) private var dismiss
    @State private var sharePayload: SharePayload?
    @FocusState private var titleFocused: Bool

    @State private var pendingInstall: PendingInstall?
    @State private var installing: String?      // module name currently installing
    @State private var installNotice: String?
    @State private var showPackages = false

    @State private var showDataPicker = false
    @State private var pendingData: PendingData?

    @State private var gitLink: GitLink?
    @State private var gitWorking = false

    /// A missing import the user can choose to download from PyPI.
    private struct PendingInstall: Identifiable {
        let module: String
        let cellID: String
        var id: String { module + cellID }
    }

    /// A picked data file awaiting the import-mode choice.
    private struct PendingData: Identifiable {
        let url: URL
        let delimiter: String
        var id: String { url.path }
    }

    /// Called when the title is committed, so the library card can be renamed.
    private let onTitleChange: ((String) -> Void)?

    init(document: NotebookDocument, onTitleChange: ((String) -> Void)? = nil) {
        _document = StateObject(wrappedValue: document)
        self.onTitleChange = onTitleChange
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: LectraSpacing.md) {
                    titleField
                    ForEach(document.cells) { cell in
                        NotebookCellView(
                            cell: cell,
                            onRun: { run(cell) },
                            onRunSelectBelow: { runSelectBelow(cell) },
                            onRunInsertBelow: { runInsertBelow(cell) },
                            onDelete: { withAnimation(LectraMotion.quick) { document.delete(cell) } },
                            onMoveUp: { withAnimation(LectraMotion.quick) { document.move(cell, by: -1) } },
                            onMoveDown: { withAnimation(LectraMotion.quick) { document.move(cell, by: 1) } },
                            onChangeType: { document.changeType(cell, to: $0) },
                            isFocused: document.focusedCellID == cell.id,
                            onFocus: { document.focusedCellID = cell.id })
                    }
                    addCellBar
                }
                .padding(LectraSpacing.lg)
            }
            .background(LectraGradient.appBackdrop.ignoresSafeArea())
            .navigationTitle("Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbarBackground(LectraColor.surfaceOverlay, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { kernelBar }
        }
        .preferredColorScheme(.dark)
        .task {
            store.save(document)
            gitLink = GitLinkStore.shared.link(for: document.id.uuidString)
            try? await runtime.start()
        }
        .onDisappear {
            commitTitle()
            store.save(document)
            runtime.shutdown()
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheetView(items: payload.urls)
        }
        .sheet(isPresented: $showPackages) {
            PackagesPanelView(runtime: runtime)
        }
        .sheet(item: $pendingData) { data in
            DataImportSheet(fileName: data.url.lastPathComponent, delimiter: data.delimiter) { asDF, delim in
                importData(from: data.url, asDataFrame: asDF, delimiter: delim)
            }
        }
        .fileImporter(isPresented: $showDataPicker,
                      allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                pendingData = PendingData(url: url, delimiter: Self.defaultDelimiter(for: url))
            }
        }
        .alert("Install “\(pendingInstall?.module ?? "")”?",
               isPresented: installAlertPresented,
               presenting: pendingInstall) { item in
            Button("Install") { performInstall(item.module, rerunCellID: item.cellID) }
            Button("Not now", role: .cancel) {}
        } message: { item in
            Text("This cell imports “\(item.module)”, which isn’t installed. Download it from PyPI?")
        }
        .alert("Lectra", isPresented: noticeAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(installNotice ?? "")
        }
    }

    private var installAlertPresented: Binding<Bool> {
        Binding(get: { pendingInstall != nil }, set: { if !$0 { pendingInstall = nil } })
    }

    private var noticeAlertPresented: Binding<Bool> {
        Binding(get: { installNotice != nil }, set: { if !$0 { installNotice = nil } })
    }

    // MARK: Header

    private var titleField: some View {
        HStack(spacing: LectraSpacing.sm) {
            TextField("Notebook title", text: $document.title)
                .font(LectraTypography.title)
                .foregroundStyle(LectraColor.textPrimary)
                .textFieldStyle(.plain)
                .focused($titleFocused)
                .submitLabel(.done)
                .onSubmit { commitTitle() }
            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(titleFocused ? LectraColor.accentSoft : LectraColor.textTertiary)
        }
        .padding(.horizontal, LectraSpacing.md)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                .fill(LectraColor.surfaceFloating.opacity(titleFocused ? 0.85 : 0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                        .stroke(titleFocused ? LectraColor.accent.opacity(0.5) : LectraColor.edgeStroke, lineWidth: 1))
        )
        .contentShape(Rectangle())
        .onTapGesture { titleFocused = true }
    }

    private func commitTitle() {
        let trimmed = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { document.title = "Untitled Notebook" }
        store.save(document)
        onTitleChange?(document.title)
    }

    private var kernelBar: some View {
        HStack(spacing: 8) {
            switch runtime.status {
            case .ready:
                Circle().fill(LectraColor.success).frame(width: 8, height: 8)
                Text("Python ready").foregroundStyle(LectraColor.textSecondary)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(LectraColor.warning)
                Text("Python unavailable").foregroundStyle(LectraColor.textSecondary)
            default:
                ProgressView().controlSize(.mini).tint(LectraColor.accentSoft)
                Text("Starting Python…").foregroundStyle(LectraColor.textSecondary)
            }
            Spacer()
            if let installing {
                ProgressView().controlSize(.mini).tint(LectraColor.accentSoft)
                Text("Installing \(installing)…").foregroundStyle(LectraColor.textSecondary)
            } else {
                Text("⇧⏎ run")
                    .foregroundStyle(LectraColor.textTertiary)
            }
        }
        .font(LectraTypography.footnoteBold)
        .padding(.horizontal, LectraSpacing.lg)
        .padding(.vertical, LectraSpacing.sm)
        .background(LectraColor.surfaceOverlay.opacity(0.95))
        .overlay(alignment: .bottom) {
            Rectangle().fill(LectraColor.edgeStroke).frame(height: 1)
        }
    }

    private var addCellBar: some View {
        HStack(spacing: LectraSpacing.sm) {
            addButton(title: "Code", icon: "chevron.left.forwardslash.chevron.right") {
                document.addCell(.code, after: document.cells.last)
            }
            addButton(title: "Markdown", icon: "text.alignleft") {
                document.addCell(.markdown, after: document.cells.last)
            }
            addButton(title: "Data", icon: "tablecells") {
                showDataPicker = true
            }
        }
        .padding(.top, LectraSpacing.sm)
    }

    private func addButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            LectraHaptics.tap()
            withAnimation(LectraMotion.quick) { action() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(LectraTypography.footnoteBold)
            .foregroundStyle(LectraColor.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                    .stroke(LectraColor.edgeStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        }
        .buttonStyle(.plain)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                LectraHaptics.tap()
                dismiss()
            } label: {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(LectraColor.textTertiary)
            }
            .accessibilityLabel("Close")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { runAll() } label: {
                Image(systemName: "play.fill").foregroundStyle(LectraColor.accentSoft)
            }
            .accessibilityLabel("Run all cells")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { share() } label: { Label("Share Notebook (.ipynb)", systemImage: "square.and.arrow.up") }
                Button { showPackages = true } label: { Label("Manage Packages", systemImage: "shippingbox") }
                if gitLink != nil {
                    Divider()
                    Button { pullNotebook() } label: { Label("Pull from GitHub", systemImage: "arrow.down.circle") }
                    Button { pushNotebook() } label: { Label("Commit & Push", systemImage: "arrow.up.circle") }
                }
                Button { restart() } label: { Label("Restart Kernel", systemImage: "arrow.clockwise") }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(LectraColor.textSecondary)
            }
        }
    }

    // MARK: Actions

    private func run(_ cell: NotebookCell) {
        guard cell.type == .code, !cell.isRunning else { return }
        cell.isRunning = true
        Task {
            let result = await runtime.run(cell.source, cellID: cell.id)
            finish(cell, result)
            store.save(document)
            // Offer to fetch a missing import from PyPI.
            if installing == nil, let missing = Self.missingModule(in: result.error) {
                pendingInstall = PendingInstall(module: missing, cellID: cell.id)
            }
        }
    }

    private func finish(_ cell: NotebookCell, _ result: PyodideRunResult) {
        cell.output = CellOutput(result)
        cell.executionCount = document.nextExecutionCount()
        cell.isRunning = false
        if result.error != nil { LectraHaptics.warning() } else { LectraHaptics.success() }
    }

    /// Pulls the top-level module name out of a `ModuleNotFoundError` traceback.
    private static func missingModule(in error: String?) -> String? {
        guard let error, let range = error.range(of: "No module named '") else { return nil }
        let tail = error[range.upperBound...]
        guard let end = tail.firstIndex(of: "'") else { return nil }
        let full = String(tail[..<end])
        return full.split(separator: ".").first.map(String.init)
    }

    private func performInstall(_ module: String, rerunCellID: String?) {
        installing = module
        Task {
            let res = await runtime.install(module)
            installing = nil
            if res.success {
                installNotice = "Installed “\(module)”."
                if let id = rerunCellID, let cell = document.cells.first(where: { $0.id == id }) {
                    run(cell)
                }
            } else {
                installNotice = res.error ?? "Couldn’t install “\(module)”."
            }
        }
    }

    /// Shift+Enter: run, then focus the next code cell (creating one at the end
    /// if there isn't a next code cell).
    private func runSelectBelow(_ cell: NotebookCell) {
        run(cell)
        if let next = document.nextCodeCell(after: cell) {
            document.focusedCellID = next.id
        } else {
            let new = document.addCell(.code, after: document.cells.last)
            document.focusedCellID = new.id
        }
    }

    /// Option+Enter: run, then insert and focus a new code cell directly below.
    private func runInsertBelow(_ cell: NotebookCell) {
        run(cell)
        let new = document.addCell(.code, after: cell)
        document.focusedCellID = new.id
    }

    private func runAll() {
        LectraHaptics.tap()
        Task {
            for cell in document.cells where cell.type == .code {
                cell.isRunning = true
                let result = await runtime.run(cell.source, cellID: cell.id)
                cell.output = CellOutput(result)
                cell.executionCount = document.nextExecutionCount()
                cell.isRunning = false
            }
            store.save(document)
        }
    }

    // MARK: Data import

    private static func defaultDelimiter(for url: URL) -> String {
        url.pathExtension.lowercased() == "tsv" ? "\t" : ","
    }

    /// Sanitizes a picked file's name into a safe, Python-friendly identifier for
    /// the kernel filesystem (keeps the extension, strips path separators/quotes).
    private static func safeName(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let cleaned = String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return cleaned.isEmpty ? "data.csv" : cleaned
    }

    private func importData(from url: URL, asDataFrame: Bool, delimiter: String) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            installNotice = "Couldn’t read that file."; return
        }
        let name = Self.safeName(url.lastPathComponent)
        Task {
            let ok = await runtime.writeFile(path: name, base64: data.base64EncodedString())
            guard ok else { installNotice = "Couldn’t load “\(name)” into Python."; return }
            let cell = insertDataCell(name: name, asDataFrame: asDataFrame, delimiter: delimiter)
            store.save(document)
            if asDataFrame { run(cell) }
        }
    }

    @discardableResult
    private func insertDataCell(name: String, asDataFrame: Bool, delimiter: String) -> NotebookCell {
        let source: String
        if asDataFrame {
            let sep = delimiter == "," ? "" : ", sep='\(Self.pySep(delimiter))'"
            source = "import pandas as pd\ndf = pd.read_csv('\(name)'\(sep))\ndf.head()"
        } else {
            source = "# “\(name)” is in this notebook’s working directory.\n"
                + "with open('\(name)') as f:\n    print(f.read()[:500])"
        }
        let cell = document.addCell(.code, after: document.cells.last)
        cell.source = source
        document.focusedCellID = cell.id
        return cell
    }

    /// Escapes a delimiter for embedding inside a single-quoted Python string.
    private static func pySep(_ delimiter: String) -> String {
        delimiter == "\t" ? "\\t" : delimiter.replacingOccurrences(of: "'", with: "\\'")
    }

    // MARK: GitHub

    private func pushNotebook() {
        guard let link = gitLink, !gitWorking,
              let data = try? document.toJupyter().encodeIPYNB() else { return }
        gitWorking = true
        Task {
            do {
                let newSha = try await GitHubService.shared.commit(
                    data, link: link, message: "Update \(link.path) from Lectra")
                var updated = link; updated.baseSha = newSha
                GitLinkStore.shared.set(updated, for: document.id.uuidString)
                gitLink = updated
                installNotice = "Pushed to \(link.repoFullName)."
            } catch {
                installNotice = error.localizedDescription
            }
            gitWorking = false
        }
    }

    private func pullNotebook() {
        guard let link = gitLink, !gitWorking else { return }
        gitWorking = true
        Task {
            do {
                let file = try await GitHubService.shared.getFile(
                    repo: link.repoFullName, path: link.path, ref: link.branch)
                let nb = try JupyterNotebook(data: file.data)
                let fresh = NotebookDocument(jupyter: nb)
                document.title = fresh.title
                document.cells = fresh.cells
                store.save(document)
                var updated = link; updated.baseSha = file.sha
                GitLinkStore.shared.set(updated, for: document.id.uuidString)
                gitLink = updated
                installNotice = "Pulled the latest from \(link.repoFullName)."
            } catch {
                installNotice = error.localizedDescription
            }
            gitWorking = false
        }
    }

    private func restart() {
        LectraHaptics.tap()
        runtime.restart()
    }

    private func share() {
        guard let url = store.exportURL(for: document) else { return }
        LectraHaptics.tap()
        sharePayload = SharePayload(urls: [url])
    }
}
