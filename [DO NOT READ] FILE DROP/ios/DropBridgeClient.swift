import Foundation

struct DropBridgeConfig {
    let supabaseURL: URL
    let publishableKey: String
    let deviceID: String
    let deviceToken: String
}

struct UploadReceipt: Decodable {
    let ok: Bool
    let uploadId: String
    let fileName: String
    let sizeBytes: Int64
    let contentType: String?
}

struct APIError: Decodable, Error {
    let error: String
}

final class DropBridgeClient {
    private let config: DropBridgeConfig
    private let session: URLSession

    init(config: DropBridgeConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func uploadFile(fileURL: URL, mimeType: String? = nil) async throws -> UploadReceipt {
        let uploadURL = config.supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent("upload-file")

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.publishableKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let detectedMime = mimeType ?? inferMimeType(from: fileURL.pathExtension)

        var body = Data()
        body.appendMultipartField(name: "deviceId", value: config.deviceID, boundary: boundary)
        body.appendMultipartField(name: "deviceToken", value: config.deviceToken, boundary: boundary)
        body.appendMultipartFile(
            name: "file",
            filename: filename,
            mimeType: detectedMime,
            fileData: fileData,
            boundary: boundary
        )
        body.appendString("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response: response, data: data)

        do {
            return try JSONDecoder().decode(UploadReceipt.self, from: data)
        } catch {
            if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
                throw apiError
            }
            throw error
        }
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200..<300).contains(http.statusCode) else {
            if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
                throw apiError
            }
            throw URLError(.badServerResponse)
        }
    }

    private func inferMimeType(from ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "mov": return "video/quicktime"
        case "mp4": return "video/mp4"
        default: return "application/octet-stream"
        }
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendMultipartFile(name: String, filename: String, mimeType: String, fileData: Data, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(fileData)
        appendString("\r\n")
    }
}
