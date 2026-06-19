import SwiftUI
import UIKit

struct GradescopeHubView: View {
    @EnvironmentObject private var gradescopeManager: GradescopeManager

    @State private var email = ""
    @State private var password = ""
    @State private var selectedCourseID = ""
    @State private var localMessage: String?
    @State private var isImportingTemplate = false
    @State private var showWebLoginSheet = false

    let onImportTemplate: (URL, String, GSAssignment) -> Void

    private var selectedCourse: GSCourse? {
        gradescopeManager.courses.first(where: { $0.id == selectedCourseID })
    }

    private var assignments: [GSAssignment] {
        guard let selectedCourse else { return [] }
        return gradescopeManager.assignments(for: selectedCourse.id)
    }

    private var assignmentDebugMessage: String? {
        guard !selectedCourseID.isEmpty else { return nil }
        return gradescopeManager.assignmentDebugMessage(for: selectedCourseID)
    }

    private var diagnosticsMessage: String? {
        gradescopeManager.latestDiagnosticsReport()
    }

    private var assignmentTechnicalDetails: TechnicalDetailsPresentation? {
        TechnicalDetailsPresentation.make(
            summary: "Technical details are available for the selected course refresh.",
            details: assignmentDebugMessage
        )
    }

    private var diagnosticsTechnicalDetails: TechnicalDetailsPresentation? {
        TechnicalDetailsPresentation.make(
            summary: "Technical details are available for the latest Gradescope sync.",
            details: diagnosticsMessage,
            excluding: assignmentDebugMessage
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 14)

            if gradescopeManager.isAuthenticated {
                authenticatedBody
            } else {
                authBody
            }
        }
        .background(LectraColor.background)
        .onChange(of: localMessage) { _, newValue in
            guard let newValue else { return }
            postAccessibilityAnnouncement(newValue)
        }
        .onChange(of: gradescopeManager.errorMessage) { _, newValue in
            guard let newValue else { return }
            postAccessibilityAnnouncement(newValue)
        }
        .onAppear {
            if gradescopeManager.isAuthenticated {
                bootstrapAuthenticatedState()
            }
        }
        .sheet(isPresented: $showWebLoginSheet) {
            GradescopeWebLoginSheet { cookies, html in
                await gradescopeManager.loginWithWebSession(cookies: cookies, accountPageHTML: html)
                if gradescopeManager.isAuthenticated {
                    bootstrapAuthenticatedState()
                    return (nil, gradescopeManager.latestWebSessionDebugReport())
                }
                return (
                    gradescopeManager.errorMessage ?? "Unknown session import error.",
                    gradescopeManager.latestWebSessionDebugReport()
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var topBar: some View {
        HStack {
            Text("Gradescope")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundColor(LectraColor.textPrimary)

            Spacer(minLength: 0)

            if gradescopeManager.isAuthenticated {
                Button {
                    LectraHaptics.selection()
                    Task {
                        await gradescopeManager.refreshCourses()
                        bootstrapAuthenticatedState()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .foregroundColor(LectraColor.textPrimary)
                }
                .buttonStyle(LectraSecondaryButtonStyle())
                .accessibilityIdentifier("gradescope.refresh")

                Button {
                    LectraHaptics.warning()
                    gradescopeManager.logout()
                    selectedCourseID = ""
                    localMessage = nil
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundColor(LectraColor.accentDestructive)
                }
                .buttonStyle(LectraSecondaryButtonStyle())
                .accessibilityIdentifier("gradescope.signOut")
            }
        }
    }

    private var authBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in with your Gradescope account to sync assignments and import templates.")
                .font(LectraTypography.body)
                .foregroundColor(LectraColor.textSecondary)

            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(10)
                .background(gradescopeInputBackground)

            SecureField("Password", text: $password)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(10)
                .background(gradescopeInputBackground)

            Button {
                LectraHaptics.tap()
                Task {
                    await gradescopeManager.login(email: email, password: password)
                    if gradescopeManager.isAuthenticated {
                        bootstrapAuthenticatedState()
                    }
                }
            } label: {
                HStack {
                    if gradescopeManager.isBusy {
                        ProgressView()
                            .tint(LectraColor.textPrimary)
                    }
                    Text("Sign In")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(LectraPrimaryButtonStyle(disabled: gradescopeManager.isBusy))
            .disabled(gradescopeManager.isBusy)

            Button {
                LectraHaptics.selection()
                showWebLoginSheet = true
            } label: {
                Text("Sign In via Gradescope Web")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(LectraSecondaryButtonStyle())
            .disabled(gradescopeManager.isBusy)

            Text("Use web sign-in for Google or school-credential Gradescope accounts.")
                .font(LectraTypography.captionMedium)
                .foregroundColor(LectraColor.textTertiary)

            if let error = gradescopeManager.errorMessage {
                Text(error)
                    .font(LectraTypography.caption)
                    .foregroundColor(LectraColor.accentSoft)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(gradescopePanelBackground)
        .padding(.horizontal, 18)
    }

    private var authenticatedBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !gradescopeManager.courses.isEmpty {
                Picker("Course", selection: $selectedCourseID) {
                    ForEach(gradescopeManager.courses) { course in
                        Text(course.shortName).tag(course.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(LectraColor.textPrimary)
                .padding(.horizontal, 12)
                .frame(minHeight: LectraSizing.minHitTarget)
                .background(gradescopeInputBackground)
            }

            if gradescopeManager.isBusy && assignments.isEmpty {
                ProgressView("Loading assignments…")
                    .tint(LectraColor.accentSoft)
                    .foregroundColor(LectraColor.textPrimary)
                    .padding(.top, 12)
            }

            if assignments.isEmpty, !gradescopeManager.isBusy {
                Text("No assignments available for this course.")
                    .font(LectraTypography.body)
                    .foregroundColor(LectraColor.textSecondary)
                    .padding(.top, 8)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(assignments) { assignment in
                        assignmentRow(assignment)
                    }
                }
            }

            if let localMessage {
                Text(localMessage)
                    .font(LectraTypography.caption)
                    .foregroundColor(
                        localMessage.contains("Imported")
                        ? LectraColor.accentSoft
                        : (localMessage.contains("No template") ? LectraColor.warningSubtle : LectraColor.accentSoft)
                    )
            }

            if let error = gradescopeManager.errorMessage {
                Text(error)
                    .font(LectraTypography.caption)
                    .foregroundColor(LectraColor.accentSoft)
            }

            if let assignmentTechnicalDetails {
                TechnicalDetailsDisclosure(
                    presentation: assignmentTechnicalDetails,
                    accessibilityID: "gradescope.assignmentDetails"
                )
            }

            if let diagnosticsTechnicalDetails {
                TechnicalDetailsDisclosure(
                    presentation: diagnosticsTechnicalDetails,
                    accessibilityID: "gradescope.diagnostics"
                )
            }
        }
        .padding(18)
        .background(gradescopePanelBackground)
        .padding(.horizontal, 18)
        .onChange(of: selectedCourseID) { _, newValue in
            guard !newValue.isEmpty else { return }
            if gradescopeManager.assignments(for: newValue).isEmpty {
                Task { await gradescopeManager.refreshAssignments(for: newValue) }
            }
        }
    }

    private func assignmentRow(_ assignment: GSAssignment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(assignment.name)
                .font(.headline)
                .foregroundColor(LectraColor.textPrimary)
                .multilineTextAlignment(.leading)

            HStack {
                if let due = assignment.dueDate {
                        Text("Due \(due.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline)
                            .foregroundColor(LectraColor.textSecondary)
                }

                Spacer(minLength: 0)

                Button {
                    LectraHaptics.tap()
                    Task { await importTemplate(for: assignment) }
                } label: {
                    HStack(spacing: 6) {
                        if isImportingTemplate {
                            ProgressView()
                                .tint(LectraColor.textPrimary)
                                .scaleEffect(0.85)
                        }
                        Image(systemName: "square.and.arrow.down")
                        Text("Import Template")
                    }
                    .frame(minHeight: LectraSizing.minHitTarget)
                }
                .buttonStyle(LectraPrimaryButtonStyle(disabled: isImportingTemplate))
                .disabled(isImportingTemplate)
            }
        }
        .padding(12)
        .background(gradescopeRowBackground)
    }

    private func bootstrapAuthenticatedState() {
        if selectedCourseID.isEmpty {
            selectedCourseID = gradescopeManager.courses.first?.id ?? ""
        }

        guard !selectedCourseID.isEmpty else { return }

        if gradescopeManager.assignments(for: selectedCourseID).isEmpty {
            Task { await gradescopeManager.refreshAssignments(for: selectedCourseID) }
        }
    }

    private func importTemplate(for assignment: GSAssignment) async {
        localMessage = nil
        isImportingTemplate = true
        defer { isImportingTemplate = false }

        do {
            let result = try await gradescopeManager.prepareTemplateImport(for: assignment)
            onImportTemplate(result.fileURL, result.suggestedFileName, assignment)
            localMessage = "Imported template for \(assignment.name)."
        } catch {
            if case GSError.noTemplateAvailable = error {
                localMessage = "No template published for \(assignment.name). You can still submit your own PDF from the editor."
            } else {
                localMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private var gradescopeInputBackground: some View {
        RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
            .fill(LectraColor.surfaceFloating.opacity(0.88))
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
    }

    private var gradescopePanelBackground: some View {
        RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
            .fill(LectraColor.surfaceElevated.opacity(0.74))
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
    }

    private var gradescopeRowBackground: some View {
        RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
            .fill(LectraColor.surfaceFloating.opacity(0.7))
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
    }
}
