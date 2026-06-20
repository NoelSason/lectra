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
        guard !LectraLaunchConfiguration.current.isUITesting else { return true }

        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        guard !LectraLaunchConfiguration.current.isUITesting else { return }

        Task {
            await LectraWakeService.shared.updatePushToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard !LectraLaunchConfiguration.current.isUITesting else {
            completionHandler(.noData)
            return
        }

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
    @StateObject private var authManager: AuthManager
    @UIApplicationDelegateAdaptor(LectraAppDelegate.self) private var appDelegate
    private let launchConfiguration: LectraLaunchConfiguration

    init() {
        let launchConfiguration = LectraLaunchConfiguration.current
        self.launchConfiguration = launchConfiguration
        _authManager = StateObject(
            wrappedValue: AuthManager(mockState: launchConfiguration.authMockState)
        )
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(authManager)
                .task {
                    guard !launchConfiguration.isUITesting else { return }
                    await LectraWakeService.shared.scenePhaseDidChange(scenePhase)
                    await LectraWakeService.shared.authStateDidChange()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard !launchConfiguration.isUITesting else { return }
                    Task {
                        await LectraWakeService.shared.scenePhaseDidChange(newPhase)
                    }
                }
                .onChange(of: authManager.isAuthenticated) { _, _ in
                    guard !launchConfiguration.isUITesting else { return }
                    Task {
                        await LectraWakeService.shared.authStateDidChange()
                    }
                }
                .onChange(of: authManager.userId) { _, _ in
                    guard !launchConfiguration.isUITesting else { return }
                    Task {
                        await LectraWakeService.shared.authStateDidChange()
                    }
                }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        if let scenario = launchConfiguration.uiTestScenario {
            LectraUITestRootView(scenario: scenario)
        } else {
            ContentView()
        }
    }
}
