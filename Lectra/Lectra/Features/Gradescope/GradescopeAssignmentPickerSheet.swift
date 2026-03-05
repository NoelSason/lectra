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
            VStack(alignment: .leading, spacing: 14) {
                if gradescopeManager.courses.isEmpty {
                    Text("No courses available yet.")
                        .foregroundColor(.white.opacity(0.75))
                    Spacer()
                } else {
                    Picker("Course", selection: $selectedCourseID) {
                        ForEach(gradescopeManager.courses) { course in
                            Text(course.shortName).tag(course.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)

                    if gradescopeManager.isBusy && assignments.isEmpty {
                        ProgressView("Loading assignments…")
                            .tint(.white)
                            .foregroundColor(.white)
                    }

                    List(assignments) { assignment in
                        Button {
                            guard let course = selectedCourse else { return }
                            onPick(course, assignment)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(assignment.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.leading)

                                if let due = assignment.dueDate {
                                    Text("Due \(due.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(.white.opacity(0.72))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color(hex: 0x171A22))
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }

                if let error = gradescopeManager.errorMessage {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: 0xE84D4D))
                }
            }
            .padding(16)
            .background(Color(hex: 0x0E1016).ignoresSafeArea())
            .navigationTitle("Pick Assignment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.white)
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
            if gradescopeManager.assignments(for: newValue).isEmpty {
                Task { await gradescopeManager.refreshAssignments(for: newValue) }
            }
        }
    }
}
