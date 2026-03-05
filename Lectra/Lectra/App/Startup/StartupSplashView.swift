//
//  StartupSplashView.swift
//  Lectra
//
//  Ink Pulse startup surface shown after LaunchScreen and before root content.
//

import SwiftUI

struct StartupSplashView: View {
    let stage: StartupCoordinator.Stage
    let isWaitingForData: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseActive = false

    private var showMark: Bool {
        stage != .intro
    }

    private var showWordmark: Bool {
        switch stage {
        case .wordmark, .waiting:
            return true
        default:
            return false
        }
    }

    private var showSpinner: Bool {
        stage == .waiting && isWaitingForData
    }

    var body: some View {
        ZStack {
            Color(hex: 0x070C17)
                .ignoresSafeArea()

            LectraGradient.appBackdrop
                .opacity(0.9)
                .ignoresSafeArea()

            ambientGlow

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    LectraColor.accentCool.opacity(0.65),
                                    LectraColor.accent.opacity(0.36)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 122, height: 122)
                        .scaleEffect(reduceMotion ? 1.0 : (pulseActive ? 1.26 : 0.86))
                        .opacity(reduceMotion ? 0.12 : (pulseActive ? 0.0 : 0.62))

                    Image("LaunchMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
                        .scaleEffect(showMark ? 1.0 : (reduceMotion ? 1.0 : 0.84))
                        .opacity(showMark ? 1.0 : 0.0)
                }

                Text("Lectra")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(LectraColor.textPrimary)
                    .opacity(showWordmark ? 1.0 : 0.0)
                    .offset(y: reduceMotion ? 0 : (showWordmark ? 0 : 10))

                if showSpinner {
                    ProgressView()
                        .tint(LectraColor.accent)
                        .scaleEffect(0.95)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 24)
        }
        .allowsHitTesting(false)
        .animation(LectraMotion.startupIntro, value: showMark)
        .animation(LectraMotion.startupIntro, value: showWordmark)
        .animation(LectraMotion.quick, value: showSpinner)
        .onAppear {
            triggerPulseIfNeeded(for: stage)
        }
        .onChange(of: stage) { _, newStage in
            triggerPulseIfNeeded(for: newStage)
        }
    }

    private var ambientGlow: some View {
        ZStack {
            Circle()
                .fill(LectraColor.accent.opacity(0.14))
                .frame(width: 420, height: 420)
                .blur(radius: 70)
                .offset(x: -220, y: -260)

            Circle()
                .fill(LectraColor.accentCool.opacity(0.12))
                .frame(width: 360, height: 360)
                .blur(radius: 64)
                .offset(x: 240, y: 250)
        }
        .opacity(stage == .intro ? 0.5 : 1.0)
        .animation(LectraMotion.startupIntro, value: stage)
    }

    private func triggerPulseIfNeeded(for stage: StartupCoordinator.Stage) {
        guard stage == .pulse else { return }

        if reduceMotion {
            pulseActive = true
            return
        }

        pulseActive = false
        Task {
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(LectraMotion.startupPulse) {
                pulseActive = true
            }
        }
    }
}
