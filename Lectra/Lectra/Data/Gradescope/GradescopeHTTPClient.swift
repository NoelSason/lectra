import Foundation

struct GSHTTPResponse {
    let data: Data
    let response: HTTPURLResponse
    let url: URL
}

final class GradescopeHTTPClient {
    let baseURL: URL

    private let cookieStorage: HTTPCookieStorage
    private let session: URLSession

    var csrfToken: String?

    var sessionExpirationDate: Date? {
        let gradescopeCookies = cookies(domainContains: "gradescope.com")
        // Typically, the "_gradescope_session" handles actual auth.
        // It might be a session cookie (expires=nil) or explicit.
        if let authCookie = gradescopeCookies.first(where: { $0.name == "_gradescope_session" }) {
            return authCookie.expiresDate
        }
        return nil
    }

    init(
        baseURL: URL = URL(string: "https://www.gradescope.com")!,
        cookieStorage: HTTPCookieStorage = .shared
    ) {
        self.baseURL = baseURL
        self.cookieStorage = cookieStorage
        self.cookieStorage.cookieAcceptPolicy = .always

        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = cookieStorage
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60

        self.session = URLSession(configuration: configuration)
    }

    var hasSessionCookies: Bool {
        !(cookies(domainContains: "gradescope.com")).isEmpty
    }

    func clearSession() {
        for cookie in cookieStorage.cookies ?? [] where cookie.domain.lowercased().contains("gradescope.com") {
            cookieStorage.deleteCookie(cookie)
        }
        csrfToken = nil
    }

    func importCookies(_ cookies: [HTTPCookie]) {
        for cookie in cookies where cookie.domain.lowercased().contains("gradescope.com") {
            cookieStorage.setCookie(cookie)
        }
    }

    func hasCookie(named name: String, domainContains: String? = nil) -> Bool {
        let domainFilter = domainContains?.lowercased()
        return (cookieStorage.cookies ?? []).contains { cookie in
            guard cookie.name == name else { return false }
            guard let domainFilter else { return true }
            return cookie.domain.lowercased().contains(domainFilter)
        }
    }

    func cookies(domainContains: String? = nil) -> [HTTPCookie] {
        guard let domainContains else {
            return cookieStorage.cookies ?? []
        }
        let filter = domainContains.lowercased()
        return (cookieStorage.cookies ?? []).filter { $0.domain.lowercased().contains(filter) }
    }

    func makeSnapshot() throws -> GSSessionSnapshot {
        let cookies = self.cookies(domainContains: "gradescope.com")
        let archive = try NSKeyedArchiver.archivedData(withRootObject: cookies, requiringSecureCoding: true)
        return GSSessionSnapshot(
            cookieArchive: archive,
            csrfToken: csrfToken ?? "",
            savedAt: Date()
        )
    }

    func restore(from snapshot: GSSessionSnapshot) {
        clearSession()

        if let cookies = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, HTTPCookie.self], from: snapshot.cookieArchive) as? [HTTPCookie] {
            for cookie in cookies {
                cookieStorage.setCookie(cookie)
            }
        }

        csrfToken = snapshot.csrfToken.isEmpty ? nil : snapshot.csrfToken
    }

    func get(path: String, referer: URL? = nil) async throws -> GSHTTPResponse {
        let url = makeURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        setDefaultHeaders(on: &request, referer: referer)
        return try await perform(request)
    }

    func get(url: URL, referer: URL? = nil) async throws -> GSHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        setDefaultHeaders(on: &request, referer: referer)
        return try await perform(request)
    }

    func postForm(path: String, fields: [String: String], referer: URL? = nil, headers: [String: String] = [:]) async throws -> GSHTTPResponse {
        let url = makeURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        setDefaultHeaders(on: &request, referer: referer)
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = encodeForm(fields)
        return try await perform(request)
    }

    func postMultipart(
        path: String,
        fields: [String: String],
        fileFieldName: String,
        fileURL: URL,
        mimeType: String,
        referer: URL? = nil,
        headers: [String: String] = [:]
    ) async throws -> GSHTTPResponse {
        let fileData = try Data(contentsOf: fileURL)
        let url = makeURL(path: path)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        setDefaultHeaders(on: &request, referer: referer)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        request.httpBody = makeMultipartBody(
            fields: fields,
            fileFieldName: fileFieldName,
            fileName: fileURL.lastPathComponent,
            fileMimeType: mimeType,
            fileData: fileData,
            boundary: boundary
        )

        return try await perform(request)
    }

    func postJSON(path: String, jsonObject: Any, referer: URL? = nil, headers: [String: String] = [:]) async throws -> GSHTTPResponse {
        let url = makeURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        setDefaultHeaders(on: &request, referer: referer)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
        return try await perform(request)
    }

    func put(url: URL, data: Data, headers: [String: String] = [:], referer: URL? = nil) async throws -> GSHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        setDefaultHeaders(on: &request, referer: referer)
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = data
        return try await perform(request)
    }

    // MARK: - Private

    private func makeURL(path: String) -> URL {
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }

        if path.hasPrefix("/") {
            return baseURL.appendingPathComponent(String(path.dropFirst()))
        }

        return baseURL.appendingPathComponent(path)
    }

    private func setDefaultHeaders(on request: inout URLRequest, referer: URL?) {
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
        if let csrfToken, !csrfToken.isEmpty {
            request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
        }
    }

    private func perform(_ request: URLRequest) async throws -> GSHTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  let finalURL = http.url else {
                throw GSError.network("Unexpected response")
            }
            return GSHTTPResponse(data: data, response: http, url: finalURL)
        } catch {
            throw GSError.network(error.localizedDescription)
        }
    }

    private func encodeForm(_ fields: [String: String]) -> Data {
        let body = fields
            .map { key, value in
                "\(percentEncode(key))=\(percentEncode(value))"
            }
            .joined(separator: "&")

        return Data(body.utf8)
    }

    private func percentEncode(_ raw: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }

    private func makeMultipartBody(
        fields: [String: String],
        fileFieldName: String,
        fileName: String,
        fileMimeType: String,
        fileData: Data,
        boundary: String
    ) -> Data {
        var data = Data()

        for (name, value) in fields {
            data.appendString("--\(boundary)\r\n")
            data.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            data.appendString("\(value)\r\n")
        }

        data.appendString("--\(boundary)\r\n")
        data.appendString("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\r\n")
        data.appendString("Content-Type: \(fileMimeType)\r\n\r\n")
        data.append(fileData)
        data.appendString("\r\n")
        data.appendString("--\(boundary)--\r\n")

        return data
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        guard let chunk = string.data(using: .utf8) else { return }
        append(chunk)
    }
}
