import SwiftUI

struct GradescopePageAssignmentSheet: View {
    private struct AssignmentRow: Identifiable {
        let id = UUID()
        let questionId: String
        let questionTitle: String
        var pagesText: String
    }

    @Environment(\.dismiss) private var dismiss

    @State private var rows: [AssignmentRow]

    let pageCount: Int?
    let onSave: ([GSPageAssignmentDraft]) -> Void

    init(
        questions: [GSPageQuestion],
        existingAssignments: [GSPageAssignmentDraft],
        pageCount: Int?,
        onSave: @escaping ([GSPageAssignmentDraft]) -> Void
    ) {
        var byQuestion: [String: GSPageAssignmentDraft] = [:]
        for assignment in existingAssignments {
            byQuestion[assignment.questionId] = assignment
        }

        var initialRows: [AssignmentRow] = []
        if questions.isEmpty {
            if existingAssignments.isEmpty {
                initialRows = [AssignmentRow(questionId: "q1", questionTitle: "Question q1", pagesText: "1")]
            } else {
                initialRows = existingAssignments.map {
                    AssignmentRow(
                        questionId: $0.questionId,
                        questionTitle: "Question \($0.questionId)",
                        pagesText: $0.pageIndexes.map(String.init).joined(separator: ",")
                    )
                }
            }
        } else {
            initialRows = questions.map { question in
                let existing = byQuestion[question.id]
                return AssignmentRow(
                    questionId: question.id,
                    questionTitle: question.title,
                    pagesText: existing?.pageIndexes.map(String.init).joined(separator: ",") ?? ""
                )
            }
        }

        _rows = State(initialValue: initialRows)
        self.pageCount = pageCount
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: LectraSpacing.md) {
                Text("Map PDF pages to questions. Use comma-separated page numbers with 1-based indexing, like 1,2,3.")
                    .font(LectraTypography.body)
                    .foregroundColor(LectraColor.textSecondary)

                if let pageCount {
                    LectraStatusBadge(
                        title: "Detected pages: \(pageCount)",
                        color: LectraColor.accentSoft,
                        size: .large
                    )
                }

                ScrollView {
                    VStack(spacing: LectraSpacing.sm) {
                        ForEach($rows) { $row in
                            VStack(alignment: .leading, spacing: LectraSpacing.sm) {
                                Text(row.questionTitle)
                                    .font(LectraTypography.caption)
                                    .foregroundColor(LectraColor.textPrimary)

                                TextField("Pages", text: $row.pagesText)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                                    .font(LectraTypography.body)
                                    .foregroundColor(LectraColor.textPrimary)
                                    .padding(.horizontal, LectraSpacing.md)
                                    .frame(minHeight: LectraSizing.minHitTarget)
                                    .background(LectraColor.surfaceFloating.opacity(0.88))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                                            .stroke(LectraColor.edgeStroke, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous))
                            }
                            .padding(LectraSpacing.md)
                            .background(pageCardBackground)
                        }
                    }
                }

                Button("Assign Sequentially") {
                    LectraHaptics.selection()
                    applySequentialAssignments()
                }
                .buttonStyle(LectraSecondaryButtonStyle())

                Button("Save Page Mapping") {
                    let mapped = rows.compactMap { row -> GSPageAssignmentDraft? in
                        let pages = parsePages(row.pagesText)
                        guard !pages.isEmpty else { return nil }
                        return GSPageAssignmentDraft(questionId: row.questionId, pageIndexes: pages)
                    }
                    LectraHaptics.success()
                    onSave(mapped)
                    dismiss()
                }
                .buttonStyle(LectraPrimaryButtonStyle())
            }
            .padding(LectraSpacing.lg)
            .background(
                ZStack {
                    LectraColor.background.ignoresSafeArea()
                    LectraGradient.appBackdrop.opacity(0.68).ignoresSafeArea()
                }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(LectraColor.accentSoft)
                }
            }
        }
    }

    private func parsePages(_ raw: String) -> [Int] {
        raw
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 > 0 }
    }

    private func applySequentialAssignments() {
        guard !rows.isEmpty else { return }
        for index in rows.indices {
            rows[index].pagesText = "\(index + 1)"
        }
    }

    private var pageCardBackground: some View {
        RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous)
            .fill(LectraColor.surfaceElevated.opacity(0.74))
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
    }
}
