import SwiftUI

struct PopoverActionRow: View {
    let title: String
    let icon: String
    var showDivider: Bool = true
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 15, weight: .regular))
                Spacer(minLength: 0)
            }
            .foregroundColor(isDestructive ? Color(hex: 0xE84D4D) : .white)
            .padding(.horizontal, 12)
            .frame(height: 44)
        }
        .buttonStyle(.plain)

        if showDivider {
            Divider()
                .background(Color.white.opacity(0.12))
                .padding(.leading, 12)
        }
    }
}
