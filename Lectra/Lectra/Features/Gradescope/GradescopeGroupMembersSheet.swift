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
            VStack(alignment: .leading, spacing: LectraSpacing.md) {
                Text("Add group members for this submission. Leave role blank if it is not required by the assignment.")
                    .font(LectraTypography.body)
                    .foregroundColor(Color.white.opacity(LectraOpacity.prominent))

                ScrollView {
                    VStack(spacing: LectraSpacing.sm) {
                        ForEach($rows) { $row in
                            VStack(alignment: .leading, spacing: LectraSpacing.sm) {
                                memberField("Email or user ID", text: $row.emailOrUserId)
                                memberField("Role (optional)", text: $row.role)

                                HStack {
                                    Spacer(minLength: 0)
                                    Button("Remove") {
                                        LectraHaptics.selection()
                                        removeRow(id: row.id)
                                    }
                                    .font(LectraTypography.caption)
                                    .foregroundColor(LectraColor.accentDestructive)
                                }
                            }
                            .padding(LectraSpacing.md)
                            .lectraCard(cornerRadius: LectraRadius.card, shadow: false)
                        }
                    }
                }

                Button("Add Member") {
                    LectraHaptics.selection()
                    rows.append(MemberRow(emailOrUserId: "", role: ""))
                }
                .buttonStyle(LectraSecondaryButtonStyle())

                Button("Save Members") {
                    let members = rows
                        .map {
                            GSGroupMemberDraft(
                                emailOrUserId: $0.emailOrUserId.trimmingCharacters(in: .whitespacesAndNewlines),
                                role: normalizedRole($0.role)
                            )
                        }
                        .filter { !$0.emailOrUserId.isEmpty }
                    LectraHaptics.success()
                    onSave(members)
                    dismiss()
                }
                .buttonStyle(LectraPrimaryButtonStyle())
            }
            .padding(LectraSpacing.lg)
            .background(LectraColor.surfaceElevated.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(LectraColor.accentSoft)
                }
            }
        }
    }

    private func memberField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .font(LectraTypography.body)
            .foregroundColor(.white)
            .padding(.horizontal, LectraSpacing.md)
            .frame(minHeight: LectraSizing.minHitTarget)
            .background(Color.white.opacity(LectraOpacity.subtle))
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                    .stroke(Color.white.opacity(LectraOpacity.muted), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous))
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
