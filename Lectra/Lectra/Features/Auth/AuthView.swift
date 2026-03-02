//
//  AuthView.swift
//  Lectra
//
//  Full-screen sign-in entry with a distinctive drafting-studio style.
//

import SwiftUI

struct AuthView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        ZStack {
            LectraGradient.appBackdrop
                .ignoresSafeArea()

            ambientBlobs

            VStack(spacing: LectraSpacing.lg) {
                Spacer(minLength: 28)

                authPanel
                    .padding(.horizontal, LectraSpacing.lg)

                Spacer(minLength: 22)
            }
        }
        .animation(LectraMotion.quick, value: authManager.isLoading)
        .animation(LectraMotion.quick, value: authManager.errorMessage)
    }

    private var ambientBlobs: some View {
        ZStack {
            Circle()
                .fill(LectraColor.accent.opacity(0.15))
                .frame(width: 520, height: 520)
                .blur(radius: 60)
                .offset(x: -210, y: -260)

            Circle()
                .fill(LectraColor.accentCool.opacity(0.14))
                .frame(width: 460, height: 460)
                .blur(radius: 72)
                .offset(x: 230, y: 240)
        }
        .allowsHitTesting(false)
    }

    private var authPanel: some View {
        VStack(spacing: LectraSpacing.lg) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LectraGradient.panel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(LectraColor.edgeStroke, lineWidth: 1)
                        )
                        .frame(width: 86, height: 86)

                    Image(systemName: "pencil.and.scribble")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [LectraColor.accentCool, LectraColor.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                Text("Lectra Studio")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(LectraColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Precision annotation for lecture PDFs.\nBuilt for Apple Pencil, tuned for long sessions.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(LectraColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            HStack(spacing: LectraSpacing.sm) {
                AuthFeatureChip(title: "Pencil-first")
                AuthFeatureChip(title: "Fast Sync")
                AuthFeatureChip(title: "Offline Ready")
            }

            if let error = authManager.errorMessage {
                Text(error)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(LectraColor.accent)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LectraSpacing.md)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                Task { @MainActor in await authManager.signInWithGoogle() }
            } label: {
                HStack(spacing: 12) {
                    if authManager.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 16, weight: .bold))
                    }

                    Text(authManager.isLoading ? "Connecting…" : "Continue with Google")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [LectraColor.accent, Color(hex: 0xD83E3A)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: LectraColor.accent.opacity(0.35), radius: 14, x: 0, y: 8)
            }
            .disabled(authManager.isLoading)

            Text("Sign in with your Canvascope account")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(LectraColor.textTertiary)
        }
        .padding(.horizontal, LectraSpacing.lg)
        .padding(.vertical, LectraSpacing.xl)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color(hex: 0x0F1628, opacity: 0.88))

                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(LectraGradient.spotlight.opacity(0.55))

                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 16)
        .frame(maxWidth: 620)
    }
}

private struct AuthFeatureChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(LectraColor.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.07))
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .clipShape(Capsule())
            .lineLimit(1)
    }
}
