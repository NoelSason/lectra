//
//  ProfileAvatarView.swift
//  Lectra
//
//  Reusable profile avatar with async image loading and initial fallback.
//

import SwiftUI

struct ProfileAvatarView: View {
    let avatarURL: String?
    let fallbackName: String?
    var size: CGFloat = 36

    var body: some View {
        Group {
            if let avatarURL,
               let url = URL(string: avatarURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        fallbackAvatar
                    @unknown default:
                        fallbackAvatar
                    }
                }
            } else {
                fallbackAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallbackAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [LectraColor.accentSoft, LectraColor.accentDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(fallbackInitial)
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundColor(LectraColor.textPrimary)
        }
        .overlay(
            Circle()
                .stroke(LectraColor.edgeStroke, lineWidth: 1)
        )
        .lectraShadow(LectraElevation.low())
    }

    private var fallbackInitial: String {
        if let initial = fallbackName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .first {
            return String(initial).uppercased()
        }
        return "N"
    }
}
