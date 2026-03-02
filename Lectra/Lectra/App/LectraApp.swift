//
//  LectraApp.swift
//  Lectra
//
//  The main entry point. Injects the AuthManager environment object.
//

import SwiftUI

@main
@MainActor
struct LectraApp: App {
    @StateObject private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
        }
    }
}
