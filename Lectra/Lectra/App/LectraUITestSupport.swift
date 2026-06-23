import Foundation
import SwiftUI
import UIKit

enum LectraUITestScenario: String {
    case auth
    case library
    case editorCompact
    case editorFull
}

struct LectraLaunchConfiguration {
    static let current = LectraLaunchConfiguration()

    let uiTestScenario: LectraUITestScenario?
    let isUITesting: Bool

    init(processInfo: ProcessInfo = .processInfo) {
        uiTestScenario = processInfo.environment["LECTRA_UI_TEST_SCENARIO"]
            .flatMap(LectraUITestScenario.init(rawValue:))
        isUITesting = uiTestScenario != nil || processInfo.arguments.contains("LECTRA_UI_TESTING")
    }

    var authMockState: AuthManager.MockState? {
        guard isUITesting else { return nil }

        switch uiTestScenario {
        case .auth:
            return AuthManager.MockState(
                isAuthenticated: false,
                userId: nil,
                userEmail: nil,
                userName: nil,
                avatarURL: nil
            )
        case .library, .editorCompact, .editorFull:
            return AuthManager.MockState(
                isAuthenticated: true,
                userId: UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
                userEmail: "ui-tests@canvascope.com",
                userName: "UI Test Student",
                avatarURL: nil
            )
        case nil:
            return AuthManager.MockState(
                isAuthenticated: false,
                userId: nil,
                userEmail: nil,
                userName: nil,
                avatarURL: nil
            )
        }
    }
}

struct LectraLibraryLaunchConfiguration {
    let documents: [LocalDocument]
    let folders: [LocalFolder]
    let documentFolderMap: [String: String]
    let recentDocumentIDs: [UUID]
    let currentFolderID: UUID?
    let isCloudSyncEnabled: Bool
    let isAutoBackupEnabled: Bool
    let lastCloudSyncDate: Date
    let lastBackupDate: Date

    static let smoke: LectraLibraryLaunchConfiguration = {
        let importedFolder = LocalFolder(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            name: "Imported",
            createdAt: Date(timeIntervalSince1970: 1_774_160_800),
            colorHex: 0x8B6AA6,
            iconSystemName: "tray",
            systemTag: nil
        )

        let reviewPacket = makeMockDocument(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            title: "Organic Chemistry Midterm Review Packet",
            updatedAt: Date(timeIntervalSince1970: 1_774_679_200)
        )
        let staticsLab = makeMockDocument(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            title: "Statics Lab 4 Worksheet",
            updatedAt: Date(timeIntervalSince1970: 1_774_635_700),
            syncState: .queuedUpload
        )
        let notebook = makeMockDocument(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000003")!,
            title: "Lecture Notebook - Week 8",
            updatedAt: Date(timeIntervalSince1970: 1_774_548_000),
            isFavorite: true
        )
        let importedScan = makeMockDocument(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000004")!,
            title: "Imported Problem Set Scan",
            updatedAt: Date(timeIntervalSince1970: 1_774_462_000)
        )

        return LectraLibraryLaunchConfiguration(
            documents: [reviewPacket, staticsLab, notebook, importedScan],
            folders: [importedFolder],
            documentFolderMap: [
                importedScan.id.uuidString: importedFolder.id.uuidString
            ],
            recentDocumentIDs: [reviewPacket.id, notebook.id],
            currentFolderID: nil,
            isCloudSyncEnabled: false,
            isAutoBackupEnabled: true,
            lastCloudSyncDate: Date(timeIntervalSince1970: 1_731_974_400),
            lastBackupDate: Date(timeIntervalSince1970: 1_731_974_400)
        )
    }()

    private static func makeMockDocument(
        id: UUID,
        title: String,
        updatedAt: Date,
        syncState: DocumentSyncState = .idle,
        isFavorite: Bool = false
    ) -> LocalDocument {
        let document = LocalDocument(
            title: title,
            localURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(id.uuidString).pdf"),
            id: id,
            isFavorite: isFavorite,
            createdAt: updatedAt.addingTimeInterval(-60 * 60 * 24),
            updatedAt: updatedAt
        )
        document.localPDFURL = nil
        document.syncState = syncState
        return document
    }
}

