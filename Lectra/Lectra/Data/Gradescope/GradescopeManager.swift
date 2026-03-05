import Foundation
import Combine

@MainActor
final class GradescopeManager: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isBusy = false
    @Published private(set) var courses: [GSCourse] = []
    @Published private(set) var assignmentsByCourse: [String: [GSAssignment]] = [:]
    @Published private(set) var assignmentDebugByCourse: [String: String] = [:]
    @Published private(set) var webSessionDebugReport: String?
    @Published private(set) var diagnosticsReport: String?
    @Published var errorMessage: String?

    private let authService: GradescopeAuthService
    private let catalogService: GradescopeCatalogService
    private let templateService: GradescopeTemplateService
    private let submissionService: GradescopeSubmissionService
    private let webScrapeService: GradescopeWebScrapeService
    private let linkStore: GradescopeLinkStore

    init() {
        let parser = GradescopeHTMLParser()
        let httpClient = GradescopeHTTPClient()
        let keychainStore = GradescopeKeychainStore()
        let linkStore = GradescopeLinkStore()

        self.authService = GradescopeAuthService(
            httpClient: httpClient,
            parser: parser,
            keychainStore: keychainStore
        )

        self.catalogService = GradescopeCatalogService(
            httpClient: httpClient,
            parser: parser
        )

        self.templateService = GradescopeTemplateService(
            httpClient: httpClient,
            parser: parser
        )

        let webRunner = GradescopeSubmissionWebRunnerImpl()
        self.submissionService = GradescopeSubmissionService(
            httpClient: httpClient,
            parser: parser,
            linkStore: linkStore,
            webRunner: webRunner
        )

        self.webScrapeService = GradescopeWebScrapeService(parser: parser)

        self.linkStore = linkStore

        Task {
            await restoreSession()
        }
    }

    func restoreSession() async {
        isBusy = true
        defer { isBusy = false }

        let restored = await authService.restoreSession()
        isAuthenticated = restored

        if restored {
            await refreshCourses()
        } else {
            courses = []
            assignmentsByCourse = [:]
            assignmentDebugByCourse = [:]
        }
    }

    func login(email: String, password: String) async {
        isBusy = true
        errorMessage = nil
        webSessionDebugReport = nil
        diagnosticsReport = nil
        defer { isBusy = false }

        do {
            try await authService.login(email: email, password: password)
            isAuthenticated = true
            await refreshCourses()
        } catch {
            isAuthenticated = false
            let localized = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = localized
        }
    }

    func loginWithWebSession(cookies: [HTTPCookie], accountPageHTML: String?) async {
        isBusy = true
        errorMessage = nil
        webSessionDebugReport = nil
        diagnosticsReport = nil
        defer { isBusy = false }

        do {
            try await authService.loginWithImportedWebSession(cookies: cookies, accountPageHTML: accountPageHTML)
            isAuthenticated = true
            webSessionDebugReport = authService.lastWebSessionImportDebugReport
            await refreshCourses()

            if courses.isEmpty, let accountPageHTML {
                let seededCourses = catalogService.parseCoursesFromHTML(accountPageHTML)
                if !seededCourses.isEmpty {
                    courses = seededCourses
                    errorMessage = nil
                }
            }
        } catch {
            isAuthenticated = false
            let localized = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = localized
            webSessionDebugReport = authService.lastWebSessionImportDebugReport
        }
    }

    func logout() {
        authService.logout()
        isAuthenticated = false
        courses = []
        assignmentsByCourse = [:]
        assignmentDebugByCourse = [:]
        webSessionDebugReport = nil
        diagnosticsReport = nil
        errorMessage = nil
    }

    func refreshCourses() async {
        guard isAuthenticated else { return }

        isBusy = true
        errorMessage = nil
        diagnosticsReport = nil
        defer { isBusy = false }

        do {
            let result = try await catalogService.fetchCoursesWithDebug()
            courses = result.courses
            diagnosticsReport = result.debugLines.joined(separator: "\n")
        } catch {
            let localized = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = localized
            var lines = catalogService.lastDebugLines
            lines.append("courses error: \(localized)")
            diagnosticsReport = lines.joined(separator: "\n")
        }
    }

    func refreshAssignments(for courseId: String) async {
        guard isAuthenticated, !courseId.isEmpty else { return }

        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        var debugLines: [String] = []
        debugLines.append("refresh start: course=\(courseId)")

        do {
            let catalogResult = try await catalogService.fetchAssignmentsWithDebug(courseId: courseId)
            debugLines.append(contentsOf: catalogResult.debugLines)

            var resolvedAssignments = catalogResult.assignments

            if resolvedAssignments.isEmpty {
                debugLines.append("catalog returned 0 assignments; trying rendered web scrape")
                do {
                    let scrapeResult = try await webScrapeService.fetchAssignmentsWithDebug(courseId: courseId)
                    debugLines.append(contentsOf: scrapeResult.debugLines)
                    if !scrapeResult.assignments.isEmpty {
                        resolvedAssignments = scrapeResult.assignments
                        debugLines.append("web-scrape success: assignments=\(scrapeResult.assignments.count)")
                    } else {
                        debugLines.append("web-scrape complete: still 0 assignments")
                    }
                } catch {
                    debugLines.append("web-scrape error: \(localizedDescription(for: error))")
                }
            }

            assignmentsByCourse[courseId] = resolvedAssignments
            debugLines.append("refresh complete: final assignments=\(resolvedAssignments.count)")
            assignmentDebugByCourse[courseId] = debugLines.joined(separator: "\n")
            diagnosticsReport = assignmentDebugByCourse[courseId]
        } catch {
            let localized = localizedDescription(for: error)
            errorMessage = localized
            debugLines.append("catalog error: \(localized)")
            assignmentDebugByCourse[courseId] = debugLines.joined(separator: "\n")
            diagnosticsReport = assignmentDebugByCourse[courseId]
        }
    }

    func assignments(for courseId: String) -> [GSAssignment] {
        assignmentsByCourse[courseId] ?? []
    }

    func assignmentDebugMessage(for courseId: String) -> String? {
        assignmentDebugByCourse[courseId]
    }

    func latestWebSessionDebugReport() -> String? {
        webSessionDebugReport
    }

    func latestDiagnosticsReport() -> String? {
        diagnosticsReport
    }

    func prepareTemplateImport(for assignment: GSAssignment) async throws -> (fileURL: URL, suggestedFileName: String) {
        do {
            let templateResult = try await templateService.fetchTemplateWithDebug(for: assignment)
            diagnosticsReport = templateResult.debugLines.joined(separator: "\n")

            switch templateResult.template {
            case .noTemplate:
                throw GSError.noTemplateAvailable
            case .available(let downloadURL, let suggestedFileName):
                let localURL = try await templateService.downloadTemplate(url: downloadURL, suggestedFileName: suggestedFileName)
                diagnosticsReport = templateService.lastDebugLines.joined(separator: "\n")
                return (localURL, suggestedFileName)
            }
        } catch {
            var lines = templateService.lastDebugLines
            lines.append("template error: \(localizedDescription(for: error))")
            diagnosticsReport = lines.joined(separator: "\n")
            throw error
        }
    }

    func preflight(documentId: UUID?, fileURL: URL, courseId: String, assignmentId: String) async throws -> GSPreflightResult {
        let draft = GSSubmissionDraft(
            documentId: documentId,
            courseId: courseId,
            assignmentId: assignmentId,
            localFileURL: fileURL
        )
        do {
            let result = try await submissionService.preflightWithDebug(draft: draft)
            diagnosticsReport = result.debugLines.joined(separator: "\n")
            return result.preflight
        } catch {
            var lines = submissionService.lastDebugLines
            lines.append("preflight error: \(localizedDescription(for: error))")
            diagnosticsReport = lines.joined(separator: "\n")
            throw error
        }
    }

    func submit(documentId: UUID?, fileURL: URL, courseId: String, assignmentId: String, confirmed: Bool) async throws -> GSSubmissionReceipt {
        let draft = GSSubmissionDraft(
            documentId: documentId,
            courseId: courseId,
            assignmentId: assignmentId,
            localFileURL: fileURL
        )
        do {
            let result = try await submissionService.submitWithDebug(draft: draft, confirmed: confirmed)
            diagnosticsReport = result.debugLines.joined(separator: "\n")
            return result.receipt
        } catch {
            var lines = submissionService.lastDebugLines
            lines.append("submit error: \(localizedDescription(for: error))")
            diagnosticsReport = lines.joined(separator: "\n")
            throw error
        }
    }

    func prepareSubmissionWorkflow(documentId: UUID?, fileURL: URL, courseId: String, assignmentId: String) async throws -> GSSubmissionWorkflow {
        let draft = GSSubmissionDraft(
            documentId: documentId,
            courseId: courseId,
            assignmentId: assignmentId,
            localFileURL: fileURL
        )
        do {
            let workflow = try await submissionService.prepareSubmissionWorkflow(draft: draft)
            diagnosticsReport = submissionService.lastDebugLines.joined(separator: "\n")
            return workflow
        } catch {
            var lines = submissionService.lastDebugLines
            lines.append("workflow error: \(localizedDescription(for: error))")
            diagnosticsReport = lines.joined(separator: "\n")
            throw error
        }
    }

    func uploadPDF(workflowId: String, confirmed: Bool) async throws -> GSUploadResult {
        do {
            let result = try await submissionService.uploadPDF(workflowId: workflowId, confirmed: confirmed)
            diagnosticsReport = submissionService.lastDebugLines.joined(separator: "\n")
            return result
        } catch {
            var lines = submissionService.lastDebugLines
            lines.append("upload error: \(localizedDescription(for: error))")
            diagnosticsReport = lines.joined(separator: "\n")
            throw error
        }
    }

    func updateGroupMembers(workflowId: String, members: [GSGroupMemberDraft]) async throws -> GSGroupUpdateResult {
        do {
            let result = try await submissionService.updateGroupMembers(workflowId: workflowId, members: members)
            diagnosticsReport = submissionService.lastDebugLines.joined(separator: "\n")
            return result
        } catch {
            var lines = submissionService.lastDebugLines
            lines.append("group update error: \(localizedDescription(for: error))")
            diagnosticsReport = lines.joined(separator: "\n")
            throw error
        }
    }

    func updatePageAssignments(workflowId: String, assignments: [GSPageAssignmentDraft]) async throws -> GSPageAssignmentResult {
        do {
            let result = try await submissionService.updatePageAssignments(workflowId: workflowId, assignments: assignments)
            diagnosticsReport = submissionService.lastDebugLines.joined(separator: "\n")
            return result
        } catch {
            var lines = submissionService.lastDebugLines
            lines.append("page mapping error: \(localizedDescription(for: error))")
            diagnosticsReport = lines.joined(separator: "\n")
            throw error
        }
    }

    func finalizeSubmission(workflowId: String) async throws -> GSSubmissionReceipt {
        do {
            let receipt = try await submissionService.finalizeSubmission(workflowId: workflowId)
            diagnosticsReport = submissionService.lastDebugLines.joined(separator: "\n")
            return receipt
        } catch {
            var lines = submissionService.lastDebugLines
            lines.append("finalize error: \(localizedDescription(for: error))")
            diagnosticsReport = lines.joined(separator: "\n")
            throw error
        }
    }

    func linkDocument(documentId: UUID, courseId: String, assignmentId: String, mode: GSLinkMode) {
        linkStore.upsertLink(documentId: documentId, courseId: courseId, assignmentId: assignmentId, mode: mode)
    }

    func linkedDocument(for documentId: UUID) -> GSLinkedDocument? {
        linkStore.link(for: documentId)
    }

    private func localizedDescription(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
