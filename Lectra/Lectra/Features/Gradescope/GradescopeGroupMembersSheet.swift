import SwiftUI

struct GradescopeGroupMembersSheet: View {
    private struct MemberRow: Identifiable {
        let id = UUID()
        var emailOrUserId: String
        var role: String
    }

    @Environment(\.dismiss) private var dismiss

    @State private var rows: [MemberRow]

    let onSave: ([GSGroupMemberDraft]) -> Void

    init(currentMembers: [GSGroupMemberDraft], onSave: @escaping ([GSGroupMemberDraft]) -> Void) {
        if currentMembers.isEmpty {
            _rows = State(initialValue: [MemberRow(emailOrUserId: "", role: "")])
        } else {
            _rows = State(initialValue: currentMembers.map {
                MemberRow(emailOrUserId: $0.emailOrUserId, role: $0.role ?? "")
            })
        }
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add group members for this submission. Leave role blank if not needed.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.72))

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach($rows) { $row in
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Email or user ID", text: $row.emailOrUserId)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                                    .padding(10)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                TextField("Role (optional)", text: $row.role)
                                    .padding(10)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                HStack {
                                    Spacer(minLength: 0)
                                    Button("Remove") {
                                        removeRow(id: row.id)
                                    }
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color(hex: 0xE84D4D))
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.04)))
                        }
                    }
                }

                Button("Add Member") {
                    rows.append(MemberRow(emailOrUserId: "", role: ""))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button("Save Members") {
                    let members = rows
                        .map { GSGroupMemberDraft(emailOrUserId: $0.emailOrUserId.trimmingCharacters(in: .whitespacesAndNewlines), role: normalizedRole($0.role)) }
                        .filter { !$0.emailOrUserId.isEmpty }
                    onSave(members)
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

    private func removeRow(id: UUID) {
        if rows.count == 1 {
            rows = [MemberRow(emailOrUserId: "", role: "")]
            return
        }
        rows.removeAll { $0.id == id }
    }

    private func normalizedRole(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
