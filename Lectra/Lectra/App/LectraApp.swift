//
//  LectraApp.swift
//  Lectra
//
//  The main entry point. Injects the AuthManager environment object.
//

import SwiftUI
import UIKit

final class LectraAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        Task {
            await LectraWakeService.shared.applicationDidLaunch()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task {
            await LectraWakeService.shared.updatePushToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task {
            let result = await LectraWakeService.shared.handleRemoteNotification(userInfo: userInfo)
            completionHandler(result)
        }
    }
}

@main
@MainActor
struct LectraApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var authManager = AuthManager()
    @UIApplicationDelegateAdaptor(LectraAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .task {
                    await LectraWakeService.shared.scenePhaseDidChange(scenePhase)
                    await LectraWakeService.shared.authStateDidChange()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    Task {
                        await LectraWakeService.shared.scenePhaseDidChange(newPhase)
                    }
                }
                .onChange(of: authManager.isAuthenticated) { _, _ in
                    Task {
                        await LectraWakeService.shared.authStateDidChange()
                    }
                }
                .onChange(of: authManager.userId) { _, _ in
                    Task {
                        await LectraWakeService.shared.authStateDidChange()
                    }
                }
        }
    }
}
