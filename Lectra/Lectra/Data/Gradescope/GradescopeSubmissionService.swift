import Foundation
import CryptoKit

final class GradescopeSubmissionService: GradescopeSubmitting {
    private struct WorkflowState {
        let draft: GSSubmissionDraft
        let preflight: GSPreflightResult
        var uploadPageURL: URL
        var uploadContract: GSSubmissionFormContract
        var finalizationPageURL: URL?
        var finalizationContract: GSSubmissionFormContract?
        var requiresGroupStep: Bool
        var requiresPageStep: Bool
        var detectedQuestions: [GSPageQuestion]
        var detectedPageCount: Int?
        var groupMembers: [GSGroupMemberDraft]
        var pageAssignments: [GSPageAssignmentDraft]
        var uploadSubmissionURL: URL?
        var finalizedSubmissionURL: URL?
        var uploadedAt: Date?
    }

    private let httpClient: GradescopeHTTPClient
    private let parser: GradescopeHTMLParser
    private let linkStore: GradescopeLinkStore
    private let webRunner: GradescopeSubmissionWebRunner
    private(set) var lastDebugLines: [String] = []

    private var workflows: [String: WorkflowState] = [:]

    init(
        httpClient: GradescopeHTTPClient,
        parser: GradescopeHTMLParser,
        linkStore: GradescopeLinkStore,
        webRunner: GradescopeSubmissionWebRunner
    ) {
        self.httpClient = httpClient
        self.parser = parser
        self.linkStore = linkStore
        self.webRunner = webRunner
    }

    // MARK: - Preflight

    func preflight(draft: GSSubmissionDraft) async throws -> GSPreflightResult {
        let result = try await preflightWithDebug(draft: draft)
        return result.preflight
    }

    func preflightWithDebug(draft: GSSubmissionDraft) async throws -> (preflight: GSPreflightResult, debugLines: [String]) {
        var issues: [String] = []
        var warnings: [String] = []
        var fileHash: String?
        var fileSizeBytes: Int64?
        var debugLines: [String] = []
        debugLines.append("GS-PREFLIGHT-START")
        debugLines.append("preflight course=\(draft.courseId) assignment=\(draft.assignmentId)")
        defer { lastDebugLines = debugLines }

        guard FileManager.default.fileExists(atPath: draft.localFileURL.path) else {
            debugLines.append("GS-PREFLIGHT-MISSING-FILE")
            throw GSError.fileNotFound
        }

        if draft.localFileURL.pathExtension.lowercased() != "pdf" {
            issues.append("Only PDF files are supported.")
            debugLines.append("GS-PREFLIGHT-NON-PDF")
        }

        let data = try Data(contentsOf: draft.localFileURL)
        if data.isEmpty {
            issues.append("File is empty.")
            debugLines.append("GS-PREFLIGHT-EMPTY")
        }

        let pdfHeader = Data([0x25, 0x50, 0x44, 0x46, 0x2D])
        if !data.starts(with: pdfHeader) {
            issues.append("File does not have a valid PDF header.")
            debugLines.append("GS-PREFLIGHT-INVALID-HEADER")
        }

        fileHash = data.sha256HexString
        fileSizeBytes = Int64(data.count)

        if let fileHash,
           linkStore.wasRecentlySubmitted(assignmentId: draft.assignmentId, fileHash: fileHash, within: 60) {
            issues.append("This file was submitted to the same assignment in the last minute.")
            debugLines.append("GS-PREFLIGHT-DUPLICATE")
        }

        if data.count > 25 * 1024 * 1024 {
            warnings.append("File is larger than 25 MB. Gradescope may reject large uploads.")
            debugLines.append("GS-PREFLIGHT-LARGE-FILE")
        }

        let result = GSPreflightResult(
            isReady: issues.isEmpty,
            issues: issues,
            warnings: warnings,
            fileSHA256: fileHash,
            fileSizeBytes: fileSizeBytes
        )
        debugLines.append("GS-PREFLIGHT-COMPLETE ready=\(result.isReady)")
        return (result, debugLines)
    }

    // MARK: - Workflow API

