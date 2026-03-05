import Foundation

final class GradescopeTemplateService: GradescopeTemplateImporting {
    private let httpClient: GradescopeHTTPClient
    private let parser: GradescopeHTMLParser
    private(set) var lastDebugLines: [String] = []

    init(httpClient: GradescopeHTTPClient, parser: GradescopeHTMLParser) {
        self.httpClient = httpClient
        self.parser = parser
    }

    func fetchTemplate(for assignment: GSAssignment) async throws -> GSTemplateResult {
        let result = try await fetchTemplateWithDebug(for: assignment)
        return result.template
    }

    func fetchTemplateWithDebug(for assignment: GSAssignment) async throws -> (template: GSTemplateResult, debugLines: [String]) {
        var debugLines: [String] = []
        debugLines.append("template fetch start ts=\(ISO8601DateFormatter().string(from: Date()))")
        debugLines.append("template assignment course=\(assignment.courseId) id=\(assignment.id)")
        debugLines.append("template session \(sessionSummary())")
        defer { lastDebugLines = debugLines }

        let path = "/courses/\(assignment.courseId)/assignments/\(assignment.id)"
        let response = try await httpClient.get(path: path)
        debugLines.append("template GET \(path) -> \(response.response.statusCode) final=\(response.url.path)")

        guard response.response.statusCode == 200 else {
            if response.response.statusCode == 401 {
                debugLines.append("template unauthorized response")
                throw GSError.unauthorized
            }
            debugLines.append("template non-200 response")
            throw GSError.network("Could not open assignment page (\(response.response.statusCode)).")
        }

        let html = String(decoding: response.data, as: UTF8.self)
        debugLines.append("template html-signals \(templateHTMLSignals(in: html))")
        if let csrf = parser.parseCSRFToken(from: html) {
            httpClient.csrfToken = csrf
            debugLines.append("template csrf refreshed")
        } else {
            debugLines.append("template csrf missing from assignment page")
        }

        if parser.isLikelyLoginPage(html) || response.url.path.hasPrefix("/login") {
            debugLines.append("template page resolved to login")
            throw GSError.unauthorized
        }

        guard let url = parser.parseTemplatePDFLink(from: html, pageURL: response.url) else {
            debugLines.append("template result: no template link detected")
            return (.noTemplate, debugLines)
        }

        let suggested = sanitizeFileName("\(assignment.name) Template.pdf")
        debugLines.append("template result: found \(url.absoluteString)")
        return (.available(downloadURL: url, suggestedFileName: suggested), debugLines)
    }

    func downloadTemplate(url: URL, suggestedFileName: String) async throws -> URL {
        var debugLines = lastDebugLines
        debugLines.append("template download start url=\(url.absoluteString)")
        debugLines.append("template session \(sessionSummary())")
        defer { lastDebugLines = debugLines }

        let response = try await httpClient.get(url: url)
        debugLines.append("template download GET -> \(response.response.statusCode) final=\(response.url.path)")

        guard response.response.statusCode == 200 else {
            if response.response.statusCode == 401 {
                debugLines.append("template download unauthorized response")
                throw GSError.unauthorized
            }
            debugLines.append("template download non-200 response")
            throw GSError.network("Template download failed (\(response.response.statusCode)).")
        }

        guard !response.data.isEmpty else {
            debugLines.append("template download empty payload")
            throw GSError.emptyFile
        }

        let ext = (URL(string: suggestedFileName)?.pathExtension.isEmpty == false) ? "" : ".pdf"
        let name = sanitizeFileName(suggestedFileName) + ext
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GradescopeTemplates", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString)-\(name)")

        let folder = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try response.data.write(to: destination, options: [.atomic])

        debugLines.append("template download saved bytes=\(response.data.count) path=\(destination.path)")
        return destination
    }

    private func sanitizeFileName(_ raw: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let pieces = raw
            .components(separatedBy: forbidden)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return pieces.joined(separator: " ")
    }

    private func sessionSummary() -> String {
        let gradescopeCookies = httpClient.cookies(domainContains: "gradescope.com")
        let hasSession = httpClient.hasCookie(named: "_gradescope_session", domainContains: "gradescope.com")
        let csrfPresent = !(httpClient.csrfToken ?? "").isEmpty
        return "cookies=\(gradescopeCookies.count), has_session=\(hasSession), csrf_present=\(csrfPresent)"
    }

    private func templateHTMLSignals(in html: String) -> String {
        let normalized = html.lowercased()
        let pdfLinks = matchCount(in: html, pattern: "href=[\"'][^\"']+\\.pdf(?:\\?[^\"']*)?[\"']")
        let downloadText = normalized.contains("template") || normalized.contains("download") ? "yes" : "no"
        return "login=\(parser.isLikelyLoginPage(html)), auth=\(parser.isLikelyAuthenticatedAccountPage(html)), pdf-links=\(pdfLinks), has-template-language=\(downloadText)"
    }

    private func matchCount(in text: String, pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return 0
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }
}
