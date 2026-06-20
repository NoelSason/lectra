//
//  CanvascopeExportService.swift
//  Lectra
//
//  Uploads a local PDF to DropBridge v2 so the signed-in Lectra extension
//  can auto-download it without manual pairing.
//

import Foundation
import Supabase

struct CanvascopeUploadReceipt: Decodable {
    let ok: Bool
    let uploadId: String
    let fileName: String
    let sizeBytes: Int
    let contentType: String
    let receiverId: String
    let expiresAt: String
}

struct CanvascopeUploadStatusReceipt: Decodable {
    let ok: Bool
    let uploadId: String
    let status: String
    let createdAt: String?
    let downloadedAt: String?
    let expiresAt: String?
}

nonisolated private struct CanvascopeUploadStatusEnvelope: Decodable {
    struct Payload: Decodable {
        let uploadId: String?
        let status: String?
    }

    let payload: Payload?
    let uploadId: String?
    let status: String?
}

enum CanvascopeExportError: LocalizedError {
    case notAuthenticated
    case noActiveReceiver
    case fileTooLarge
    case network(String)
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in again to export to Lectra."
        case .noActiveReceiver:
            return "Open the Lectra extension on desktop to receive this file."
        case .fileTooLarge:
            return "This file is too large to export (25 MB max)."
        case .network(let message):
            return "Network error: \(message)"
        case .server(let message):
            return message
        case .invalidResponse:
            return "Unexpected response from Lectra export service."
        }
    }
}

final class CanvascopeExportService {
    private struct ErrorEnvelope: Decodable {
        let error: String
    }

    /// Realtime broadcast the backend sends back to this device when the
    /// receiver finishes downloading. Used for an instant "delivered" signal.
    private static let uploadStatusEvent = "upload_status"

    /// Stable id for this device, shared with `LectraWakeService` so the backend
    /// can route delivery confirmations to the channel we subscribe to.
    private let senderDeviceId = LectraWakeService.resolveDeviceId()

    private let maxFileBytes = 25 * 1024 * 1024
    private let uploadEndpoint = SupabaseManager.shared.supabaseURL
        .appendingPathComponent("functions")
        .appendingPathComponent("v1")
        .appendingPathComponent("upload-file-v2")
    private let statusEndpoint = SupabaseManager.shared.supabaseURL
        .appendingPathComponent("functions")
        .appendingPathComponent("v1")
        .appendingPathComponent("get-upload-status-v2")

    func uploadToCanvascope(fileURL: URL) async throws -> CanvascopeUploadReceipt {
        let fileData = try Data(contentsOf: fileURL)

        if fileData.isEmpty {
            throw CanvascopeExportError.server("File is empty and cannot be exported.")
        }

        if fileData.count > maxFileBytes {
            throw CanvascopeExportError.fileTooLarge
        }

        do {
            var accessToken = try await resolveAccessToken()
            var result = try await performUpload(fileURL: fileURL, fileData: fileData, accessToken: accessToken)
            var parsed = parseResponse(data: result.data, response: result.response)

            if case .authExpired = parsed {
                accessToken = try await refreshAccessToken()
                result = try await performUpload(fileURL: fileURL, fileData: fileData, accessToken: accessToken)
                parsed = parseResponse(data: result.data, response: result.response)
            }

            switch parsed {
            case .success(let receipt):
                return receipt
            case .authExpired:
                throw CanvascopeExportError.notAuthenticated
            case .noReceiver:
                throw CanvascopeExportError.noActiveReceiver
            case .fileTooLarge:
                throw CanvascopeExportError.fileTooLarge
            case .forbidden(let message):
                throw CanvascopeExportError.server(message)
            case .server(let message):
                throw CanvascopeExportError.server(message)
            case .invalidResponse:
                throw CanvascopeExportError.invalidResponse
            }
        } catch let exportError as CanvascopeExportError {
            throw exportError
        } catch {
            throw CanvascopeExportError.network(error.localizedDescription)
        }
    }