    func prepareSubmissionWorkflow(draft: GSSubmissionDraft) async throws -> GSSubmissionWorkflow {
        var debugLines: [String] = ["GS-WORKFLOW-PREPARE-START"]
        defer { lastDebugLines = debugLines }

        let preflight = try await preflight(draft: draft)
        guard preflight.isReady else {
            debugLines.append("GS-WORKFLOW-PREFLIGHT-NOT-READY")
            throw GSError.workflowIncomplete("Preflight must pass before preparing submission.")
        }

        let coursePath = "/courses/\(draft.courseId)"
        let coursePage = try await httpClient.get(path: coursePath)
        guard coursePage.response.statusCode == 200 else {
            if coursePage.response.statusCode == 401 || coursePage.response.statusCode == 403 {
                throw GSError.unauthorized
            }
            throw GSError.network("Could not open course page (\(coursePage.response.statusCode)).")
        }

        let courseHTML = String(decoding: coursePage.data, as: UTF8.self)
        if let csrf = parser.parseCSRFToken(from: courseHTML), !csrf.isEmpty {
            httpClient.csrfToken = csrf
        }

        let uploadPagePath = "/courses/\(draft.courseId)/assignments/\(draft.assignmentId)/submissions/new"
        let uploadPage = try await httpClient.get(path: uploadPagePath, referer: coursePage.url)
        guard uploadPage.response.statusCode == 200 else {
            if uploadPage.response.statusCode == 401 || uploadPage.response.statusCode == 403 {
                throw GSError.unauthorized
            }
            throw GSError.network("Could not open submission editor (\(uploadPage.response.statusCode)).")
        }

        let uploadHTML = String(decoding: uploadPage.data, as: UTF8.self)
        if parser.isLikelyLoginPage(uploadHTML) || uploadPage.url.path.hasPrefix("/login") {
            throw GSError.unauthorized
        }

        let formSpecs = parser.parseSubmissionFormSpecs(from: uploadHTML, pageURL: uploadPage.url)
        guard let preferredSpec = selectPreferredFormSpec(formSpecs, courseId: draft.courseId, assignmentId: draft.assignmentId) else {
            debugLines.append("GS-SUBMIT-CONTRACT-MISMATCH no_form")
            throw GSError.contractMismatch
        }

        let uploadContract = normalizedContractTarget(
            buildContract(from: preferredSpec),
            courseId: draft.courseId,
            assignmentId: draft.assignmentId
        )
        let workflowId = UUID().uuidString

        let state = WorkflowState(
            draft: draft,
            preflight: preflight,
            uploadPageURL: uploadPage.url,
            uploadContract: uploadContract,
            finalizationPageURL: nil,
            finalizationContract: nil,
            requiresGroupStep: false,
            requiresPageStep: false,
            detectedQuestions: [],
            detectedPageCount: nil,
            groupMembers: [],
            pageAssignments: [],
            uploadSubmissionURL: nil,
            finalizedSubmissionURL: nil,
            uploadedAt: nil
        )

        workflows[workflowId] = state
        debugLines.append("GS-WORKFLOW-PREPARE-COMPLETE id=\(workflowId)")

        return GSSubmissionWorkflow(
            id: workflowId,
            courseId: draft.courseId,
            assignmentId: draft.assignmentId,
            uploadURL: uploadContract.targetURL,
            submissionURL: nil,
            requiresGroupStep: false,
            requiresPageStep: false,
            detectedQuestions: [],
            detectedPageCount: nil,
            finalized: false
        )
    }

