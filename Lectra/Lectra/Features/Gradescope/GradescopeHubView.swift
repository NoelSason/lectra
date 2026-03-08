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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
                .padding(.horizontal, 18)
                .padding(.top, 10)

            if gradescopeManager.isAuthenticated {
                authenticatedBody
            } else {
                authBody
            }
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
                .font(.largeTitle.weight(.bold))
                .foregroundColor(.white.opacity(0.96))

            Spacer(minLength: 0)

            if gradescopeManager.isAuthenticated {
                Button {
                    Task {
                        await gradescopeManager.refreshCourses()
                        bootstrapAuthenticatedState()
                    }
                } label: {
                    Text("Refresh")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color(hex: 0xE84D4D))
                        .padding(.horizontal, 14)
                        .frame(minHeight: LectraSizing.minHitTarget)
                        .background(Color(hex: 0xE84D4D).opacity(0.12))
                        .clipShape(Capsule())
                }

                Button {
                    gradescopeManager.logout()
                    selectedCourseID = ""
                    localMessage = nil
                } label: {
                    Text("Sign Out")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color(hex: 0xE84D4D))
                        .padding(.horizontal, 14)
                        .frame(minHeight: LectraSizing.minHitTarget)
                        .background(Color(hex: 0xE84D4D).opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var authBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in with your Gradescope account to sync assignments and import templates.")
                .font(.body)
                .foregroundColor(.white.opacity(0.74))

            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(10)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            SecureField("Password", text: $password)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .padding(10)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
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
                            .tint(.white)
                    }
                    Text("Sign In")
                        .font(.headline.weight(.semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: LectraSizing.minHitTarget)
                .background(Color(hex: 0x4A222A))
                .clipShape(Capsule())
            }
            .disabled(gradescopeManager.isBusy)

            Button {
                showWebLoginSheet = true
            } label: {
                Text("Sign In via Gradescope Web")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: LectraSizing.minHitTarget)
                    .background(Color.white.opacity(0.10))
                    .clipShape(Capsule())
            }
            .disabled(gradescopeManager.isBusy)

            Text("Use web sign-in for Google or school-credential Gradescope accounts.")
                .font(.callout)
                .foregroundColor(.white.opacity(0.62))

            if let error = gradescopeManager.errorMessage {
                Text(error)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Color(hex: 0xE84D4D))
            }

            Spacer(minLength: 0)
        }
        .padding(18)
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
                .tint(.white)
            }

            if gradescopeManager.isBusy && assignments.isEmpty {
                ProgressView("Loading assignments…")
                    .tint(.white)
                    .foregroundColor(.white)
                    .padding(.top, 12)
            }

            if assignments.isEmpty, !gradescopeManager.isBusy {
                Text("No assignments available for this course.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.72))
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
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(
                        localMessage.contains("Imported")
                        ? Color(hex: 0x35B77A)
                        : (localMessage.contains("No template") ? Color(hex: 0xF0BA5C) : Color(hex: 0xE84D4D))
                    )
            }

            if let error = gradescopeManager.errorMessage {
                Text(error)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Color(hex: 0xE84D4D))
            }

            if let assignmentDebugMessage {
                Text(assignmentDebugMessage)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.white.opacity(0.62))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            if let diagnosticsMessage, diagnosticsMessage != assignmentDebugMessage {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Diagnostics")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.white.opacity(0.9))
                        Spacer(minLength: 0)
                        Button("Copy") {
                            UIPasteboard.general.string = diagnosticsMessage
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color(hex: 0xE84D4D))
                        .padding(.horizontal, 12)
                        .frame(minHeight: LectraSizing.minHitTarget)
                        .background(Color(hex: 0xE84D4D).opacity(0.12))
                        .clipShape(Capsule())
                    }

                    Text(diagnosticsMessage)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.white.opacity(0.62))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(18)
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
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)

            HStack {
                if let due = assignment.dueDate {
                    Text("Due \(due.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.72))
                }

                Spacer(minLength: 0)

                Button {
                    Task { await importTemplate(for: assignment) }
                } label: {
                    HStack(spacing: 6) {
                        if isImportingTemplate {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.85)
                        }
                        Image(systemName: "square.and.arrow.down")
                        Text("Import Template")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: LectraSizing.minHitTarget)
                    .background(Color(hex: 0x4A222A))
                    .clipShape(Capsule())
                }
                .disabled(isImportingTemplate)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
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
}
