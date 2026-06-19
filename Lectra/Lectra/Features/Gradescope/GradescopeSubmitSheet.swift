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

    private var diagnosticsPresentation: TechnicalDetailsPresentation? {
        TechnicalDetailsPresentation.make(
            summary: "Technical details are available for the current Gradescope submission attempt.",
            details: gradescopeManager.latestDiagnosticsReport()
        )
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
                            .font(LectraTypography.caption)
                            .foregroundColor(LectraColor.accentDestructive)
                    }

                    if let managerError = gradescopeManager.errorMessage {
                        Text(managerError)
                            .font(LectraTypography.caption)
                            .foregroundColor(LectraColor.accentDestructive)
                    }

                    if let diagnosticsPresentation {
                        TechnicalDetailsDisclosure(
                            presentation: diagnosticsPresentation,
                            accessibilityID: "gradescope.submit.technicalDetails"
                        )
                    }
                }
                .padding(16)
            }
            .background(
                ZStack {
                    LectraColor.background.ignoresSafeArea()
                    LectraGradient.appBackdrop.opacity(0.72).ignoresSafeArea()
                }
            )
            .navigationTitle("Submit to Gradescope")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(LectraColor.accentSoft)
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
        .onChange(of: localError) { _, newValue in
            guard let newValue else { return }
            postAccessibilityAnnouncement(newValue)
        }
        .onChange(of: gradescopeManager.errorMessage) { _, newValue in
            guard let newValue else { return }
            postAccessibilityAnnouncement(newValue)
        }
        .onChange(of: submitReceipt?.submittedAt) { _, newValue in
            guard newValue != nil, let receipt = submitReceipt else { return }
            postAccessibilityAnnouncement(
                receipt.isDryRun
                    ? "Gradescope dry run completed."
                    : "Gradescope submission recorded."
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Submission Packet", systemImage: "doc.badge.arrow.up")
                .font(LectraTypography.caption)
                .foregroundColor(LectraColor.accentSoft)

            Text(document.title)
                .font(LectraTypography.titleSmall)
                .foregroundColor(LectraColor.textPrimary)

            if let url = exportURL,
               let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attr[.size] as? NSNumber {
                Text("File: \(url.lastPathComponent) • \(ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file))")
                    .font(LectraTypography.captionMedium)
                    .foregroundColor(LectraColor.textSecondary)
            } else {
                Text("No local PDF available for submission.")
                    .font(LectraTypography.captionMedium)
                    .foregroundColor(LectraColor.accentDestructive)
            }
        }
        .padding(12)
        .background(submissionCardBackground)
    }

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in to Gradescope")
                .font(LectraTypography.headlineMedium)
                .foregroundColor(LectraColor.textPrimary)

            TextField("Email", text: $loginEmail)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(LectraTypography.body)
                .padding(10)
                .background(submissionInputBackground)

            SecureField("Password", text: $loginPassword)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(LectraTypography.body)
                .padding(10)
                .background(submissionInputBackground)

            Button {
                LectraHaptics.tap()
                Task {
                    await gradescopeManager.login(email: loginEmail, password: loginPassword)
                    if gradescopeManager.isAuthenticated {
                        hydrateLinkedAssignment()
                    }
                }
            } label: {
                HStack {
                    if gradescopeManager.isBusy {
                        ProgressView().tint(LectraColor.textPrimary)
                    }
                    Text("Sign In")
                }
            }
            .buttonStyle(LectraPrimaryButtonStyle(disabled: gradescopeManager.isBusy))
            .disabled(gradescopeManager.isBusy)
        }
        .padding(12)
        .background(submissionCardBackground)
    }

    private var assignmentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Assignment")
                    .font(LectraTypography.headlineMedium)
                    .foregroundColor(LectraColor.textPrimary)

                Spacer()

                Button("Pick") {
                    LectraHaptics.selection()
                    showPicker = true
                }
                .font(LectraTypography.caption)
                .foregroundColor(LectraColor.accentSoft)
            }

            if let assignment = selectedAssignment {
                Text(assignment.name)
                    .font(LectraTypography.bodyEmphasis)
                    .foregroundColor(LectraColor.textPrimary)

                if let course = selectedCourse {
                        Text(course.shortName)
                            .font(LectraTypography.captionMedium)
                            .foregroundColor(LectraColor.textSecondary)
                }

                if let due = assignment.dueDate {
                        Text("Due \(due.formatted(date: .abbreviated, time: .shortened))")
                            .font(LectraTypography.captionMedium)
                            .foregroundColor(LectraColor.textSecondary)
                }
            } else {
                Text("No assignment selected.")
                    .font(LectraTypography.captionMedium)
                    .foregroundColor(LectraColor.textTertiary)
            }
        }
        .padding(12)
        .background(submissionCardBackground)
    }

    private var preflightCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preflight")
                .font(LectraTypography.headlineMedium)
                .foregroundColor(LectraColor.textPrimary)

            Button {
                LectraHaptics.selection()
                Task { await runPreflight() }
            } label: {
                HStack {
                    if isRunningPreflight {
                        ProgressView().tint(LectraColor.textPrimary)
                    }
                    Text("Run Preflight")
                }
            }
            .buttonStyle(LectraSecondaryButtonStyle())
            .disabled(isRunningPreflight || selectedAssignment == nil)

            if let result = preflightResult {
                LectraStatusBadge(
                    title: result.isReady ? "Ready" : "Fix issues before submit",
                    color: LectraColor.accentSoft,
                    size: .large
                )

                ForEach(result.issues, id: \.self) { issue in
                    Text("• \(issue)")
                        .font(LectraTypography.captionMedium)
                        .foregroundColor(LectraColor.accentDestructive)
                }

                ForEach(result.warnings, id: \.self) { warning in
                    Text("• \(warning)")
                        .font(LectraTypography.captionMedium)
                        .foregroundColor(LectraColor.warning)
                }
            }
        }
        .padding(12)
        .background(submissionCardBackground)
    }

    private var submitCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Submit")
                .font(LectraTypography.headlineMedium)
                .foregroundColor(LectraColor.textPrimary)

            Toggle(isOn: $confirmationChecked) {
                Text("I confirm this should be submitted")
                    .font(LectraTypography.captionMedium)
                    .foregroundColor(LectraColor.textPrimary)
            }
            .tint(LectraColor.accentSoft)

            if let workflow {
                workflowProgressView(workflow)
            }

            if let uploadResult, uploadResult.status == .uploadedNeedsFinalize {
                if workflow?.requiresGroupStep == true {
                    Button("Edit Group Members") {
                        LectraHaptics.selection()
                        showGroupSheet = true
                    }
                    .font(LectraTypography.caption)
                    .foregroundColor(LectraColor.accentSoft)
                }

                if workflow?.requiresPageStep == true {
                    Button("Edit Page Assignment") {
                        LectraHaptics.selection()
                        showPageSheet = true
                    }
                    .font(LectraTypography.caption)
                    .foregroundColor(LectraColor.accentSoft)
                }

                Button {
                    LectraHaptics.tap()
                    Task { await finalizeSubmission() }
                } label: {
                    HStack {
                        if isFinalizing {
                            ProgressView().tint(LectraColor.textPrimary)
                        }
                        Text("Finalize Submission")
                    }
                }
                .buttonStyle(LectraPrimaryButtonStyle(disabled: isFinalizing || !canFinalize))
                .disabled(isFinalizing || !canFinalize)
            }

            Button {
                LectraHaptics.tap()
                Task { await uploadPDF() }
            } label: {
                HStack {
                    if isUploading {
                        ProgressView().tint(LectraColor.textPrimary)
                    }
                    Text("Upload PDF")
                }
            }
            .buttonStyle(LectraSecondaryButtonStyle())
            .disabled(isUploading || isFinalizing || selectedAssignment == nil || exportURL == nil || !confirmationChecked)

            if let activeURL = uploadResult?.submissionURL ?? submitReceipt?.submissionURL {
                Button("Open Submission Editor (Emergency Fallback)") {
                    LectraHaptics.selection()
                    manageSubmissionURL = activeURL
                    showManageSubmissionSheet = true
                }
                .font(LectraTypography.caption)
                .foregroundColor(LectraColor.accentSoft)
            }

            if let receipt = submitReceipt {
                Text(receipt.isDryRun ? "Dry-run passed." : "Final submission recorded.")
                    .font(LectraTypography.caption)
                    .foregroundColor(LectraColor.accentSoft)

                if let submissionURL = receipt.submissionURL {
                        Text(submissionURL.absoluteString)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(LectraColor.textSecondary)
                            .textSelection(.enabled)
                }
            }
        }
        .padding(12)
        .background(submissionCardBackground)
    }

    @ViewBuilder
    private func workflowProgressView(_ workflow: GSSubmissionWorkflow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Workflow ID: \(workflow.id.prefix(8))…")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(LectraColor.textTertiary)

            if workflow.requiresGroupStep {
                Text(groupMembers.isEmpty ? "Group step pending" : "Group members ready (\(groupMembers.count))")
                    .font(LectraTypography.caption)
                    .foregroundColor(groupMembers.isEmpty ? LectraColor.warning : LectraColor.accentSoft)
            }

            if workflow.requiresPageStep {
                Text(pageAssignments.isEmpty ? "Page mapping pending" : "Page mapping ready (\(pageAssignments.count) questions)")
                    .font(LectraTypography.caption)
                    .foregroundColor(pageAssignments.isEmpty ? LectraColor.warning : LectraColor.accentSoft)
            }

            if workflow.finalized {
                Text("Workflow finalized")
                    .font(LectraTypography.caption)
                    .foregroundColor(LectraColor.accentSoft)
            }
        }
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

    private var submissionCardBackground: some View {
        RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
            .fill(LectraColor.surfaceElevated.opacity(0.76))
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
    }

    private var submissionInputBackground: some View {
        RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
            .fill(LectraColor.surfaceFloating.opacity(0.88))
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
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
            if preflightResult?.isReady == true {
                LectraHaptics.success()
            } else {
                LectraHaptics.warning()
            }
        } catch {
            preflightResult = nil
            LectraHaptics.warning()
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
                LectraHaptics.success()
                gradescopeManager.linkDocument(
                    documentId: document.id,
                    courseId: course.id,
                    assignmentId: assignment.id,
                    mode: .direct
                )
            case .uploadedNeedsFinalize:
                LectraHaptics.selection()
                if uploaded.nextAction == .manageGroupMembers {
                    showGroupSheet = true
                } else if uploaded.nextAction == .assignPages {
                    showPageSheet = true
                }
            }
        } catch {
            LectraHaptics.warning()
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
            LectraHaptics.success()

            gradescopeManager.linkDocument(
                documentId: document.id,
                courseId: course.id,
                assignmentId: assignment.id,
                mode: .direct
            )
        } catch {
            LectraHaptics.warning()
            localError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