    func uploadPDF(workflowId: String, confirmed: Bool) async throws -> GSUploadResult {
        var debugLines: [String] = ["GS-UPLOAD-START id=\(workflowId)"]
        defer { lastDebugLines = debugLines }

        guard confirmed else { throw GSError.confirmationRequired }
        guard var state = workflows[workflowId] else { throw GSError.workflowNotFound }

        if !GradescopeFeatureFlags.gradescopeLiveSubmitEnabled {
            debugLines.append("GS-UPLOAD-DRY-RUN")
            workflows[workflowId] = state
            return GSUploadResult(
                status: .finalized,
                submissionURL: nil,
                nextAction: .none,
                workflow: makeWorkflowSnapshot(id: workflowId, state: state)
            )
        }

        if state.preflight.fileSHA256 != nil,
           linkStore.wasRecentlySubmitted(
            assignmentId: state.draft.assignmentId,
            fileHash: state.preflight.fileSHA256 ?? "",
            within: 60
           ) {
            throw GSError.duplicateSubmission
        }
        // Re-fetch the submission page to get a fresh CSRF token.
        // The token from prepareSubmissionWorkflow may have become stale
        // (Rails rotates authenticity_token per request).
        let uploadPagePath = state.uploadPageURL.path
        debugLines.append("GS-UPLOAD-CSRF-REFRESH path=\(uploadPagePath)")
        do {
            let freshPage = try await httpClient.get(path: uploadPagePath, referer: state.uploadPageURL)
            let freshHTML = String(decoding: freshPage.data, as: UTF8.self)

            // Update CSRF from meta tag
            if let freshCSRF = parser.parseCSRFToken(from: freshHTML), !freshCSRF.isEmpty {
                httpClient.csrfToken = freshCSRF
                debugLines.append("GS-UPLOAD-CSRF-META-OK")
            }

            // Update the authenticity_token from the form's hidden fields
            let freshSpecs = parser.parseSubmissionFormSpecs(from: freshHTML, pageURL: freshPage.url)
            if let freshSpec = selectPreferredFormSpec(freshSpecs, courseId: state.draft.courseId, assignmentId: state.draft.assignmentId) {
                let freshContract = normalizedContractTarget(
                    buildContract(from: freshSpec),
                    courseId: state.draft.courseId,
                    assignmentId: state.draft.assignmentId
                )
                state.uploadContract = freshContract
                state.uploadPageURL = freshPage.url
                workflows[workflowId] = state
                debugLines.append("GS-UPLOAD-CSRF-FORM-OK token=\(freshContract.hiddenFields["authenticity_token"]?.prefix(16) ?? "nil")...")
            }
        } catch {
            debugLines.append("GS-UPLOAD-CSRF-REFRESH-FAILED error=\(error.localizedDescription)")
            // Continue with the stale token — it might still work
        }

        let requestFields = buildFields(contract: state.uploadContract, includeUploadMethod: true)
        let headers = uploadRequestHeaders(referer: state.uploadPageURL)

        let uploadResult: AttemptResult

        // Try Active Storage direct upload only if the HTML parser found the endpoint
        if let directUploadURL = state.uploadContract.directUploadURL {
            debugLines.append("GS-UPLOAD-DIRECT-START url=\(directUploadURL.path)")
            do {
                let signedBlobId = try await performDirectUpload(
                    fileURL: state.draft.localFileURL,
                    directUploadURL: directUploadURL,
                    referer: state.uploadPageURL,
                    debugLines: &debugLines
                )
                debugLines.append("GS-UPLOAD-DIRECT-BLOB-RECEIVED id=\(signedBlobId.prefix(16))...")

                var formFields = requestFields
                formFields[state.uploadContract.fileFieldName] = signedBlobId

                let response = try await httpClient.postForm(
                    path: state.uploadContract.targetURL.absoluteString,
                    fields: formFields,
                    referer: state.uploadPageURL,
                    headers: headers
                )

                let html = String(decoding: response.data, as: UTF8.self)
                debugLines.append("GS-UPLOAD-DIRECT-FORM status=\(response.response.statusCode) final=\(response.url.path)")

                let result = evaluateAttempt(
                    statusCode: response.response.statusCode,
                    finalURL: response.url,
                    html: html,
                    courseId: state.draft.courseId,
                    assignmentId: state.draft.assignmentId
                )

                if result.accepted {
                    uploadResult = result
                } else {
                    debugLines.append("GS-UPLOAD-DIRECT-FORM-REJECTED falling_back=multipart")
                    uploadResult = try await attemptLegacyUpload(
                        state: state,
                        requestFields: requestFields,
                        headers: headers,
                        debugLines: &debugLines
                    )
                }
            } catch {
                debugLines.append("GS-UPLOAD-DIRECT-FAILED error=\(error.localizedDescription) falling_back=multipart")
                uploadResult = try await attemptLegacyUpload(
                    state: state,
                    requestFields: requestFields,
                    headers: headers,
                    debugLines: &debugLines
                )
            }
        } else {
            // Standard multipart upload path
            uploadResult = try await attemptLegacyUpload(
                state: state,
                requestFields: requestFields,
                headers: headers,
                debugLines: &debugLines
            )
        }

        guard uploadResult.accepted else {
            debugLines.append("GS-SUBMIT-CONTRACT-MISMATCH")
            throw GSError.contractMismatch
        }

        let (requiresGroup, requiresPage, questions, pageCount, finalContract) = parsePostUploadState(
            html: uploadResult.html,
            pageURL: uploadResult.finalURL,
            courseId: state.draft.courseId,
            assignmentId: state.draft.assignmentId
        )

        state.uploadSubmissionURL = uploadResult.finalURL
        state.finalizationPageURL = uploadResult.finalURL
        state.finalizationContract = finalContract
        state.requiresGroupStep = requiresGroup
        state.requiresPageStep = requiresPage
        state.detectedQuestions = questions
        state.detectedPageCount = pageCount
        state.uploadedAt = Date()

        workflows[workflowId] = state

        if isFinalizedSubmissionURL(uploadResult.finalURL) && !requiresGroup && !requiresPage {
            state.finalizedSubmissionURL = uploadResult.finalURL
            workflows[workflowId] = state
            updateDuplicateGuardForFinalizedSubmission(state: state, submissionURL: uploadResult.finalURL)
            debugLines.append("GS-UPLOAD-FINALIZED")
            return GSUploadResult(
                status: .finalized,
                submissionURL: uploadResult.finalURL,
                nextAction: .none,
                workflow: makeWorkflowSnapshot(id: workflowId, state: state)
            )
        }

        let nextAction: GSUploadNextAction
        if requiresGroup {
            nextAction = .manageGroupMembers
        } else if requiresPage {
            nextAction = .assignPages
        } else {
            nextAction = .finalize
        }

        debugLines.append("GS-UPLOAD-NEEDS-FINALIZE group=\(requiresGroup) page=\(requiresPage)")
        return GSUploadResult(
            status: .uploadedNeedsFinalize,
            submissionURL: uploadResult.finalURL,
            nextAction: nextAction,
            workflow: makeWorkflowSnapshot(id: workflowId, state: state)
        )
    }

