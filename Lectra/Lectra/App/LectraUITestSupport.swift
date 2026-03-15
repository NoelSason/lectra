import SwiftUI

enum LectraUITestScenario: String {
    case auth
    case library
    case gradescope
    case editorCompact
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
        case .library, .gradescope, .editorCompact:
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

    var gradescopeMockState: GradescopeManager.MockState? {
        guard isUITesting else { return nil }

        switch uiTestScenario {
        case .gradescope:
            let course = GSCourse(
                id: "course-ui-smoke",
                shortName: "BIO 201",
                fullName: "Biology 201"
            )
            let assignment = GSAssignment(
                id: "assignment-ui-smoke",
                courseId: course.id,
                name: "Lab Report 3",
                releaseDate: nil,
                dueDate: Date(timeIntervalSince1970: 1_732_147_200),
                lateDueDate: nil,
                submissionsStatus: nil,
                grade: nil,
                maxGrade: nil
            )
            return GradescopeManager.MockState(
                isAuthenticated: true,
                courses: [course],
                assignmentsByCourse: [course.id: [assignment]],
                assignmentDebugByCourse: [
                    course.id: "assignment refresh: loaded 1 assignment"
                ],
                webSessionDebugReport: nil,
                diagnosticsReport: "courses sync: loaded 1 course\nsession: mock",
                errorMessage: nil,
                sessionExpirationDate: Date().addingTimeInterval(60 * 60)
            )
        case .auth, .library, .editorCompact, nil:
            return GradescopeManager.MockState(isAuthenticated: false)
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

    static let smoke = LectraLibraryLaunchConfiguration(
        documents: [],
        folders: [],
        documentFolderMap: [:],
        recentDocumentIDs: [],
        currentFolderID: nil,
        isCloudSyncEnabled: false,
        isAutoBackupEnabled: true,
        lastCloudSyncDate: Date(timeIntervalSince1970: 1_731_974_400),
        lastBackupDate: Date(timeIntervalSince1970: 1_731_974_400)
    )
}

struct LectraUITestRootView: View {
    let scenario: LectraUITestScenario

    var body: some View {
        switch scenario {
        case .auth:
            AuthView()
        case .library:
            DocumentBrowserView(launchConfiguration: .smoke)
        case .gradescope:
            ZStack {
                LectraGradient.appBackdrop.ignoresSafeArea()
                GradescopeHubView { _, _, _ in }
            }
            .preferredColorScheme(.dark)
        case .editorCompact:
            CompactEditorTopBarScenarioView()
                .preferredColorScheme(.dark)
        }
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
                    onShowGradescope: {},
                    onShare: {},
                    isTitleFocused: $isTitleFocused
                )
                .frame(maxWidth: 720)

                Spacer()
            }
        }
    }
}
