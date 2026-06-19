//
//  AuthView.swift
//  Lectra
//
//  Full-screen sign-in entry for the Canvascope document workspace.
//

import SwiftUI

struct AuthView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            LectraGradient.appBackdrop
                .ignoresSafeArea()

            VStack(spacing: LectraSpacing.lg) {
                Spacer(minLength: LectraSpacing.xl)

                authPanel
                    .padding(.horizontal, LectraSpacing.lg)
                    .scaleEffect(reduceMotion ? 1.0 : (hasAppeared ? 1.0 : 0.97))
                    .offset(y: reduceMotion ? 0 : (hasAppeared ? 0 : 18))
                    .opacity(hasAppeared ? 1.0 : 0.0)

                Spacer(minLength: LectraSpacing.lg)
            }
        }
        .animation(reduceMotion ? nil : LectraMotion.quick, value: authManager.isLoading)
        .animation(reduceMotion ? nil : LectraMotion.quick, value: authManager.errorMessage)
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
        }
    }

    private var authPanel: some View {
        VStack(spacing: LectraSpacing.lg) {
            VStack(spacing: LectraSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                        .fill(LectraGradient.panel)
                        .overlay(
                            RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                                .stroke(LectraColor.edgeStroke, lineWidth: 1)
                        )
                        .frame(width: 86, height: 86)

                    Image("LaunchMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 58)
                        .accessibilityHidden(true)
                }

                VStack(spacing: 4) {
                    Text("Canvascope")
                        .font(LectraTypography.displayLarge)
                        .foregroundColor(LectraColor.textPrimary)
                        .multilineTextAlignment(.center)
                }

                Text("Canvascope's iPad workspace for PDFs, notes, and Apple Pencil markup.")
                    .font(LectraTypography.headlineMedium)
                    .foregroundColor(LectraColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: LectraSpacing.sm) {
                    AuthFeatureChip(title: "Local-first")
                    AuthFeatureChip(title: "Pencil-ready")
                    AuthFeatureChip(title: "Return flows")
                }

                VStack(spacing: LectraSpacing.sm) {
                    AuthFeatureChip(title: "Local-first")
                    AuthFeatureChip(title: "Pencil-ready")
                    AuthFeatureChip(title: "Return flows")
                }
            }

            if let error = authManager.errorMessage {
                Text(error)
                    .font(LectraTypography.caption)
                    .foregroundColor(LectraColor.accent)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LectraSpacing.md)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    .accessibilityLabel("Sign-in error. \(error)")
            }

            Button {
                LectraHaptics.tap()
                Task { @MainActor in await authManager.signInWithGoogle() }
            } label: {
                HStack(spacing: LectraSpacing.sm) {
                    if authManager.isLoading {
                        ProgressView()
                            .tint(LectraColor.textPrimary)
                    } else {
                        Image(systemName: "globe")
                            .font(LectraTypography.headline)
                    }

                    Text(authManager.isLoading ? "Connecting…" : "Continue with Google")
                        .font(LectraTypography.headline)
                }
                .foregroundColor(LectraColor.textPrimary)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(LectraPrimaryButtonStyle(disabled: authManager.isLoading))
            .disabled(authManager.isLoading)
            .accessibilityHint("Starts Google sign-in for your Canvascope account.")
            .accessibilityIdentifier("auth.signIn")

            Text("Sign in with your Canvascope account")
                .font(LectraTypography.captionMedium)
                .foregroundColor(LectraColor.textTertiary)
        }
        .padding(.horizontal, LectraSpacing.lg)
        .padding(.vertical, LectraSpacing.xl)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: LectraRadius.hero, style: .continuous)
                    .fill(LectraColor.surfaceElevated.opacity(0.88))

                RoundedRectangle(cornerRadius: LectraRadius.hero, style: .continuous)
                    .fill(LectraGradient.spotlight.opacity(0.42))

                RoundedRectangle(cornerRadius: LectraRadius.hero, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: LectraRadius.hero, style: .continuous))
        .lectraShadow(LectraElevation.high())
        .frame(maxWidth: 620)
        .accessibilityElement(children: .contain)
    }
}

private struct AuthFeatureChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(LectraTypography.caption)
            .foregroundColor(LectraColor.textSecondary)
            .padding(.horizontal, LectraSpacing.sm)
            .padding(.vertical, LectraSpacing.sm)
            .background(LectraColor.surfaceFloating.opacity(0.82))
            .overlay(
                Capsule()
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
            .clipShape(Capsule())
            .lineLimit(1)
    }
}
