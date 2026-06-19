import SwiftUI

struct GradescopeAssignmentPickerSheet: View {
    @EnvironmentObject private var gradescopeManager: GradescopeManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCourseID: String = ""

    let onPick: (GSCourse, GSAssignment) -> Void

    private var selectedCourse: GSCourse? {
        gradescopeManager.courses.first(where: { $0.id == selectedCourseID })
    }

    private var assignments: [GSAssignment] {
        guard let selectedCourse else { return [] }
        return gradescopeManager.assignments(for: selectedCourse.id)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: LectraSpacing.md) {
                header

                if gradescopeManager.courses.isEmpty {
                    emptyState
                } else {
                    coursePicker
                    assignmentsList
                }

                if let error = gradescopeManager.errorMessage {
                    Text(error)
                        .font(LectraTypography.caption)
                        .foregroundColor(LectraColor.accentDestructive)
                }
            }
            .padding(LectraSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                ZStack {
                    LectraColor.background.ignoresSafeArea()
                    LectraGradient.appBackdrop.opacity(0.7).ignoresSafeArea()
                }
            )
            .navigationTitle("Pick Assignment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(LectraColor.accentSoft)
                }
            }
        }
        .onAppear {
            if selectedCourseID.isEmpty {
                selectedCourseID = gradescopeManager.courses.first?.id ?? ""
            }

            if let course = selectedCourse,
               gradescopeManager.assignments(for: course.id).isEmpty {
                Task { await gradescopeManager.refreshAssignments(for: course.id) }
            }
        }
        .onChange(of: selectedCourseID) { _, newValue in
            guard !newValue.isEmpty else { return }
            LectraHaptics.selection()
            if gradescopeManager.assignments(for: newValue).isEmpty {
                Task { await gradescopeManager.refreshAssignments(for: newValue) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LectraSpacing.xs) {
            Text("Choose the course and assignment that match this PDF.")
                .font(LectraTypography.body)
                .foregroundColor(LectraColor.textSecondary)

            if gradescopeManager.isBusy && assignments.isEmpty {
                HStack(spacing: LectraSpacing.sm) {
                    ProgressView()
                        .tint(LectraColor.accentSoft)
                    Text("Loading assignments…")
                        .font(LectraTypography.caption)
                        .foregroundColor(LectraColor.textPrimary)
                }
            }
        }
    }

    private var coursePicker: some View {
        VStack(alignment: .leading, spacing: LectraSpacing.sm) {
            Text("Course")
                .font(LectraTypography.caption)
                .foregroundColor(LectraColor.textTertiary)

            Picker("Course", selection: $selectedCourseID) {
                ForEach(gradescopeManager.courses) { course in
                    Text(course.shortName).tag(course.id)
                }
            }
            .pickerStyle(.menu)
            .tint(LectraColor.textPrimary)
            .padding(.horizontal, LectraSpacing.md)
            .frame(minHeight: LectraSizing.minHitTarget)
            .background(LectraColor.surfaceFloating.opacity(0.88))
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous))
        }
    }

    private var assignmentsList: some View {
        List(assignments) { assignment in
            Button {
                guard let course = selectedCourse else { return }
                LectraHaptics.selection()
                onPick(course, assignment)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: LectraSpacing.xs) {
                    Text(assignment.name)
                        .font(LectraTypography.bodyEmphasis)
                        .foregroundColor(LectraColor.textPrimary)
                        .multilineTextAlignment(.leading)

                    if let due = assignment.dueDate {
                        Text("Due \(due.formatted(date: .abbreviated, time: .shortened))")
                            .font(LectraTypography.captionMedium)
                            .foregroundColor(LectraColor.textSecondary)
                    }
                }
                .padding(.vertical, LectraSpacing.xs)
            }
            .listRowBackground(LectraColor.surfaceFloating.opacity(0.82))
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                .stroke(LectraColor.edgeStroke, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: LectraSpacing.sm) {
            Image(systemName: "tray")
                .font(LectraTypography.title)
                .foregroundColor(LectraColor.accentCool)

            Text("No courses available yet.")
                .font(LectraTypography.headlineMedium)
                .foregroundColor(LectraColor.textPrimary)

            Text("Refresh your Gradescope session first, then come back to map this PDF to an assignment.")
                .font(LectraTypography.body)
                .foregroundColor(LectraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(LectraSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .lectraCard(cornerRadius: LectraRadius.panel)
    }
}
