//
//  ContentView.swift
//  Lectra
//
//  Root view – shows AuthView if not signed in, DocumentBrowserView if signed in.
//  Handles the cold-start startup splash handoff before revealing app content.
//

import SwiftUI

struct ContentView: View {
    private enum RootScreen {
        case library
        case auth
    }

    @EnvironmentObject var authManager: AuthManager
    @StateObject private var startupCoordinator = StartupCoordinator()

    private var rootScreen: RootScreen {
        authManager.isAuthenticated ? .library : .auth
    }

    var body: some View {
        ZStack {
            switch rootScreen {
            case .library:
                DocumentBrowserView()
                    .transition(.opacity)
            case .auth:
                AuthView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if !startupCoordinator.isCompleted {
                StartupSplashView(
                    stage: startupCoordinator.stage,
                    isWaitingForData: authManager.isLoading
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .preferredColorScheme(.dark)
        .animation(LectraMotion.screenSwap, value: rootScreen)
        .animation(LectraMotion.startupExit, value: startupCoordinator.isCompleted)
        .onAppear {
            startupCoordinator.start(dataReady: !authManager.isLoading)
        }
        .onChange(of: authManager.isLoading) { _, isLoading in
            startupCoordinator.updateDataReady(!isLoading)
        }
    }
}
