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
            VStack(alignment: .leading, spacing: 12) {
                Text("Map PDF pages to questions. Use comma-separated page numbers (1-based), e.g. 1,2,3.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.72))

                if let pageCount {
                    Text("Detected pages: \(pageCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach($rows) { $row in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(row.questionTitle)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                TextField("Pages", text: $row.pagesText)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                                    .padding(10)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.04)))
                        }
                    }
                }

                Button("Assign Sequentially") {
                    applySequentialAssignments()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button("Save Page Mapping") {
                    let mapped = rows.compactMap { row -> GSPageAssignmentDraft? in
                        let pages = parsePages(row.pagesText)
                        guard !pages.isEmpty else { return nil }
                        return GSPageAssignmentDraft(questionId: row.questionId, pageIndexes: pages)
                    }
                    onSave(mapped)
                    dismiss()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Color(hex: 0x4A222A))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(14)
            .background(Color(hex: 0x111214).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(Color(hex: 0xE84D4D))
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
}
