//
//  ContentView.swift
//  Lectra
//
//  Root view – shows AuthView if not signed in, DocumentBrowserView if signed in.
//  Also shows a loading spinner while checking for an existing session.
//

import SwiftUI

struct ContentView: View {
    private enum RootScreen {
        case loading
        case library
        case auth
    }

    @EnvironmentObject var authManager: AuthManager

    private var rootScreen: RootScreen {
        if authManager.isLoading {
            return .loading
        }
        return authManager.isAuthenticated ? .library : .auth
    }

    var body: some View {
        ZStack {
            switch rootScreen {
            case .loading:
                loadingView
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .library:
                DocumentBrowserView()
                    .transition(.opacity)
            case .auth:
                AuthView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .preferredColorScheme(.dark)
        .animation(rootScreen == .loading ? LectraMotion.appLaunch : LectraMotion.screenSwap, value: rootScreen)
    }

    private var loadingView: some View {
        ZStack {
            LectraGradient.appBackdrop.ignoresSafeArea()

            VStack(spacing: LectraSpacing.md) {
                Image(systemName: "pencil.and.scribble")
                    .font(.system(size: 48))
                    .foregroundColor(LectraColor.accentCool)

                ProgressView()
                    .tint(LectraColor.accent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
