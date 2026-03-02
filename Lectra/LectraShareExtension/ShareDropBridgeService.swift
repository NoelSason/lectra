import Foundation
import Supabase
import UniformTypeIdentifiers

struct ShareUploadReceipt: Decodable {
    let ok: Bool
    let uploadId: String
    let fileName: String
    let sizeBytes: Int
    let contentType: String
    let receiverId: String
    let expiresAt: String
}

enum ShareDropBridgeError: LocalizedError {
    case notAuthenticated
    case fileTooLarge
    case fileEmpty
    case network(String)
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sign in to Lectra first, then try sharing again."
        case .fileTooLarge:
            return "This file is too large to send (25 MB max)."
        case .fileEmpty:
            return "This file appears to be empty."
        case .network(let message):
            return "Network error: \(message)"
        case .server(let message):
            return message
        case .invalidResponse:
            return "Unexpected response from Canvascope export service."
        }
    }
}

final class ShareDropBridgeService {
    private struct ErrorEnvelope: Decodable {
        let error: String
    }

    private let maxFileBytes = 25 * 1024 * 1024
    private let uploadEndpoint = ShareSupabaseManager.shared.supabaseURL
        .appendingPathComponent("functions")
        .appendingPathComponent("v1")
        .appendingPathComponent("upload-file-v2")

    func assertAuthenticated() async throws {
        _ = try await resolveAccessToken()
    }

    func uploadSharedFile(fileURL: URL) async throws -> ShareUploadReceipt {
        let fileData = try Data(contentsOf: fileURL)

        if fileData.isEmpty {
            throw ShareDropBridgeError.fileEmpty
        }

        if fileData.count > maxFileBytes {
            throw ShareDropBridgeError.fileTooLarge
        }

        let mimeType = Self.inferMIMEType(for: fileURL)

        do {
            var accessToken = try await resolveAccessToken()
            var result = try await performUpload(
                fileURL: fileURL,
                fileData: fileData,
                mimeType: mimeType,
                accessToken: accessToken
            )
            var parsed = parseResponse(data: result.data, response: result.response)

            if case .authExpired = parsed {
                accessToken = try await refreshAccessToken()
                result = try await performUpload(
                    fileURL: fileURL,
                    fileData: fileData,
                    mimeType: mimeType,
                    accessToken: accessToken
                )
                parsed = parseResponse(data: result.data, response: result.response)
            }

            switch parsed {
            case .success(let receipt):
                return receipt
            case .authExpired:
                throw ShareDropBridgeError.notAuthenticated
            case .fileTooLarge:
                throw ShareDropBridgeError.fileTooLarge
            case .server(let message):
                throw ShareDropBridgeError.server(message)
            case .invalidResponse:
                throw ShareDropBridgeError.invalidResponse
            }
        } catch let error as ShareDropBridgeError {
            throw error
        } catch {
            throw ShareDropBridgeError.network(error.localizedDescription)
        }
    }

    private enum ParsedUploadResponse {
        case success(ShareUploadReceipt)
        case authExpired
        case fileTooLarge
        case server(String)
        case invalidResponse
    }

    private func performUpload(
        fileURL: URL,
        fileData: Data,
        mimeType: String,
        accessToken: String
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        var request = URLRequest(url: uploadEndpoint)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(ShareSupabaseManager.shared.supabaseKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = makeMultipartBody(
            fields: [
                "receiverKind": "canvascope_extension",
                "senderKind": "lectra_ipad"
            ],
            fieldName: "file",
            fileName: fileURL.lastPathComponent,
            mimeType: mimeType,
            fileData: fileData,
            boundary: boundary
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShareDropBridgeError.invalidResponse
        }
        return (data, httpResponse)
    }

    private func parseResponse(data: Data, response: HTTPURLResponse) -> ParsedUploadResponse {
        if (200...299).contains(response.statusCode) {
            guard let receipt = try? JSONDecoder().decode(ShareUploadReceipt.self, from: data) else {
                return .invalidResponse
            }
            return .success(receipt)
        }

        let serverMessage = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error)
            ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)

        switch response.statusCode {
        case 401:
            return .authExpired
        case 413:
            return .fileTooLarge
        default:
            return .server(serverMessage)
        }
    }

    private func resolveAccessToken() async throws -> String {
        if let current = ShareSupabaseManager.shared.client.auth.currentSession {
            if current.isExpired {
                do {
                    let refreshed = try await ShareSupabaseManager.shared.client.auth.refreshSession()
                    return refreshed.accessToken
                } catch {
                    throw ShareDropBridgeError.notAuthenticated
                }
            }
            return current.accessToken
        }

        do {
            let session = try await ShareSupabaseManager.shared.client.auth.session
            return session.accessToken
        } catch {
            throw ShareDropBridgeError.notAuthenticated
        }
    }

    private func refreshAccessToken() async throws -> String {
        do {
            let refreshed = try await ShareSupabaseManager.shared.client.auth.refreshSession()
            return refreshed.accessToken
        } catch {
            throw ShareDropBridgeError.notAuthenticated
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

    private static func inferMIMEType(for fileURL: URL) -> String {
        let ext = fileURL.pathExtension
        if !ext.isEmpty,
           let type = UTType(filenameExtension: ext),
           let mime = type.preferredMIMEType {
            return mime
        }

        if let type = UTType(filenameExtension: fileURL.lastPathComponent),
           let mime = type.preferredMIMEType {
            return mime
        }

        return "application/octet-stream"
    }
}

private extension Data {
    mutating func append(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        append(data)
    }
}