    func updateGroupMembers(workflowId: String, members: [GSGroupMemberDraft]) async throws -> GSGroupUpdateResult {
        var debugLines: [String] = ["GS-GROUP-UPDATE id=\(workflowId)"]
        defer { lastDebugLines = debugLines }

        guard var state = workflows[workflowId] else { throw GSError.workflowNotFound }
        state.groupMembers = members.filter { !$0.emailOrUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        workflows[workflowId] = state

        var warnings: [String] = []
        if state.requiresGroupStep && state.groupMembers.isEmpty {
            warnings.append("No group members provided. If this is a group assignment, add members before final submit.")
            debugLines.append("GS-GROUP-EMPTY")
        }

        return GSGroupUpdateResult(workflowId: workflowId, members: state.groupMembers, warnings: warnings)
    }

    func updatePageAssignments(workflowId: String, assignments: [GSPageAssignmentDraft]) async throws -> GSPageAssignmentResult {
        var debugLines: [String] = ["GS-PAGE-UPDATE id=\(workflowId)"]
        defer { lastDebugLines = debugLines }

        guard var state = workflows[workflowId] else { throw GSError.workflowNotFound }
        state.pageAssignments = assignments
        workflows[workflowId] = state

        var warnings: [String] = []
        if state.requiresPageStep && state.pageAssignments.isEmpty {
            warnings.append("Page assignment is required before final submit.")
            debugLines.append("GS-SUBMIT-NEEDS-PAGE-MAP")
        }

        return GSPageAssignmentResult(workflowId: workflowId, assignments: assignments, warnings: warnings)
    }

    func finalizeSubmission(workflowId: String) async throws -> GSSubmissionReceipt {
        var debugLines: [String] = ["GS-FINALIZE-START id=\(workflowId)"]
        defer { lastDebugLines = debugLines }

        guard var state = workflows[workflowId] else { throw GSError.workflowNotFound }

        if let finalizedURL = state.finalizedSubmissionURL {
            return GSSubmissionReceipt(
                assignmentId: state.draft.assignmentId,
                submittedAt: Date(),
                submissionURL: finalizedURL,
                isDryRun: false
            )
        }

        if state.requiresPageStep && state.pageAssignments.isEmpty {
            debugLines.append("GS-SUBMIT-NEEDS-PAGE-MAP")
            throw GSError.workflowIncomplete("GS-SUBMIT-NEEDS-PAGE-MAP: Assign pages before final submit.")
        }

        guard let finalizationContract = state.finalizationContract,
              let finalizationPageURL = state.finalizationPageURL else {
            if let uploadURL = state.uploadSubmissionURL,
               isFinalizedSubmissionURL(uploadURL) {
                state.finalizedSubmissionURL = uploadURL
                workflows[workflowId] = state
                updateDuplicateGuardForFinalizedSubmission(state: state, submissionURL: uploadURL)
                return GSSubmissionReceipt(
                    assignmentId: state.draft.assignmentId,
                    submittedAt: Date(),
                    submissionURL: uploadURL,
                    isDryRun: false
                )
            }
            debugLines.append("GS-SUBMIT-CONTRACT-MISMATCH finalize_contract_missing")
            throw GSError.contractMismatch
        }

        let fields = buildFinalizationFields(contract: finalizationContract, state: state)
        let headers = uploadRequestHeaders(referer: finalizationPageURL)

        let nativeResult = try await attemptNativeFormFinalize(
            finalizationPageURL: finalizationPageURL,
            contract: finalizationContract,
            fields: fields,
            headers: headers,
            debugLines: &debugLines
        )

        let finalizeResult: AttemptResult
        if nativeResult.accepted {
            finalizeResult = nativeResult
        } else {
            debugLines.append("GS-FINALIZE-NATIVE-FAILED falling_back=hidden_web")
            finalizeResult = try await attemptWebRunnerFormFinalize(
                finalizationPageURL: finalizationPageURL,
                contract: finalizationContract,
                fields: fields,
                headers: headers,
                debugLines: &debugLines
            )
        }

        guard finalizeResult.accepted else {
            debugLines.append("GS-SUBMIT-CONTRACT-MISMATCH finalize_rejected")
            throw GSError.contractMismatch
        }

        if !isFinalizedSubmissionURL(finalizeResult.finalURL) {
            if state.requiresPageStep {
                throw GSError.workflowIncomplete("GS-SUBMIT-NEEDS-PAGE-MAP: Gradescope still requires page assignment.")
            }
            throw GSError.workflowIncomplete("GS-SUBMIT-NOT-FINALIZED: Complete final steps in the submission editor.")
        }

        state.finalizedSubmissionURL = finalizeResult.finalURL
        workflows[workflowId] = state
        updateDuplicateGuardForFinalizedSubmission(state: state, submissionURL: finalizeResult.finalURL)

        debugLines.append("GS-FINALIZE-SUCCESS")
        return GSSubmissionReceipt(
            assignmentId: state.draft.assignmentId,
            submittedAt: Date(),
            submissionURL: finalizeResult.finalURL,
            isDryRun: false
        )
    }

    // MARK: - Backward Compatibility

    func submit(draft: GSSubmissionDraft, confirmed: Bool) async throws -> GSSubmissionReceipt {
        let workflow = try await prepareSubmissionWorkflow(draft: draft)
        let uploadResult = try await uploadPDF(workflowId: workflow.id, confirmed: confirmed)
        switch uploadResult.status {
        case .finalized:
            return GSSubmissionReceipt(
                assignmentId: draft.assignmentId,
                submittedAt: Date(),
                submissionURL: uploadResult.submissionURL,
                isDryRun: false
            )
        case .uploadedNeedsFinalize:
            return try await finalizeSubmission(workflowId: workflow.id)
        }
    }

    func submitWithDebug(draft: GSSubmissionDraft, confirmed: Bool) async throws -> (receipt: GSSubmissionReceipt, debugLines: [String]) {
        let receipt = try await submit(draft: draft, confirmed: confirmed)
        return (receipt, lastDebugLines)
    }

    // MARK: - Deterministic Form Building

    private func buildContract(from spec: GradescopeHTMLParser.SubmissionFormSpec) -> GSSubmissionFormContract {
        let submitButton = chooseSubmitButton(spec)
        let targetURL = submitButton?.formActionURL ?? spec.actionURL

        return GSSubmissionFormContract(
            targetURL: targetURL,
            method: (submitButton?.formMethod ?? spec.method).lowercased(),
            enctype: submitButton?.formEnctype ?? spec.enctype,
            fileFieldName: spec.fileFieldName,
            hiddenFields: spec.hiddenFields,
            defaultFields: spec.allFields,
            submitButtonSpec: submitButton,
            requiredFields: spec.requiredFields,
            directUploadURL: spec.fileInputDirectUploadURL
        )
    }

    private func buildFields(contract: GSSubmissionFormContract, includeUploadMethod: Bool) -> [String: String] {
        var fields = contract.defaultFields
        for (key, value) in contract.hiddenFields {
            fields[key] = value
        }

        if let token = fields["authenticity_token"], !token.isEmpty {
            httpClient.csrfToken = token
        } else if let csrf = httpClient.csrfToken, !csrf.isEmpty {
            fields["authenticity_token"] = csrf
        }

        if fields["utf8"] == nil {
            fields["utf8"] = "✓"
        }

        if let button = contract.submitButtonSpec,
           let name = button.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty,
           let value = button.value {
            fields[name] = value
        }

        return fields
    }

    private func buildFinalizationFields(contract: GSSubmissionFormContract, state: WorkflowState) -> [String: String] {
        var fields = buildFields(contract: contract, includeUploadMethod: false)

        if !state.groupMembers.isEmpty {
            let joinedMembers = state.groupMembers.map { $0.emailOrUserId }.joined(separator: ",")
            if let key = fields.keys.first(where: { matchesAny($0, tokens: ["group", "member", "partner"]) }) {
                fields[key] = joinedMembers
            }
        }

        for assignment in state.pageAssignments {
            let pageValue = assignment.pageIndexes.map { String($0) }.joined(separator: ",")
            let candidates = [
                "submission[question_page_mappings][\(assignment.questionId)]",
                "submission[page_assignments][\(assignment.questionId)]",
                "question_page_mapping[\(assignment.questionId)]",
                assignment.questionId
            ]

            if let existing = candidates.first(where: { fields[$0] != nil }) {
                fields[existing] = pageValue
                continue
            }

            if let key = fields.keys.first(where: { $0.localizedCaseInsensitiveContains(assignment.questionId) }) {
                fields[key] = pageValue
            }
        }

        return fields
    }

    private func chooseSubmitButton(_ spec: GradescopeHTMLParser.SubmissionFormSpec) -> GSSubmissionSubmitButton? {
        guard !spec.submitButtons.isEmpty else { return nil }
        return spec.submitButtons.sorted { lhs, rhs in
            scoreSubmitButton(lhs, fallbackAction: spec.actionURL) > scoreSubmitButton(rhs, fallbackAction: spec.actionURL)
        }.first
    }

    private func scoreSubmitButton(_ button: GSSubmissionSubmitButton, fallbackAction: URL) -> Int {
        let target = button.formActionURL ?? fallbackAction
        var score = 0
        if target.path.hasSuffix("/submissions") { score += 100 }
        if target.path.hasSuffix("/submissions/new") { score += 20 }
        if button.label.lowercased().contains("submit") { score += 12 }
        if button.value?.lowercased().contains("submit") == true { score += 10 }
        if button.label.lowercased().contains("upload") { score += 8 }
        if let method = button.formMethod, method == "post" { score += 6 }
        return score
    }

    // MARK: - Upload and Finalize Attempts

    private struct AttemptResult {
        let accepted: Bool
        let finalURL: URL
        let html: String
    }

    // MARK: Active Storage Direct Upload

    private func performDirectUpload(
        fileURL: URL,
        directUploadURL: URL,
        referer: URL,
        debugLines: inout [String]
    ) async throws -> String {
        let fileData = try Data(contentsOf: fileURL)
        let fileName = fileURL.lastPathComponent
        let contentType = "application/pdf"
        let byteSize = fileData.count

        // Active Storage requires a base64-encoded MD5 checksum
        let md5Digest = Insecure.MD5.hash(data: fileData)
        let checksum = Data(md5Digest).base64EncodedString()

        debugLines.append("GS-UPLOAD-DIRECT-META filename=\(fileName) size=\(byteSize)")

        // Phase 1: POST metadata to the direct upload endpoint to get a signed upload URL and blob ID
        let blobPayload: [String: Any] = [
            "blob": [
                "filename": fileName,
                "content_type": contentType,
                "byte_size": byteSize,
                "checksum": checksum
            ]
        ]

        let createResponse = try await httpClient.postJSON(
            path: directUploadURL.absoluteString,
            jsonObject: blobPayload,
            referer: referer,
            headers: uploadRequestHeaders(referer: referer)
        )

        guard createResponse.response.statusCode == 200 || createResponse.response.statusCode == 201 else {
            debugLines.append("GS-UPLOAD-DIRECT-CREATE-FAILED status=\(createResponse.response.statusCode)")
            throw GSError.uploadFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: createResponse.data) as? [String: Any] else {
            debugLines.append("GS-UPLOAD-DIRECT-CREATE-PARSE-FAILED")
            throw GSError.parsingFailed("Could not parse direct upload response.")
        }

        guard let signedId = json["signed_id"] as? String, !signedId.isEmpty else {
            debugLines.append("GS-UPLOAD-DIRECT-NO-SIGNED-ID")
            throw GSError.parsingFailed("Direct upload response missing signed_id.")
        }

        let directUpload = json["direct_upload"] as? [String: Any]
        let uploadURLString = directUpload?["url"] as? String
        let uploadHeaders = directUpload?["headers"] as? [String: String] ?? [:]

        debugLines.append("GS-UPLOAD-DIRECT-CREATE-OK signed_id=\(signedId.prefix(16))...")

        // Phase 2: PUT the raw file bytes to the signed cloud storage URL
        if let uploadURLString, let uploadURL = URL(string: uploadURLString) {
            debugLines.append("GS-UPLOAD-DIRECT-PUT host=\(uploadURL.host ?? "unknown")")
            var putHeaders = uploadHeaders
            putHeaders["Content-Type"] = contentType

            let putResponse = try await httpClient.put(
                url: uploadURL,
                data: fileData,
                headers: putHeaders,
                referer: referer
            )

            let putStatus = putResponse.response.statusCode
            debugLines.append("GS-UPLOAD-DIRECT-PUT-DONE status=\(putStatus)")

            guard (200...299).contains(putStatus) else {
                debugLines.append("GS-UPLOAD-DIRECT-PUT-FAILED status=\(putStatus)")
                throw GSError.uploadFailed
            }
        } else {
            // Some Active Storage configurations handle storage server-side during the create call;
            // the signed_id alone is sufficient in that case.
            debugLines.append("GS-UPLOAD-DIRECT-NO-PUT-URL (server-side storage)")
        }

        return signedId
    }

    // MARK: Legacy Multipart Upload (Native → Web fallback)

    private func attemptLegacyUpload(
        state: WorkflowState,
        requestFields: [String: String],
        headers: [String: String],
        debugLines: inout [String]
    ) async throws -> AttemptResult {
        let fileFieldCandidates = uploadFileFieldCandidates(contract: state.uploadContract)
        debugLines.append("GS-UPLOAD-FILE-FIELD-CANDIDATES \(fileFieldCandidates.joined(separator: "|"))")

        let nativeResult = try await attemptNativeMultipartUpload(
            state: state,
            fields: requestFields,
            headers: headers,
            fileFieldCandidates: fileFieldCandidates,
            debugLines: &debugLines
        )

        if nativeResult.accepted {
            return nativeResult
        }

        debugLines.append("GS-UPLOAD-NATIVE-FAILED falling_back=hidden_web")
        let webResult = try await attemptWebRunnerMultipartUpload(
            state: state,
            fields: requestFields,
            headers: headers,
            fileFieldCandidates: fileFieldCandidates,
            debugLines: &debugLines
        )

        if webResult.accepted {
            return webResult
        }

        // Final fallback: submit via the DOM form in WKWebView.
        // This uses the page's own CSRF token and cookies, bypassing
        // any mismatch between the app's URLSession and the server.
        debugLines.append("GS-UPLOAD-WEB-FAILED falling_back=dom_form")
        do {
            let domResult = try await webRunner.runDOMFormSubmission(
                pageURL: state.uploadPageURL,
                fileURL: state.draft.localFileURL
            )
            let html = domResult.bodyHTML
            debugLines.append("GS-UPLOAD-DOM status=\(domResult.statusCode) final=\(domResult.finalURL.path)")

            return evaluateAttempt(
                statusCode: domResult.statusCode,
                finalURL: domResult.finalURL,
                html: html,
                courseId: state.draft.courseId,
                assignmentId: state.draft.assignmentId
            )
        } catch {
            debugLines.append("GS-UPLOAD-DOM-FAILED error=\(error.localizedDescription)")
            return webResult
        }
    }

    private func attemptNativeMultipartUpload(
        state: WorkflowState,
        fields: [String: String],
        headers: [String: String],
        fileFieldCandidates: [String],
        debugLines: inout [String]
    ) async throws -> AttemptResult {
        var latest = AttemptResult(accepted: false, finalURL: state.uploadPageURL, html: "")
        for fileField in fileFieldCandidates {
            let response = try await httpClient.postMultipart(
                path: state.uploadContract.targetURL.absoluteString,
                fields: fields,
                fileFieldName: fileField,
                fileURL: state.draft.localFileURL,
                mimeType: "application/pdf",
                referer: state.uploadPageURL,
                headers: headers
            )

            let html = String(decoding: response.data, as: UTF8.self)
            debugLines.append("GS-UPLOAD-NATIVE status=\(response.response.statusCode) final=\(response.url.path) fileField=\(fileField)")

            // Diagnostic: capture 422 response body to understand rejection reason
            if response.response.statusCode == 422 {
                let snippet = String(html.prefix(500))
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                debugLines.append("GS-UPLOAD-NATIVE-422-BODY \(snippet)")
                if let flash = parser.parseFlashErrorMessage(from: html), !flash.isEmpty {
                    debugLines.append("GS-UPLOAD-NATIVE-422-FLASH \(flash)")
                }
            }

            latest = evaluateAttempt(
                statusCode: response.response.statusCode,
                finalURL: response.url,
                html: html,
                courseId: state.draft.courseId,
                assignmentId: state.draft.assignmentId
            )
            if latest.accepted {
                return latest
            }
        }
        return latest
    }

    private func attemptWebRunnerMultipartUpload(
        state: WorkflowState,
        fields: [String: String],
        headers: [String: String],
        fileFieldCandidates: [String],
        debugLines: inout [String]
    ) async throws -> AttemptResult {
        var latest = AttemptResult(accepted: false, finalURL: state.uploadPageURL, html: "")
        for fileField in fileFieldCandidates {
            let result = try await webRunner.runMultipartSubmission(
                pageURL: state.uploadPageURL,
                targetURL: state.uploadContract.targetURL,
                fields: fields,
                fileFieldName: fileField,
                fileURL: state.draft.localFileURL,
                headers: headers
            )
            debugLines.append("GS-UPLOAD-WEB status=\(result.statusCode) final=\(result.finalURL.path) fileField=\(fileField)")

            latest = evaluateAttempt(
                statusCode: result.statusCode,
                finalURL: result.finalURL,
                html: result.bodyHTML,
                courseId: state.draft.courseId,
                assignmentId: state.draft.assignmentId
            )
            if latest.accepted {
                return latest
            }
        }
        return latest
    }

    private func attemptNativeFormFinalize(
        finalizationPageURL: URL,
        contract: GSSubmissionFormContract,
        fields: [String: String],
        headers: [String: String],
        debugLines: inout [String]
    ) async throws -> AttemptResult {
        let response = try await httpClient.postForm(
            path: contract.targetURL.absoluteString,
            fields: fields,
            referer: finalizationPageURL,
            headers: headers
        )

        let html = String(decoding: response.data, as: UTF8.self)
        debugLines.append("GS-FINALIZE-NATIVE status=\(response.response.statusCode) final=\(response.url.path)")

        return evaluateAttempt(
            statusCode: response.response.statusCode,
            finalURL: response.url,
            html: html,
            courseId: "",
            assignmentId: ""
        )
    }

    private func attemptWebRunnerFormFinalize(
        finalizationPageURL: URL,
        contract: GSSubmissionFormContract,
        fields: [String: String],
        headers: [String: String],
        debugLines: inout [String]
    ) async throws -> AttemptResult {
        let result = try await webRunner.runFormSubmission(
            pageURL: finalizationPageURL,
            targetURL: contract.targetURL,
            fields: fields,
            headers: headers
        )
        debugLines.append("GS-FINALIZE-WEB status=\(result.statusCode) final=\(result.finalURL.path)")

        return evaluateAttempt(
            statusCode: result.statusCode,
            finalURL: result.finalURL,
            html: result.bodyHTML,
            courseId: "",
            assignmentId: ""
        )
    }

    private func evaluateAttempt(
        statusCode: Int,
        finalURL: URL,
        html: String,
        courseId: String,
        assignmentId: String
    ) -> AttemptResult {
        if statusCode == 401 || statusCode == 403 { return AttemptResult(accepted: false, finalURL: finalURL, html: html) }
        if finalURL.path.hasPrefix("/login") { return AttemptResult(accepted: false, finalURL: finalURL, html: html) }
        if [404, 422].contains(statusCode) { return AttemptResult(accepted: false, finalURL: finalURL, html: html) }

        if let flash = parser.parseFlashErrorMessage(from: html), !flash.isEmpty {
            return AttemptResult(accepted: false, finalURL: finalURL, html: html)
        }

        let normalized = html.lowercased()
        if normalized.contains("404 error") || normalized.contains("422 error") {
            return AttemptResult(accepted: false, finalURL: finalURL, html: html)
        }

        if !courseId.isEmpty, !assignmentId.isEmpty {
            let hardFailurePath = "/courses/\(courseId)"
            if finalURL.path == hardFailurePath {
                return AttemptResult(accepted: false, finalURL: finalURL, html: html)
            }
        }

        return AttemptResult(accepted: true, finalURL: finalURL, html: html)
    }

    // MARK: - Requirement Parsing

    private func parsePostUploadState(
        html: String,
        pageURL: URL,
        courseId: String,
        assignmentId: String
    ) -> (requiresGroup: Bool, requiresPage: Bool, questions: [GSPageQuestion], pageCount: Int?, finalContract: GSSubmissionFormContract?) {
        let normalized = html.lowercased()

        let requiresGroup =
            normalized.contains("manage group")
            || normalized.contains("group members")
            || normalized.contains("add group members")
            || normalized.contains("partner")

        let requiresPage =
            normalized.contains("assign pages")
            || normalized.contains("page assignment")
            || normalized.contains("assign each page")

        let questions = parseQuestions(from: html)
        let pageCount = parsePageCount(from: html)

        let finalSpecs = parser.parseSubmissionFormSpecs(from: html, pageURL: pageURL)
        let finalSpec = selectPreferredFormSpec(finalSpecs, courseId: courseId, assignmentId: assignmentId)
        let finalContract = finalSpec.map {
            normalizedContractTarget(
                buildContract(from: $0),
                courseId: courseId,
                assignmentId: assignmentId
            )
        }

        return (requiresGroup, requiresPage, questions, pageCount, finalContract)
    }

    private func parseQuestions(from html: String) -> [GSPageQuestion] {
        var questions: [GSPageQuestion] = []
        var seen = Set<String>()

        let patterns = [
            "data-question-id=[\"']([^\"']+)[\"'][^>]*data-question-title=[\"']([^\"']+)[\"']",
            "data-question-id=[\"']([^\"']+)[\"'][^>]*>([^<]{1,120})<",
            "question[_-]?id[\"']?\\s*[:=]\\s*[\"']([^\"']+)[\"'][\\s\\S]{0,160}?title[\"']?\\s*[:=]\\s*[\"']([^\"']+)[\"']"
        ]

        for pattern in patterns {
            let matches = captures(in: html, pattern: pattern)
            for match in matches {
                guard match.count >= 3 else { continue }
                let id = match[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let title = match[2].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty, seen.insert(id).inserted else { continue }
                questions.append(GSPageQuestion(id: id, title: title.isEmpty ? "Question \(id)" : title))
            }
        }

        // Fallback from form field names.
        let fieldMatches = captures(
            in: html,
            pattern: "submission\\[(?:question_page_mappings|page_assignments)\\]\\[([^\\]]+)\\]"
        )
        for match in fieldMatches {
            guard match.count >= 2 else { continue }
            let id = match[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            questions.append(GSPageQuestion(id: id, title: "Question \(id)"))
        }

        return questions
    }

    private func parsePageCount(from html: String) -> Int? {
        let explicitMatches = captures(in: html, pattern: "data-page-number=[\"']([0-9]+)[\"']")
        let explicitValues = explicitMatches.compactMap { match -> Int? in
            guard match.count >= 2 else { return nil }
            return Int(match[1])
        }
        if let maxExplicit = explicitValues.max(), maxExplicit > 0 {
            return maxExplicit
        }

        let labelMatches = captures(in: html, pattern: "Page\\s+([0-9]+)")
        let labelValues = labelMatches.compactMap { match -> Int? in
            guard match.count >= 2 else { return nil }
            return Int(match[1])
        }
        return labelValues.max()
    }

    // MARK: - Utilities

    private func selectPreferredFormSpec(
        _ specs: [GradescopeHTMLParser.SubmissionFormSpec],
        courseId: String,
        assignmentId: String
    ) -> GradescopeHTMLParser.SubmissionFormSpec? {
        guard !specs.isEmpty else { return nil }
        let preferredPath = "/courses/\(courseId)/assignments/\(assignmentId)/submissions"

        return specs.sorted { lhs, rhs in
            scoreFormSpec(lhs, preferredPath: preferredPath) > scoreFormSpec(rhs, preferredPath: preferredPath)
        }.first
    }

    private func scoreFormSpec(_ spec: GradescopeHTMLParser.SubmissionFormSpec, preferredPath: String) -> Int {
        var score = 0
        if spec.actionURL.path == preferredPath { score += 120 }
        if spec.actionURL.path.hasSuffix("/submissions") { score += 50 }
        if spec.actionURL.path.hasSuffix("/submissions/new") { score += 20 }
        if spec.fileFieldName == "submission[files][]" { score += 20 }
        if spec.fileFieldName == "pdf_attachment" { score += 16 }
        if spec.enctype?.lowercased().contains("multipart/form-data") == true { score += 12 }
        if spec.method == "post" { score += 8 }
        if spec.submitButtons.contains(where: { ($0.formActionURL ?? spec.actionURL).path.hasSuffix("/submissions") }) {
            score += 15
        }
        return score
    }

    private func uploadRequestHeaders(referer: URL) -> [String: String] {
        var headers: [String: String] = [:]
        if let components = URLComponents(url: referer, resolvingAgainstBaseURL: false),
           let scheme = components.scheme,
           let host = components.host {
            if let port = components.port {
                headers["Origin"] = "\(scheme)://\(host):\(port)"
            } else {
                headers["Origin"] = "\(scheme)://\(host)"
            }
        }
        return headers
    }

    private func isFinalizedSubmissionURL(_ url: URL) -> Bool {
        let path = url.path
        guard path.contains("/submissions/") else { return false }
        guard !path.hasSuffix("/submissions") else { return false }
        guard !path.hasSuffix("/submissions/new") else { return false }
        return true
    }

    private func updateDuplicateGuardForFinalizedSubmission(state: WorkflowState, submissionURL: URL) {
        guard let hash = state.preflight.fileSHA256 else { return }
        linkStore.recordSubmission(
            documentId: state.draft.documentId,
            assignmentId: state.draft.assignmentId,
            fileHash: hash,
            submissionURL: submissionURL,
            submittedAt: Date()
        )
    }

    private func normalizedContractTarget(
        _ contract: GSSubmissionFormContract,
        courseId: String,
        assignmentId: String
    ) -> GSSubmissionFormContract {
        guard contract.method.lowercased() == "post" else { return contract }
        guard contract.targetURL.path.hasSuffix("/submissions/new") else { return contract }

        var components = URLComponents(url: contract.targetURL, resolvingAgainstBaseURL: false)
        components?.path = "/courses/\(courseId)/assignments/\(assignmentId)/submissions"
        guard let canonicalURL = components?.url else { return contract }

        return GSSubmissionFormContract(
            targetURL: canonicalURL,
            method: contract.method,
            enctype: contract.enctype,
            fileFieldName: contract.fileFieldName,
            hiddenFields: contract.hiddenFields,
            defaultFields: contract.defaultFields,
            submitButtonSpec: contract.submitButtonSpec,
            requiredFields: contract.requiredFields,
            directUploadURL: contract.directUploadURL
        )
    }

    private func uploadFileFieldCandidates(contract: GSSubmissionFormContract) -> [String] {
        var candidates = [contract.fileFieldName]
        // Add common Gradescope field name variants as fallbacks
        if contract.targetURL.path.hasSuffix("/submissions") {
            candidates.append("pdf_attachment")
            candidates.append("submission[pdf_attachment]")
            candidates.append("submission[files][]")
        }
        return uniquePreservingOrder(candidates)
    }

    private func makeWorkflowSnapshot(id: String, state: WorkflowState) -> GSSubmissionWorkflow {
        GSSubmissionWorkflow(
            id: id,
            courseId: state.draft.courseId,
            assignmentId: state.draft.assignmentId,
            uploadURL: state.uploadContract.targetURL,
            submissionURL: state.finalizedSubmissionURL ?? state.uploadSubmissionURL,
            requiresGroupStep: state.requiresGroupStep,
            requiresPageStep: state.requiresPageStep,
            detectedQuestions: state.detectedQuestions,
            detectedPageCount: state.detectedPageCount,
            finalized: state.finalizedSubmissionURL != nil
        )
    }

    private func matchesAny(_ text: String, tokens: [String]) -> Bool {
        let normalized = text.lowercased()
        return tokens.contains { normalized.contains($0.lowercased()) }
    }

    private func captures(in text: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)

        return matches.map { match in
            (0..<match.numberOfRanges).compactMap { idx in
                let matchRange = match.range(at: idx)
                guard matchRange.location != NSNotFound else { return nil }
                return nsText.substring(with: matchRange)
            }
        }
    }

    private func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in values {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        return result
    }
}
