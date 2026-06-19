import Foundation
import Supabase
import SwiftUI
import UIKit

actor LectraWakeService {
    static let shared = LectraWakeService()

    private static let clientKind = "lectra_ipad"
    private static let wakeEvent = "document_refresh"
    private static let registerEndpoint = SupabaseManager.shared.supabaseURL
        .appendingPathComponent("functions")
        .appendingPathComponent("v1")
        .appendingPathComponent("register-device-v2")
    private static let registrationRefreshInterval: TimeInterval = 5 * 60
    /// Max number of PDFs to fetch concurrently per wake. Downloads run in
    /// parallel so files land on-device before the user opens the library;
    /// the cap only bounds peak memory, it does not cap how many we fetch.
    private static let maxConcurrentPrefetches = 6
    private static let deviceIdDefaultsKey = "lectra_wake_device_id"
    private static let pushTokenDefaultsKey = "lectra_wake_push_token"

    private struct RegisterDevicePayload: Encodable {
        let deviceId: UUID
        let deviceName: String
        let clientKind: String
        let pushToken: String?
        let pushEnvironment: String?
    }

    private let client = SupabaseManager.shared.client
    private let repository = DocumentRepository()

    private let deviceId: UUID
    private var pushToken: String?
    private var currentScenePhase: ScenePhase = .background
    private var lastRegisteredAt: Date?
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeStatusTask: Task<Void, Never>?
    private var realtimeBroadcastTask: Task<Void, Never>?
    private var isRefreshInFlight = false
    private var shouldRefreshAgain = false

    init() {
        self.deviceId = Self.resolveDeviceId()
        self.pushToken = UserDefaults.standard.string(forKey: Self.pushTokenDefaultsKey)
    }

    /// Stable per-install device id, shared with the Canvascope export flow so
    /// delivery confirmations can be routed back to this device over realtime.
    nonisolated static func resolveDeviceId() -> UUID {
        if let stored = UserDefaults.standard.string(forKey: deviceIdDefaultsKey),
           let uuid = UUID(uuidString: stored) {
            return uuid
        }
        let created = UUID()
        UserDefaults.standard.set(created.uuidString, forKey: deviceIdDefaultsKey)
        return created
    }

    func applicationDidLaunch() async {
        guard await hasAuthenticatedSession() else { return }
        do {
            try await registerDeviceIfNeeded(reason: "launch", force: false)
        } catch {
            // Best effort. The next auth or wake event will retry.
        }
    }

    func authStateDidChange() async {
        guard await hasAuthenticatedSession() else {
            await stopRealtime()
            return
        }

        do {
            try await registerDeviceIfNeeded(reason: "auth-state", force: true)
        } catch {
            // Best effort. Wake handling remains opportunistic.
        }

        if currentScenePhase == .active {
            await ensureRealtimeSubscription()
            _ = await refreshRemoteDocuments(reason: "auth-state")
        }
    }

    func scenePhaseDidChange(_ newPhase: ScenePhase) async {
        currentScenePhase = newPhase

        guard newPhase == .active else {
            await stopRealtime()
            return
        }

        guard await hasAuthenticatedSession() else { return }

        do {
            try await registerDeviceIfNeeded(reason: "scene-active", force: false)
        } catch {
            // Best effort.
        }

        await ensureRealtimeSubscription()
        _ = await refreshRemoteDocuments(reason: "scene-active")
    }

    func updatePushToken(_ deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        pushToken = token
        UserDefaults.standard.set(token, forKey: Self.pushTokenDefaultsKey)

        guard await hasAuthenticatedSession() else { return }
        do {
            try await registerDeviceIfNeeded(reason: "push-token-refresh", force: true)
        } catch {
            // Best effort.
        }
    }

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard await hasAuthenticatedSession() else { return .noData }

        let backgroundTaskId = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(withName: "LectraWakeHint")
        }
        defer {
            Task { @MainActor in
                if backgroundTaskId != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskId)
                }
            }
        }

        do {
            try await registerDeviceIfNeeded(reason: notificationReason(from: userInfo), force: false)
            let didWork = await refreshRemoteDocuments(reason: notificationReason(from: userInfo))
            return didWork ? .newData : .noData
        } catch {
            return .failed
        }
    }

    private func ensureRealtimeSubscription() async {
        guard let userId = try? await resolveUserId() else { return }

        let desiredTopic = "dropbridge:user:\(userId.uuidString):device:\(deviceId.uuidString)"
        if realtimeChannel?.topic == desiredTopic {
            return
        }

        await stopRealtime()
        await client.realtimeV2.connect()

        let channel = client.channel(desiredTopic) { config in
            config.isPrivate = true
        }
        realtimeChannel = channel

        realtimeStatusTask = Task {
            for await status in channel.statusChange {
                guard !Task.isCancelled else { return }
                if status == .subscribed {
                    _ = await self.refreshRemoteDocuments(reason: "realtime-subscribed")
                }
            }
        }

        realtimeBroadcastTask = Task {
            for await _ in channel.broadcastStream(event: Self.wakeEvent) {
                guard !Task.isCancelled else { return }
                _ = await self.refreshRemoteDocuments(reason: "realtime-broadcast")
            }
        }

        do {
            try await channel.subscribeWithError()
        } catch {
            realtimeStatusTask?.cancel()
            realtimeStatusTask = nil
            realtimeBroadcastTask?.cancel()
            realtimeBroadcastTask = nil
            realtimeChannel = nil
            await client.removeChannel(channel)
        }
    }

    private func stopRealtime() async {
        realtimeStatusTask?.cancel()
        realtimeStatusTask = nil
        realtimeBroadcastTask?.cancel()
        realtimeBroadcastTask = nil

        if let channel = realtimeChannel {
            await client.removeChannel(channel)
        }
        realtimeChannel = nil
    }

    private func refreshRemoteDocuments(reason: String) async -> Bool {
        if isRefreshInFlight {
            shouldRefreshAgain = true
            return false
        }

        isRefreshInFlight = true
        defer {
            isRefreshInFlight = false
        }

        var didWork = false

        repeat {
            shouldRefreshAgain = false
            do {
                didWork = try await performRefresh(reason: reason) || didWork
            } catch {
                break
            }
        } while shouldRefreshAgain

        return didWork
    }

    private func performRefresh(reason: String) async throws -> Bool {
        _ = try await resolveSession()

        let items = try await repository.fetchDocuments()
        let candidates = items.filter { item in
            item.itemType == "pdf_document"
                && item.itemData.status == "pending_annotation"
                && !repository.isPDFCachedLocally(documentId: item.id)
        }

        // Download every pending document concurrently so the file is already
        // on-device by the time the user looks. A bounded task group keeps peak
        // memory in check while still saturating the connection.
        let prefetchedIds = await withTaskGroup(of: UUID?.self, returning: [UUID].self) { group in
            var collected: [UUID] = []
            var index = 0

            func addTask(for item: SyncedItem) {
                group.addTask { [repository] in
                    do {
                        _ = try await repository.downloadPDF(
                            storagePath: item.itemData.storagePath,
                            documentId: item.id
                        )
                        return item.id
                    } catch {
                        // Best effort prefetch. A later foreground refresh can still recover.
                        return nil
                    }
                }
            }

            while index < candidates.count && index < Self.maxConcurrentPrefetches {
                addTask(for: candidates[index])
                index += 1
            }

            while let result = await group.next() {
                if let id = result {
                    collected.append(id)
                }
                if index < candidates.count {
                    addTask(for: candidates[index])
                    index += 1
                }
            }

            return collected
        }

        let notifiedDocumentIds = prefetchedIds
        await MainActor.run {
            NotificationCenter.default.post(
                name: .lectraRemoteDocumentsDidChange,
                object: RemoteDocumentsChangePayload(documentIds: notifiedDocumentIds, reason: reason)
            )
        }

        return !candidates.isEmpty
    }

    private func registerDeviceIfNeeded(reason: String, force: Bool) async throws {
        if !force,
           let lastRegisteredAt,
           Date().timeIntervalSince(lastRegisteredAt) < Self.registrationRefreshInterval {
            return
        }

        let payload = RegisterDevicePayload(
            deviceId: deviceId,
            deviceName: await resolveDeviceName(),
            clientKind: Self.clientKind,
            pushToken: pushToken,
            pushEnvironment: pushToken == nil ? nil : currentPushEnvironment()
        )

        _ = try await performEdgeRequest(url: Self.registerEndpoint, payload: payload)
        lastRegisteredAt = Date()
    }

    private func performEdgeRequest<T: Encodable>(url: URL, payload: T) async throws -> Data {
        var accessToken = try await resolveAccessToken()
        var response = try await performRequest(url: url, payload: payload, accessToken: accessToken)

        if response.httpResponse.statusCode == 401 {
            accessToken = try await refreshAccessToken()
            response = try await performRequest(url: url, payload: payload, accessToken: accessToken)
        }

        if (200...299).contains(response.httpResponse.statusCode) {
            return response.data
        }

        let serverMessage = String(data: response.data, encoding: .utf8)
            ?? HTTPURLResponse.localizedString(forStatusCode: response.httpResponse.statusCode)
        throw NSError(
            domain: "LectraWakeService",
            code: response.httpResponse.statusCode,
            userInfo: [NSLocalizedDescriptionKey: serverMessage]
        )
    }

    private func performRequest<T: Encodable>(
        url: URL,
        payload: T,
        accessToken: String
    ) async throws -> (data: Data, httpResponse: HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseManager.shared.supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try Self.encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "LectraWakeService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected response from Canvascope wake endpoint."]
            )
        }
        return (data, httpResponse)
    }

    private func notificationReason(from userInfo: [AnyHashable: Any]) -> String {
        if let dropbridge = userInfo["dropbridge"] as? [String: Any],
           let reason = dropbridge["reason"] as? String,
           !reason.isEmpty {
            return "push-\(reason)"
        }

        if let event = userInfo["event"] as? String, !event.isEmpty {
            return "push-\(event)"
        }

        if let type = userInfo["type"] as? String, !type.isEmpty {
            return "push-\(type)"
        }

        return "silent-push"
    }

    private func hasAuthenticatedSession() async -> Bool {
        (try? await resolveUserId()) != nil
    }

    private func resolveUserId() async throws -> UUID {
        let session = try await resolveSession()
        return session.user.id
    }

    private func resolveAccessToken() async throws -> String {
        let session = try await resolveSession()
        return session.accessToken
    }

    private func refreshAccessToken() async throws -> String {
        try await client.auth.refreshSession().accessToken
    }

    private func resolveSession() async throws -> Session {
        if let current = client.auth.currentSession {
            if current.isExpired {
                return try await client.auth.refreshSession()
            }
            return current
        }
        return try await client.auth.session
    }

    private func resolveDeviceName() async -> String {
        await MainActor.run {
            let raw = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? "Canvascope iPad" : raw
        }
    }

    private func currentPushEnvironment() -> String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
