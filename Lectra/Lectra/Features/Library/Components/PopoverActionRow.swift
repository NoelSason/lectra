import SwiftUI

struct PopoverActionRow: View {
    let title: String
    let icon: String
    var showDivider: Bool = true
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            if isDestructive {
                LectraHaptics.warning()
            } else {
                LectraHaptics.selection()
            }
            action()
        } label: {
            HStack(spacing: LectraSpacing.sm) {
                Image(systemName: icon)
                    .font(LectraTypography.body)
                    .frame(width: 24)
                Text(title)
                    .font(LectraTypography.body)
                Spacer(minLength: 0)
            }
            .foregroundColor(isDestructive ? LectraColor.accentDestructive : .white)
            .padding(.horizontal, 12)
            .frame(height: LectraSizing.minHitTarget)
        }
        .buttonStyle(.plain)

        if showDivider {
            Divider()
                .background(Color.white.opacity(LectraOpacity.muted))
                .padding(.leading, 12)
        }
    }
}
