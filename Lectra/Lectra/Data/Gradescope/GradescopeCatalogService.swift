import Foundation

final class GradescopeCatalogService: GradescopeCatalogProviding {
    private let httpClient: GradescopeHTTPClient
    private let parser: GradescopeHTMLParser
    private(set) var lastDebugLines: [String] = []

    init(httpClient: GradescopeHTTPClient, parser: GradescopeHTMLParser) {
        self.httpClient = httpClient
        self.parser = parser
    }

    func parseCoursesFromHTML(_ html: String) -> [GSCourse] {
        let courses = parser.parseCourses(from: html)
        return courses.sorted {
            if $0.shortName == $1.shortName {
                return $0.id < $1.id
            }
            return $0.shortName.localizedCaseInsensitiveCompare($1.shortName) == .orderedAscending
        }
    }

    func fetchCourses() async throws -> [GSCourse] {
        let result = try await fetchCoursesWithDebug()
        return result.courses
    }

    func fetchCoursesWithDebug() async throws -> (courses: [GSCourse], debugLines: [String]) {
        let candidatePaths = ["/account", "/"]
        var sawUnauthorized = false
        var sawAnyAuthenticatedPage = false
        var debugLines: [String] = []
        debugLines.append("courses refresh start ts=\(ISO8601DateFormatter().string(from: Date()))")
        debugLines.append("courses session \(sessionSummary())")
        defer { lastDebugLines = debugLines }

        for path in candidatePaths {
            let response = try await httpClient.get(path: path)
            debugLines.append("courses GET \(path) -> \(response.response.statusCode) final=\(response.url.path)")

            if response.response.statusCode == 401 || response.response.statusCode == 403 {
                sawUnauthorized = true
                debugLines.append("courses \(path): unauthorized response")
                continue
            }

            guard response.response.statusCode == 200 else {
                debugLines.append("courses \(path): skipped non-200")
                continue
            }

            let html = String(decoding: response.data, as: UTF8.self)
            if let csrf = parser.parseCSRFToken(from: html) {
                httpClient.csrfToken = csrf
                debugLines.append("courses \(path): csrf refreshed")
            }

            if parser.isLikelyLoginPage(html) {
                sawUnauthorized = true
                debugLines.append("courses \(path): login page detected")
                continue
            }

            sawAnyAuthenticatedPage = true
            debugLines.append("courses \(path): html-signals \(courseHTMLSignals(in: html))")
            let courses = parseCoursesFromHTML(html)
            debugLines.append("courses \(path): parser courses=\(courses.count)")
            if !courses.isEmpty {
                debugLines.append("courses success: returning \(courses.count) courses from \(path)")
                return (courses, debugLines)
            }

            // If "/" is authenticated but parser didn't recognize cards, don't treat as unauthorized.
            if path == "/" {
                debugLines.append("courses \(path): authenticated page but no courses parsed")
                throw GSError.parsingFailed("Authenticated Gradescope page loaded, but course cards could not be parsed.")
            }
        }

        if !sawAnyAuthenticatedPage && sawUnauthorized {
            debugLines.append("courses failed: unauthorized across endpoints")
            throw GSError.unauthorized
        }

        debugLines.append("courses failed: no courses found")
        throw GSError.parsingFailed("No courses found")
    }

    func fetchAssignments(courseId: String) async throws -> [GSAssignment] {
        let result = try await fetchAssignmentsWithDebug(courseId: courseId)
        return result.assignments
    }