    /// Waits for the receiver to confirm download. Races an instant realtime
    /// "delivered" broadcast against polling so confirmation is near-instant when
    /// realtime is connected, and still resolves via polling if it isn't.
    func awaitTerminalStatus(
        uploadId: String,
        timeoutSeconds: TimeInterval = 120
    ) async throws -> CanvascopeUploadStatusReceipt? {
        let userId = try? await resolveUserId()

        return try await withThrowingTaskGroup(of: CanvascopeUploadStatusReceipt?.self) { group in
            if let userId {
                group.addTask {
                    await self.awaitRealtimeStatus(
                        uploadId: uploadId,
                        userId: userId,
                        timeoutSeconds: timeoutSeconds
                    )
                }
            }

            group.addTask {
                try await self.awaitPolledStatus(uploadId: uploadId, timeoutSeconds: timeoutSeconds)
            }

            // First branch to produce a terminal receipt wins; nil results (a
            // branch giving up) are ignored until every branch has finished.
            var resolved: CanvascopeUploadStatusReceipt? = nil
            for try await result in group {
                if let result {
                    resolved = result
                    break
                }
            }
            group.cancelAll()
            return resolved
        }
    }

    /// Subscribes to this device's private channel and resolves the moment the
    /// backend broadcasts a terminal `upload_status` for this upload.
    private func awaitRealtimeStatus(
        uploadId: String,
        userId: UUID,
        timeoutSeconds: TimeInterval
    ) async -> CanvascopeUploadStatusReceipt? {
        let client = SupabaseManager.shared.client
        let topic = "dropbridge:user:\(userId.uuidString):device:\(senderDeviceId.uuidString)"

        await client.realtimeV2.connect()
        let channel = client.channel(topic) { config in
            config.isPrivate = true
        }
        let stream = channel.broadcastStream(event: Self.uploadStatusEvent)

        do {
            try await channel.subscribeWithError()
        } catch {
            await client.removeChannel(channel)
            return nil
        }

        defer {
            Task { await client.removeChannel(channel) }
        }

        return await withTaskGroup(of: CanvascopeUploadStatusReceipt?.self) { group in
            group.addTask {
                for await message in stream {
                    guard let envelope = Self.decodeStatusEnvelope(message) else { continue }
                    guard (envelope.uploadId ?? envelope.payload?.uploadId) == uploadId else { continue }
                    let status = envelope.status ?? envelope.payload?.status
                    if status == "downloaded" || status == "canceled" {
                        return CanvascopeUploadStatusReceipt(
                            ok: true,
                            uploadId: uploadId,
                            status: status ?? "downloaded",
                            createdAt: nil,
                            downloadedAt: status == "downloaded" ? ISO8601DateFormatter().string(from: Date()) : nil,
                            expiresAt: nil
                        )
                    }
                }
                return nil
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(timeoutSeconds, 0) * 1_000_000_000))
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    nonisolated private static func decodeStatusEnvelope(_ message: [String: AnyJSON]) -> CanvascopeUploadStatusEnvelope? {
        guard let data = try? JSONEncoder().encode(message) else { return nil }
        return try? JSONDecoder().decode(CanvascopeUploadStatusEnvelope.self, from: data)
    }

    private func awaitPolledStatus(
        uploadId: String,
        timeoutSeconds: TimeInterval
    ) async throws -> CanvascopeUploadStatusReceipt? {
        let pollCadenceSeconds: [TimeInterval] = [0.4, 1.0, 1.8, 2.5]
        let deadline = Date().addingTimeInterval(max(timeoutSeconds, pollCadenceSeconds[0]))
        var accessToken = try await resolveAccessToken()
        var pollCount = 0

        while Date() < deadline {
            var result = try await performStatusCheck(uploadId: uploadId, accessToken: accessToken)
            var parsed = parseStatusResponse(data: result.data, response: result.response)

            if case .authExpired = parsed {
                accessToken = try await refreshAccessToken()
                result = try await performStatusCheck(uploadId: uploadId, accessToken: accessToken)
                parsed = parseStatusResponse(data: result.data, response: result.response)
            }

            switch parsed {
            case .success(let statusReceipt):
                if statusReceipt.status == "downloaded" || statusReceipt.status == "canceled" {
                    return statusReceipt
                }
            case .authExpired:
                throw CanvascopeExportError.notAuthenticated
            case .notFound:
                return nil
            case .forbidden(let message):
                throw CanvascopeExportError.server(message)
            case .server(let message):
                throw CanvascopeExportError.server(message)
            case .invalidResponse:
                throw CanvascopeExportError.invalidResponse
            }

            let delayIndex = min(pollCount, pollCadenceSeconds.count - 1)
            pollCount += 1
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                break
            }

            let waitSeconds = min(pollCadenceSeconds[delayIndex], remaining)
            let nanos = UInt64(max(waitSeconds, 0) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanos)
        }

        return nil
    }

