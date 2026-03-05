import SwiftUI
import UIKit

struct GradescopeSubmitSheet: View {
    @EnvironmentObject private var gradescopeManager: GradescopeManager
    @Environment(\.dismiss) private var dismiss

    let document: LocalDocument
    let repository: DocumentRepository

    @State private var loginEmail = ""
    @State private var loginPassword = ""

    @State private var selectedCourse: GSCourse?
    @State private var selectedAssignment: GSAssignment?

    @State private var showPicker = false
    @State private var isRunningPreflight = false
    @State private var isUploading = false
    @State private var isFinalizing = false
    @State private var preflightResult: GSPreflightResult?
    @State private var submitReceipt: GSSubmissionReceipt?
    @State private var confirmationChecked = false
    @State private var localError: String?

    @State private var workflow: GSSubmissionWorkflow?
    @State private var uploadResult: GSUploadResult?
    @State private var groupMembers: [GSGroupMemberDraft] = []
    @State private var pageAssignments: [GSPageAssignmentDraft] = []

    @State private var showGroupSheet = false
    @State private var showPageSheet = false

    @State private var showManageSubmissionSheet = false
    @State private var manageSubmissionURL: URL?

    private var exportURL: URL? {
        let annotatedURL = repository.localPDFURL(for: document.id)
            .deletingLastPathComponent()
            .appendingPathComponent("annotated.pdf")

        if FileManager.default.fileExists(atPath: annotatedURL.path) {
            return annotatedURL
        }

        return document.localPDFURL
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if gradescopeManager.isAuthenticated {
                        assignmentCard
                        preflightCard
                        submitCard
                    } else {
                        loginCard
                    }

                    if let localError {
                        Text(localError)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: 0xE84D4D))
                    }

                    if let managerError = gradescopeManager.errorMessage {
                        Text(managerError)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: 0xE84D4D))
                    }

                    if let diagnostics = gradescopeManager.latestDiagnosticsReport() {
                        diagnosticsCard(diagnostics)
                    }
                }
                .padding(16)
            }
            .background(Color(hex: 0x0D1017).ignoresSafeArea())
            .navigationTitle("Submit to Gradescope")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            GradescopeAssignmentPickerSheet { course, assignment in
                selectedCourse = course
                selectedAssignment = assignment
                resetSubmissionState()
            }
            .environmentObject(gradescopeManager)
        }
        .sheet(isPresented: $showGroupSheet) {
            GradescopeGroupMembersSheet(currentMembers: groupMembers) { members in
                groupMembers = members
            }
        }
        .sheet(isPresented: $showPageSheet) {
            GradescopePageAssignmentSheet(
                questions: workflow?.detectedQuestions ?? [],
                existingAssignments: pageAssignments,
                pageCount: workflow?.detectedPageCount
            ) { assignments in
                pageAssignments = assignments
            }
        }
        .sheet(isPresented: $showManageSubmissionSheet) {
            if let manageSubmissionURL {
                GradescopeSubmissionWebSheet(url: manageSubmissionURL)
            }
        }
        .onAppear {
            hydrateLinkedAssignment()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(document.title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(.white)

            if let url = exportURL,
               let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attr[.size] as? NSNumber {
                Text("File: \(url.lastPathComponent) • \(ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file))")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.72))
            } else {
                Text("No local PDF available for submission.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color(hex: 0xE84D4D))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in to Gradescope")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            TextField("Email", text: $loginEmail)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(10)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            SecureField("Password", text: $loginPassword)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(10)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                Task {
                    await gradescopeManager.login(email: loginEmail, password: loginPassword)
                    if gradescopeManager.isAuthenticated {
                        hydrateLinkedAssignment()
                    }
                }
            } label: {
                HStack {
                    if gradescopeManager.isBusy {
                        ProgressView().tint(.white)
                    }
                    Text("Sign In")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Color(hex: 0x4A222A))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(gradescopeManager.isBusy)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private var assignmentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Assignment")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Button("Pick") {
                    showPicker = true
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: 0xE84D4D))
            }

            if let assignment = selectedAssignment {
                Text(assignment.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                if let course = selectedCourse {
                    Text(course.shortName)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.72))
                }

                if let due = assignment.dueDate {
                    Text("Due \(due.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.72))
                }
            } else {
                Text("No assignment selected.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.72))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private var preflightCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preflight")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Button {
                Task { await runPreflight() }
            } label: {
                HStack {
                    if isRunningPreflight {
                        ProgressView().tint(.white)
                    }
                    Text("Run Preflight")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(isRunningPreflight || selectedAssignment == nil)

            if let result = preflightResult {
                Text(result.isReady ? "Ready" : "Fix issues before submit")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(result.isReady ? Color(hex: 0x35B77A) : Color(hex: 0xE84D4D))

                ForEach(result.issues, id: \.self) { issue in
                    Text("• \(issue)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color(hex: 0xE84D4D))
                }

                ForEach(result.warnings, id: \.self) { warning in
                    Text("• \(warning)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color(hex: 0xF0BA5C))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private var submitCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Submit")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Toggle(isOn: $confirmationChecked) {
                Text("I confirm this should be submitted")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }
            .tint(Color(hex: 0xE84D4D))

            if let workflow {
                workflowProgressView(workflow)
            }

            if let uploadResult, uploadResult.status == .uploadedNeedsFinalize {
                if workflow?.requiresGroupStep == true {
                    Button("Edit Group Members") {
                        showGroupSheet = true
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: 0xE84D4D))
                }

                if workflow?.requiresPageStep == true {
                    Button("Edit Page Assignment") {
                        showPageSheet = true
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: 0xE84D4D))
                }

                Button {
                    Task { await finalizeSubmission() }
                } label: {
                    HStack {
                        if isFinalizing {
                            ProgressView().tint(.white)
                        }
                        Text("Finalize Submission")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color(hex: 0x4A222A))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .disabled(isFinalizing || !canFinalize)
            }

            Button {
                Task { await uploadPDF() }
            } label: {
                HStack {
                    if isUploading {
                        ProgressView().tint(.white)
                    }
                    Text("Upload PDF")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .disabled(isUploading || isFinalizing || selectedAssignment == nil || exportURL == nil || !confirmationChecked)

            if let activeURL = uploadResult?.submissionURL ?? submitReceipt?.submissionURL {
                Button("Open Submission Editor (Emergency Fallback)") {
                    manageSubmissionURL = activeURL
                    showManageSubmissionSheet = true
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: 0xE84D4D))
            }

            if let receipt = submitReceipt {
                Text(receipt.isDryRun ? "Dry-run passed." : "Final submission recorded.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: 0x35B77A))

                if let submissionURL = receipt.submissionURL {
                    Text(submissionURL.absoluteString)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.75))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    @ViewBuilder
    private func workflowProgressView(_ workflow: GSSubmissionWorkflow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Workflow ID: \(workflow.id.prefix(8))…")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.65))

            if workflow.requiresGroupStep {
                Text(groupMembers.isEmpty ? "Group step pending" : "Group members ready (\(groupMembers.count))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(groupMembers.isEmpty ? Color(hex: 0xF0BA5C) : Color(hex: 0x35B77A))
            }

            if workflow.requiresPageStep {
                Text(pageAssignments.isEmpty ? "Page mapping pending" : "Page mapping ready (\(pageAssignments.count) questions)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(pageAssignments.isEmpty ? Color(hex: 0xF0BA5C) : Color(hex: 0x35B77A))
            }

            if workflow.finalized {
                Text("Workflow finalized")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: 0x35B77A))
            }
        }
    }

    @ViewBuilder
    private func diagnosticsCard(_ diagnostics: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Diagnostics")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer(minLength: 0)
                Button("Copy") {
                    UIPasteboard.general.string = diagnostics
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: 0xE84D4D))
            }

            Text(diagnostics)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private var canFinalize: Bool {
        guard let workflow else { return false }
        if workflow.requiresPageStep && pageAssignments.isEmpty {
            return false
        }
        return true
    }

    private func resetSubmissionState() {
        confirmationChecked = false
        preflightResult = nil
        submitReceipt = nil
        localError = nil
        workflow = nil
        uploadResult = nil
        groupMembers = []
        pageAssignments = []
        manageSubmissionURL = nil
    }

    private func hydrateLinkedAssignment() {
        guard gradescopeManager.isAuthenticated else { return }

        if gradescopeManager.courses.isEmpty {
            Task { await gradescopeManager.refreshCourses() }
        }

        guard let link = gradescopeManager.linkedDocument(for: document.id) else { return }
        if let course = gradescopeManager.courses.first(where: { $0.id == link.courseId }) {
            selectedCourse = course
        }

        Task {
            await gradescopeManager.refreshAssignments(for: link.courseId)
            if let assignment = gradescopeManager.assignments(for: link.courseId)
                .first(where: { $0.id == link.assignmentId }) {
                selectedAssignment = assignment
            }
        }
    }

    private func runPreflight() async {
        localError = nil
        submitReceipt = nil

        guard let assignment = selectedAssignment,
              let exportURL else {
            localError = "Select an assignment and ensure the PDF exists locally."
            return
        }

        isRunningPreflight = true
        defer { isRunningPreflight = false }

        do {
            preflightResult = try await gradescopeManager.preflight(
                documentId: document.id,
                fileURL: exportURL,
                courseId: assignment.courseId,
                assignmentId: assignment.id
            )
        } catch {
            preflightResult = nil
            localError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func uploadPDF() async {
        localError = nil
        submitReceipt = nil

        guard let assignment = selectedAssignment,
              let course = selectedCourse,
              let exportURL else {
            localError = "Select an assignment and ensure the PDF exists locally."
            return
        }

        if preflightResult == nil {
            await runPreflight()
        }

        guard preflightResult?.isReady == true else {
            localError = "Preflight must pass before upload."
            return
        }

        isUploading = true
        defer { isUploading = false }

        do {
            let prepared = try await gradescopeManager.prepareSubmissionWorkflow(
                documentId: document.id,
                fileURL: exportURL,
                courseId: course.id,
                assignmentId: assignment.id
            )
            workflow = prepared

            let uploaded = try await gradescopeManager.uploadPDF(
                workflowId: prepared.id,
                confirmed: confirmationChecked
            )
            uploadResult = uploaded
            if let updatedWorkflow = uploaded.workflow {
                workflow = updatedWorkflow
            }
            manageSubmissionURL = uploaded.submissionURL

            switch uploaded.status {
            case .finalized:
                let receipt = GSSubmissionReceipt(
                    assignmentId: assignment.id,
                    submittedAt: Date(),
                    submissionURL: uploaded.submissionURL,
                    isDryRun: false
                )
                submitReceipt = receipt
                gradescopeManager.linkDocument(
                    documentId: document.id,
                    courseId: course.id,
                    assignmentId: assignment.id,
                    mode: .direct
                )
            case .uploadedNeedsFinalize:
                if uploaded.nextAction == .manageGroupMembers {
                    showGroupSheet = true
                } else if uploaded.nextAction == .assignPages {
                    showPageSheet = true
                }
            }
        } catch {
            localError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func finalizeSubmission() async {
        localError = nil

        guard let workflow,
              let course = selectedCourse,
              let assignment = selectedAssignment else {
            localError = "No active submission workflow. Upload the PDF first."
            return
        }

        isFinalizing = true
        defer { isFinalizing = false }

        do {
            if workflow.requiresGroupStep {
                _ = try await gradescopeManager.updateGroupMembers(workflowId: workflow.id, members: groupMembers)
            }
            if workflow.requiresPageStep {
                _ = try await gradescopeManager.updatePageAssignments(workflowId: workflow.id, assignments: pageAssignments)
            }

            let receipt = try await gradescopeManager.finalizeSubmission(workflowId: workflow.id)
            submitReceipt = receipt
            manageSubmissionURL = receipt.submissionURL

            gradescopeManager.linkDocument(
                documentId: document.id,
                courseId: course.id,
                assignmentId: assignment.id,
                mode: .direct
            )
        } catch {
            localError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