struct LectraUITestRootView: View {
    let scenario: LectraUITestScenario

    var body: some View {
        switch scenario {
        case .auth:
            AuthView()
        case .library:
            DocumentBrowserView(launchConfiguration: .smoke)
        case .editorCompact:
            CompactEditorTopBarScenarioView()
                .preferredColorScheme(.dark)
        case .editorFull:
            PDFAnnotationView(
                document: LectraEditorLaunchConfiguration.makeDocument(),
                repository: DocumentRepository()
            )
            .preferredColorScheme(.dark)
        }
    }
}

enum LectraEditorLaunchConfiguration {
    private static let documentId = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!

    @MainActor
    static func makeDocument() -> LocalDocument {
        let url = makeFixturePDF()
        return LocalDocument(
            title: "Editor Fixture",
            localURL: url,
            id: documentId,
            createdAt: Date(timeIntervalSince1970: 1_774_160_800),
            updatedAt: Date(timeIntervalSince1970: 1_774_679_200)
        )
    }

    private static func makeFixturePDF() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lectra-ui-editor-fixture.pdf")
        try? FileManager.default.removeItem(at: url)

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        try? renderer.writePDF(to: url) { context in
            for page in 1...2 {
                context.beginPage()
                UIColor.white.setFill()
                UIBezierPath(rect: pageRect).fill()

                let title = "Lectra Editor Fixture"
                let body = [
                    "Page \(page)",
                    "Use this page for pen, highlighter, eraser, lasso, zoom, search, and save checks.",
                    "Search token: mitochondria"
                ].joined(separator: "\n\n")

                draw(title, in: CGRect(x: 54, y: 62, width: 504, height: 42), fontSize: 28, weight: .bold)
                draw(body, in: CGRect(x: 54, y: 124, width: 504, height: 160), fontSize: 18, weight: .regular)

                UIColor.systemBlue.withAlphaComponent(0.14).setFill()
                UIBezierPath(roundedRect: CGRect(x: 54, y: 318, width: 504, height: 96), cornerRadius: 16).fill()
                draw("Annotation target box", in: CGRect(x: 78, y: 350, width: 456, height: 42), fontSize: 22, weight: .semibold)
            }
        }
        return url
    }

    private static func draw(
        _ text: String,
        in rect: CGRect,
        fontSize: CGFloat,
        weight: UIFont.Weight
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph
        ]
        text.draw(in: rect, withAttributes: attributes)
    }
}

private struct CompactEditorTopBarScenarioView: View {
    @State private var titleDraft = "Chemistry Notes"
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        ZStack {
            LectraGradient.appBackdrop.ignoresSafeArea()

            VStack(spacing: 0) {
                EditorTopBar(
                    documentTitle: "Chemistry Notes",
                    titleDraft: $titleDraft,
                    isRenamingTitle: false,
                    isReadMode: true,
                    isSaving: false,
                    isExportingToCanvascope: false,
                    canUndo: true,
                    canRedo: false,
                    syncStatus: EditorSyncStatusDescriptor(
                        title: "Saved",
                        color: LectraColor.success
                    ),
                    hasOutline: true,
                    handedness: .right,
                    squeezeAction: .togglePenEraser,
                    barWidth: 720,
                    onBack: {},
                    onUndo: {},
                    onRedo: {},
                    onBeginRename: {},
                    onCommitRename: {},
                    onShowSearch: {},
                    onShowOutline: {},
                    onSetHandedness: { _ in },
                    onSetSqueezeAction: { _ in },
                    onExportCanvascope: {},
                    onShare: {},
                    onShareOriginal: {},
                    onShareEditable: {},
                    onShowIntelligence: {},
                    isTitleFocused: $isTitleFocused
                )
                .frame(maxWidth: 720)

                Spacer()
            }
        }
    }
}