    func fetchAssignmentsWithDebug(courseId: String) async throws -> (assignments: [GSAssignment], debugLines: [String]) {
        guard !courseId.isEmpty else {
            throw GSError.parsingFailed("Missing course id")
        }

        let candidatePaths = ["/courses/\(courseId)/assignments", "/courses/\(courseId)"]
        var sawUnauthorized = false
        var sawAnyAuthenticatedPage = false
        var debugLines: [String] = []
        debugLines.append("assignments refresh start ts=\(ISO8601DateFormatter().string(from: Date()))")
        debugLines.append("assignments course=\(courseId)")
        debugLines.append("assignments session \(sessionSummary())")
        defer { lastDebugLines = debugLines }

        for path in candidatePaths {
            let response = try await httpClient.get(path: path)
            debugLines.append("catalog GET \(path) -> \(response.response.statusCode) final=\(response.url.path)")

            if response.response.statusCode == 401 || response.response.statusCode == 403 {
                sawUnauthorized = true
                debugLines.append("catalog \(path): unauthorized response")
                continue
            }

            guard response.response.statusCode == 200 else {
                debugLines.append("catalog \(path): skipped non-200")
                continue
            }

            let html = String(decoding: response.data, as: UTF8.self)
            if let csrf = parser.parseCSRFToken(from: html) {
                httpClient.csrfToken = csrf
                debugLines.append("catalog \(path): csrf refreshed")
            }

            if parser.isLikelyLoginPage(html) || response.url.path.hasPrefix("/login") {
                sawUnauthorized = true
                debugLines.append("catalog \(path): login page detected")
                continue
            }

            sawAnyAuthenticatedPage = true
            debugLines.append("catalog \(path): html-signals \(assignmentHTMLSignals(in: html))")
            debugLines.append("catalog \(path): sample-links \(sampleMatches(in: html, pattern: "/courses/[^\"'\\s<>]+/assignments/[^\"'\\s<>]+"))")
            debugLines.append("catalog \(path): sample-data-ids \(sampleMatches(in: html, pattern: "data-assignment-id=[\"'][^\"']+[\"']"))")

            let assignments = try parser.parseAssignments(from: html, courseId: courseId)
            debugLines.append("catalog \(path): parser assignments=\(assignments.count)")
            if !assignments.isEmpty {
                let sorted = sortAssignments(assignments)
                debugLines.append("catalog success: returning \(sorted.count) assignments from \(path)")
                return (sorted, debugLines)
            }
        }

        if !sawAnyAuthenticatedPage && sawUnauthorized {
            debugLines.append("catalog failed: unauthorized across assignment endpoints")
            throw GSError.unauthorized
        }

        debugLines.append("catalog complete: no assignments parsed")
        return ([], debugLines)
    }

    private func sortAssignments(_ assignments: [GSAssignment]) -> [GSAssignment] {
        assignments.sorted {
            switch ($0.dueDate, $1.dueDate) {
            case let (lhs?, rhs?):
                if lhs == rhs {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return lhs < rhs
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private func assignmentHTMLSignals(in html: String) -> String {
        let assignmentLinks = matchCount(in: html, pattern: "/courses/[^\"'\\s<>]+/assignments/[^\"'\\s<>]+")
        let looseAssignmentLinks = matchCount(in: html, pattern: "/assignments/[^\"'\\s<>]+")
        let dataAssignmentIDs = matchCount(in: html, pattern: "data-assignment-id=[\"'][^\"']+[\"']")
        let assignmentsTable = matchCount(in: html, pattern: "AssignmentsTable")
        let noAssignmentsText = html.lowercased().contains("no assignments") ? "yes" : "no"
        return "links=\(assignmentLinks), loose-links=\(looseAssignmentLinks), data-ids=\(dataAssignmentIDs), table-markers=\(assignmentsTable), no-assignments-text=\(noAssignmentsText)"
    }

    private func courseHTMLSignals(in html: String) -> String {
        let normalized = html.lowercased()
        let courseLinks = matchCount(in: html, pattern: "href=[\"']/courses/[0-9]+[\"']")
        let courseCards = matchCount(in: html, pattern: "coursebox--shortname")
        let logout = normalized.contains("href=\"/logout\"") || normalized.contains("/sign_out") ? "yes" : "no"
        return "login=\(parser.isLikelyLoginPage(html)), auth=\(parser.isLikelyAuthenticatedAccountPage(html)), course-links=\(courseLinks), course-cards=\(courseCards), logout=\(logout)"
    }

    private func sessionSummary() -> String {
        let gradescopeCookies = httpClient.cookies(domainContains: "gradescope.com")
        let hasSession = httpClient.hasCookie(named: "_gradescope_session", domainContains: "gradescope.com")
        let hasRememberMe = httpClient.hasCookie(named: "remember_me", domainContains: "gradescope.com")
        let csrfPresent = !(httpClient.csrfToken ?? "").isEmpty
        return "cookies=\(gradescopeCookies.count), has_session=\(hasSession), has_remember_me=\(hasRememberMe), csrf_present=\(csrfPresent)"
    }

    private func sampleMatches(in text: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return "regex-error"
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)
        if matches.isEmpty {
            return "none"
        }

        let snippets = matches.prefix(4).compactMap { match -> String? in
            guard match.range.location != NSNotFound else { return nil }
            let captured = nsText.substring(with: match.range)
            let compact = captured.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return compact.count > 140 ? String(compact.prefix(140)) + "…" : compact
        }

        let joined = snippets.joined(separator: " | ")
        if matches.count > snippets.count {
            return "\(joined) (+\(matches.count - snippets.count) more)"
        }
        return joined
    }

    private func matchCount(in text: String, pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return 0
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }
}