    private enum ParsedUploadResponse {
        case success(CanvascopeUploadReceipt)
        case authExpired
        case noReceiver
        case fileTooLarge
        case forbidden(String)
        case server(String)
        case invalidResponse
    }

    private enum ParsedStatusResponse {
        case success(CanvascopeUploadStatusReceipt)
        case authExpired
        case notFound
        case forbidden(String)
        case server(String)
        case invalidResponse
    }

    private func performUpload(fileURL: URL, fileData: Data, accessToken: String) async throws
        -> (data: Data, response: HTTPURLResponse)
    {
        var request = URLRequest(url: uploadEndpoint)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseManager.shared.supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = makeMultipartBody(
            fields: [
                "receiverKind": "canvascope_extension",
                "senderKind": "lectra_ipad",
                "senderDeviceId": senderDeviceId.uuidString
            ],
            fieldName: "file",
            fileName: fileURL.lastPathComponent,
            mimeType: "application/pdf",
            fileData: fileData,
            boundary: boundary
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CanvascopeExportError.invalidResponse
        }
        return (data, httpResponse)
    }

    private func performStatusCheck(uploadId: String, accessToken: String) async throws
        -> (data: Data, response: HTTPURLResponse)
    {
        var request = URLRequest(url: statusEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseManager.shared.supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["uploadId": uploadId])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CanvascopeExportError.invalidResponse
        }

        return (data, httpResponse)
    }

    private func parseResponse(data: Data, response: HTTPURLResponse) -> ParsedUploadResponse {
        if (200...299).contains(response.statusCode) {
            guard let receipt = try? JSONDecoder().decode(CanvascopeUploadReceipt.self, from: data) else {
                return .invalidResponse
            }
            return .success(receipt)
        }

        let serverMessage = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error)
            ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)

        switch response.statusCode {
        case 401:
            return .authExpired
        case 403:
            return .forbidden(serverMessage)
        case 404:
            return .noReceiver
        case 413:
            return .fileTooLarge
        default:
            return .server(serverMessage)
        }
    }

    private func parseStatusResponse(data: Data, response: HTTPURLResponse) -> ParsedStatusResponse {
        if (200...299).contains(response.statusCode) {
            guard let receipt = try? JSONDecoder().decode(CanvascopeUploadStatusReceipt.self, from: data) else {
                return .invalidResponse
            }
            return .success(receipt)
        }

        let serverMessage = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error)
            ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)

        switch response.statusCode {
        case 401:
            return .authExpired
        case 403:
            return .forbidden(serverMessage)
        case 404:
            return .notFound
        default:
            return .server(serverMessage)
        }
    }

    private func resolveUserId() async throws -> UUID {
        let client = SupabaseManager.shared.client
        if let current = client.auth.currentSession, !current.isExpired {
            return current.user.id
        }
        let session = try await client.auth.session
        return session.user.id
    }

    private func resolveAccessToken() async throws -> String {
        if let current = SupabaseManager.shared.client.auth.currentSession {
            if current.isExpired {
                do {
                    let refreshed = try await SupabaseManager.shared.client.auth.refreshSession()
                    return refreshed.accessToken
                } catch {
                    throw CanvascopeExportError.notAuthenticated
                }
            }
            return current.accessToken
        }

        do {
            let session = try await SupabaseManager.shared.client.auth.session
            return session.accessToken
        } catch {
            throw CanvascopeExportError.notAuthenticated
        }
    }

    private func refreshAccessToken() async throws -> String {
        do {
            let refreshed = try await SupabaseManager.shared.client.auth.refreshSession()
            return refreshed.accessToken
        } catch {
            throw CanvascopeExportError.notAuthenticated
        }
    }

    private func makeMultipartBody(
        fields: [String: String],
        fieldName: String,
        fileName: String,
        mimeType: String,
        fileData: Data,
        boundary: String
    ) -> Data {
        var body = Data()
        let lineBreak = "\r\n"

        for (name, value) in fields {
            body.append("--\(boundary)\(lineBreak)")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\(lineBreak)\(lineBreak)")
            body.append("\(value)\(lineBreak)")
        }

        body.append("--\(boundary)\(lineBreak)")
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\(lineBreak)")
        body.append("Content-Type: \(mimeType)\(lineBreak)\(lineBreak)")
        body.append(fileData)
        body.append(lineBreak)
        body.append("--\(boundary)--\(lineBreak)")
        return body
    }
}

private extension Data {
    mutating func append(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        append(data)
    }
}
