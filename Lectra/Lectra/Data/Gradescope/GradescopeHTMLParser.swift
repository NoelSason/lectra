import Foundation
import UIKit

final class GradescopeHTMLParser {
    struct SubmissionFormSpec {
        let actionURL: URL
        let fileFieldName: String
        let method: String
        let isRemote: Bool
        let enctype: String?
        let fileInputAccept: String?
        let fileInputDirectUploadURL: URL?
        let hiddenFields: [String: String]
        let allFields: [String: String]
        let submitButtons: [GSSubmissionSubmitButton]
        let requiredFields: [GSRequiredField]
    }

    func parseLoginAuthenticityToken(from html: String) -> String? {
        // Primary selector from upstream project: form[action="/login"] input[name="authenticity_token"]
        if let loginFormInner = firstCapture(
            in: html,
            pattern: "<form[^>]*action=[\"']/login[\"'][^>]*>([\\s\\S]*?)</form>"
        ), let token = firstCapture(
            in: loginFormInner,
            pattern: "<input[^>]*name=[\"']authenticity_token[\"'][^>]*value=[\"']([^\"']+)[\"'][^>]*>"
        ) {
            return decodeHTMLEntities(token)
        }

        // Fallback if structure changes.
        if let fallback = firstCapture(
            in: html,
            pattern: "<input[^>]*name=[\"']authenticity_token[\"'][^>]*value=[\"']([^\"']+)[\"'][^>]*>"
        ) {
            return decodeHTMLEntities(fallback)
        }

        return nil
    }

    func parseCSRFToken(from html: String) -> String? {
        if let token = firstCapture(
            in: html,
            pattern: "<meta[^>]*name=[\"']csrf-token[\"'][^>]*content=[\"']([^\"']+)[\"'][^>]*>"
        ) {
            return decodeHTMLEntities(token)
        }
        return nil
    }

    func parseFlashErrorMessage(from html: String) -> String? {
        if let inlineMessage = firstCapture(
            in: html,
            pattern: "<div[^>]*class=[\"'][^\"']*alert[^\"']*alert-error[^\"']*[\"'][^>]*>[\\s\\S]*?<span[^>]*>([\\s\\S]*?)</span>"
        ) {
            let cleaned = cleanedText(from: inlineMessage)
            return cleaned.isEmpty ? nil : cleaned
        }

        if let compactMessage = firstCapture(
            in: html,
            pattern: "<div[^>]*class=[\"'][^\"']*alert-error[^\"']*[\"'][^>]*>([\\s\\S]*?)</div>"
        ) {
            let cleaned = cleanedText(from: compactMessage)
            return cleaned.isEmpty ? nil : cleaned
        }

        return nil
    }

    func isLikelyLoginPage(_ html: String) -> Bool {
        let normalized = html.lowercased()
        let hasLoginFormAction =
            normalized.contains("action=\"/login\"")
            || normalized.contains("action='/login'")
            || normalized.contains("/login")

        let hasCredentialInputs =
            normalized.contains("session[email]")
            || normalized.contains("session[password]")
            || normalized.contains("name=\"email\"")
            || normalized.contains("type=\"password\"")

        let hasLoginLanguage =
            normalized.contains("log in")
            || normalized.contains("sign in")
            || normalized.contains("forgot password")

        return hasLoginFormAction && (hasCredentialInputs || hasLoginLanguage)
    }

    func isLikelyAuthenticatedAccountPage(_ html: String) -> Bool {
        let normalized = html.lowercased()
        if normalized.contains("account-show") { return true }
        if normalized.contains("coursebox--shortname") { return true }
        if normalized.contains("student courses") || normalized.contains("instructor courses") { return true }
        if normalized.contains("href=\"/logout\"") { return true }
        if normalized.contains("add course") { return true }
        if firstCapture(in: html, pattern: "href=[\"']/courses/[0-9]+[\"']") != nil { return true }
        return false
    }

    func parseCourses(from html: String) -> [GSCourse] {
        let anchors = captures(
            in: html,
            pattern: "<a[^>]*href=[\"']/courses/([^\"'/?#]+)(?:[^\"']*)[\"'][^>]*>([\\s\\S]*?)</a>"
        )

        var seenIDs = Set<String>()
        var courses: [GSCourse] = []

        for match in anchors {
            guard match.count >= 3 else { continue }
            let courseId = match[1]
            guard seenIDs.insert(courseId).inserted else { continue }

            let inner = match[2]
            let shortName = cleanedText(from: firstCapture(in: inner, pattern: "<h3[^>]*courseBox--shortname[^>]*>([\\s\\S]*?)</h3>") ?? "")
            let fullName = cleanedText(from: firstCapture(in: inner, pattern: "<div[^>]*courseBox--name[^>]*>([\\s\\S]*?)</div>") ?? "")

            let fallbackText = cleanedText(from: inner)
            let resolvedShort = shortName.isEmpty ? fallbackText : shortName
            let resolvedFull = fullName.isEmpty ? resolvedShort : fullName

            courses.append(
                GSCourse(
                    id: courseId,
                    shortName: resolvedShort,
                    fullName: resolvedFull
                )
            )
        }

        return courses
    }

    func parseAssignments(from html: String, courseId: String) throws -> [GSAssignment] {
        let instructor = parseInstructorAssignments(from: html, courseId: courseId)
        if !instructor.isEmpty {
            return instructor
        }

        let student = parseStudentAssignments(from: html, courseId: courseId)
        if !student.isEmpty {
            return student
        }

        let embedded = parseAssignmentsFromEmbeddedJSON(from: html, courseId: courseId)
        if !embedded.isEmpty {
            return embedded
        }

        let linkFallback = parseAssignmentLinksFallback(from: html, courseId: courseId)
        if !linkFallback.isEmpty {
            return linkFallback
        }

        let buttonFallback = parseAssignmentButtonsFallback(from: html, courseId: courseId)
        if !buttonFallback.isEmpty {
            return buttonFallback
        }

        // Empty assignment lists are valid for some courses.
        return []
    }

    func parseTemplatePDFLink(from html: String, pageURL: URL) -> URL? {
        let links = captures(
            in: html,
            pattern: "<a[^>]*href=[\"']([^\"']+)[\"'][^>]*>([\\s\\S]*?)</a>"
        )

        let preferredKeywords = ["template", "starter", "worksheet", "download", "instructions"]
        var fallbackPDF: URL?

        for match in links {
            guard match.count >= 3 else { continue }
            let hrefRaw = decodeHTMLEntities(match[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hrefRaw.isEmpty else { continue }

            let label = cleanedText(from: match[2]).lowercased()
            let hrefLower = hrefRaw.lowercased()

            guard let url = normalizedURL(from: hrefRaw, relativeTo: pageURL) else { continue }

            // Un-extensioned template URL path fallback
            if hrefLower.hasSuffix("/template") || hrefLower.contains("/template?") {
                return url
            }

            let isPDF = hrefLower.contains(".pdf") || label.contains("pdf")
            guard isPDF else { continue }

            if fallbackPDF == nil {
                fallbackPDF = url
            }

            if preferredKeywords.contains(where: { hrefLower.contains($0) || label.contains($0) }) {
                return url
            }
        }

        if let found = fallbackPDF {
            return found
        }
        
        // --- React Fallbacks ---
        let normalized = html
            .replacingOccurrences(of: "\\\\/", with: "/")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\\"", with: "\"")

        // 1. Look for explicit /template paths in JSON strings
        if let templateMatch = firstCapture(
            in: normalized,
            pattern: "[\"'](/courses/[0-9]+/assignments/[0-9]+/template(?:\\?[^\"']*)?)[\"']"
        ) {
            if let url = normalizedURL(from: templateMatch, relativeTo: pageURL) {
                return url
            }
        }

        // 2. Look for any PDF or template URL in common JSON keys
        let jsonURLs = captures(
            in: normalized,
            pattern: "[\"'](?:url|template_url|pdf_url|href|file_url)[\"']\\s*:\\s*[\"']([^\"']+)[\"']"
        )
        for match in jsonURLs {
            guard match.count >= 2 else { continue }
            let urlRaw = match[1]
            if urlRaw.lowercased().contains(".pdf") || urlRaw.lowercased().contains("template") {
                if let url = normalizedURL(from: urlRaw, relativeTo: pageURL) {
                    return url
                }
            }
        }

        // 3. Bruteforce search for any string combining http or / with .pdf
        let bruteForceMatches = captures(
            in: normalized,
            pattern: "[\"']((?:https?://|/)[^\"']+\\.pdf(?:\\?[^\"']*)?)[\"']"
        )
        for match in bruteForceMatches {
            guard match.count >= 2 else { continue }
            if let url = normalizedURL(from: match[1], relativeTo: pageURL) {
                return url
            }
        }

        return nil
    }

    func parseSubmissionFormSpec(from html: String, pageURL: URL) -> SubmissionFormSpec? {
        let specs = parseSubmissionFormSpecs(from: html, pageURL: pageURL)
        return specs.first
    }

    func parseSubmissionFormSpecs(from html: String, pageURL: URL) -> [SubmissionFormSpec] {
        let formMatches = captures(
            in: html,
            pattern: "<form[^>]*action=[\"']([^\"']*submissions[^\"']*)[\"'][^>]*>([\\s\\S]*?)</form>"
        )

        var specs: [SubmissionFormSpec] = []

        for match in formMatches {
            guard match.count >= 3 else { continue }
            let actionRaw = decodeHTMLEntities(match[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !actionRaw.isEmpty else { continue }
            guard let actionURL = normalizedURL(from: actionRaw, relativeTo: pageURL) else { continue }

            let fullFormTag = match[0]
            let formHTML = match[2]
            let method = decodeHTMLEntities(attributeValue(in: fullFormTag, attribute: "method") ?? "get")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let isRemote = ["1", "true", "yes"].contains(
                (attributeValue(in: fullFormTag, attribute: "data-remote") ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            ) || fullFormTag.lowercased().contains("data-remote")
            let enctypeRaw = attributeValue(in: fullFormTag, attribute: "enctype")
            let enctype = enctypeRaw?.trimmingCharacters(in: .whitespacesAndNewlines)

            let fileFieldName =
                firstCapture(in: formHTML, pattern: "<input[^>]*name=[\"']([^\"']+)[\"'][^>]*type=[\"']file[\"'][^>]*>")
                ?? firstCapture(in: formHTML, pattern: "<input[^>]*type=[\"']file[\"'][^>]*name=[\"']([^\"']+)[\"'][^>]*>")
                ?? "submission[files][]"

            let fileInputTag =
                firstCapture(in: formHTML, pattern: "(<input[^>]*type=[\"']file[\"'][^>]*>)")
                ?? firstCapture(in: formHTML, pattern: "(<input[^>]*name=[\"'][^\"']+[\"'][^>]*type=[\"']file[\"'][^>]*>)")
            let fileInputAccept = fileInputTag.flatMap { attributeValue(in: $0, attribute: "accept") }
            let directUploadURL = fileInputTag
                .flatMap { attributeValue(in: $0, attribute: "data-direct-upload-url") }
                .flatMap { normalizedURL(from: decodeHTMLEntities($0), relativeTo: pageURL) }

            var hiddenFields: [String: String] = [:]
            let hiddenInputs = captures(
                in: formHTML,
                pattern: "<input[^>]*type=[\"']hidden[\"'][^>]*>"
            )

            for input in hiddenInputs {
                guard let tag = input.first else { continue }
                guard let nameRaw = attributeValue(in: tag, attribute: "name") else { continue }
                let name = decodeHTMLEntities(nameRaw).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let value = decodeHTMLEntities(attributeValue(in: tag, attribute: "value") ?? "")
                hiddenFields[name] = value
            }

            var allFields = hiddenFields
            let defaults = parseFormDefaultFields(from: formHTML)
            for (key, value) in defaults {
                allFields[key] = value
            }
            let submitButtons = parseSubmitButtons(from: formHTML, pageURL: pageURL)
            let requiredFields = parseRequiredFields(from: formHTML)

            specs.append(
                SubmissionFormSpec(
                    actionURL: actionURL,
                    fileFieldName: decodeHTMLEntities(fileFieldName).trimmingCharacters(in: .whitespacesAndNewlines),
                    method: method.isEmpty ? "get" : method,
                    isRemote: isRemote,
                    enctype: enctype,
                    fileInputAccept: fileInputAccept,
                    fileInputDirectUploadURL: directUploadURL,
                    hiddenFields: hiddenFields,
                    allFields: allFields,
                    submitButtons: submitButtons,
                    requiredFields: requiredFields
                )
            )
        }

        return specs
    }

    // MARK: - Private

    private func parseInstructorAssignments(from html: String, courseId: String) -> [GSAssignment] {
        guard let reactPropsRaw = extractAssignmentsReactProps(from: html) else { return [] }

        guard let data = reactPropsRaw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let table = json["table_data"] as? [[String: Any]] else {
            return []
        }

        var assignments: [GSAssignment] = []

        for item in table {
            guard (item["type"] as? String) == "assignment" else { continue }
            let name = (item["title"] as? String ?? "Untitled").trimmingCharacters(in: .whitespacesAndNewlines)
            let urlString = item["url"] as? String ?? ""
            let assignmentID = extractAssignmentID(fromPathOrURL: urlString) ?? ""
            guard !assignmentID.isEmpty else { continue }

            let window = item["submission_window"] as? [String: Any]
            let releaseDate = GradescopeDateParser.parse(window?["release_date"] as? String)
            let dueDate = GradescopeDateParser.parse(window?["due_date"] as? String)
            let lateDueDate = GradescopeDateParser.parse(window?["hard_due_date"] as? String)

            let maxGrade: Double?
            if let points = item["total_points"] as? Double {
                maxGrade = points
            } else if let pointsString = item["total_points"] as? String {
                maxGrade = Double(pointsString)
            } else {
                maxGrade = nil
            }

            assignments.append(
                GSAssignment(
                    id: assignmentID,
                    courseId: courseId,
                    name: name,
                    releaseDate: releaseDate,
                    dueDate: dueDate,
                    lateDueDate: lateDueDate,
                    submissionsStatus: nil,
                    grade: nil,
                    maxGrade: maxGrade
                )
            )
        }

        return assignments
    }

    private func parseStudentAssignments(from html: String, courseId: String) -> [GSAssignment] {
        var rows = captures(in: html, pattern: "<tr[^>]*role=[\"']row[\"'][^>]*>([\\s\\S]*?)</tr>")
        if rows.isEmpty {
            rows = captures(in: html, pattern: "<tr[^>]*>([\\s\\S]*?)</tr>")
        }

        var assignments: [GSAssignment] = []
        var seenAssignmentIDs = Set<String>()

        for row in rows {
            guard row.count >= 2 else { continue }
            let rowHTML = row[1]

            let titleRaw =
                firstCapture(in: rowHTML, pattern: "<th[^>]*>([\\s\\S]*?)</th>")
                ?? firstCapture(in: rowHTML, pattern: "<a[^>]*href=[\"'][^\"']*/assignments/[^\"']+[\"'][^>]*>([\\s\\S]*?)</a>")
                ?? ""
            var title = cleanedText(from: titleRaw)

            let assignmentID =
                firstCapture(in: rowHTML, pattern: "href=[\"'][^\"']*/assignments/([^\"'/?#]+)[\"']")
                ?? firstCapture(in: rowHTML, pattern: "data-assignment-id=[\"']([^\"']+)[\"']")
                ?? ""
            if assignmentID.isEmpty { continue }
            if !seenAssignmentIDs.insert(assignmentID).inserted { continue }

            if title.isEmpty {
                title = "Assignment \(assignmentID)"
            }

            let allDueDates = captures(in: rowHTML, pattern: "submissionTimeChart--dueDate[^>]*datetime=[\"']([^\"']+)[\"']")
                .compactMap { $0.count > 1 ? $0[1] : nil }

            let releaseDateRaw = firstCapture(in: rowHTML, pattern: "submissionTimeChart--releaseDate[^>]*datetime=[\"']([^\"']+)[\"']")
            let statusCell = firstCapture(in: rowHTML, pattern: "<td[^>]*>([\\s\\S]*?)</td>") ?? ""
            let statusText = cleanedText(from: statusCell)

            let points = parsePoints(from: statusText)

            assignments.append(
                GSAssignment(
                    id: assignmentID,
                    courseId: courseId,
                    name: title,
                    releaseDate: GradescopeDateParser.parse(releaseDateRaw),
                    dueDate: GradescopeDateParser.parse(allDueDates.first),
                    lateDueDate: GradescopeDateParser.parse(allDueDates.dropFirst().first),
                    submissionsStatus: statusText.isEmpty ? nil : statusText,
                    grade: points?.grade,
                    maxGrade: points?.maxGrade
                )
            )
        }

        return assignments
    }

    private func parseAssignmentLinksFallback(from html: String, courseId: String) -> [GSAssignment] {
        let links = captures(
            in: html,
            pattern: "<a[^>]*href=[\"']([^\"']+)[\"'][^>]*>([\\s\\S]*?)</a>"
        )

        var assignments: [GSAssignment] = []
        var seenAssignmentIDs = Set<String>()

        for match in links {
            guard match.count >= 3 else { continue }
            let href = decodeHTMLEntities(match[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let assignmentID: String
            if let parsed = extractCourseAndAssignment(fromPathOrURL: href) {
                guard parsed.courseId == courseId else { continue }
                assignmentID = parsed.assignmentId
            } else if let looseID = firstCapture(in: href, pattern: "/assignments/([^/?#]+)")?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !looseID.isEmpty {
                assignmentID = looseID
            } else {
                continue
            }

            guard seenAssignmentIDs.insert(assignmentID).inserted else { continue }

            let nameText = cleanedText(from: match[2])
            let name = nameText.isEmpty ? "Assignment \(assignmentID)" : nameText

            assignments.append(
                GSAssignment(
                    id: assignmentID,
                    courseId: courseId,
                    name: name,
                    releaseDate: nil,
                    dueDate: nil,
                    lateDueDate: nil,
                    submissionsStatus: nil,
                    grade: nil,
                    maxGrade: nil
                )
            )
        }

        return assignments
    }

    private func parseAssignmentButtonsFallback(from html: String, courseId: String) -> [GSAssignment] {
        let buttons = captures(
            in: html,
            pattern: "<button[^>]*data-assignment-id=[\"']([^\"']+)[\"'][^>]*>([\\s\\S]*?)</button>"
        )

        var assignments: [GSAssignment] = []
        var seenIDs = Set<String>()

        for match in buttons {
            guard match.count >= 3 else { continue }
            let assignmentID = decodeHTMLEntities(match[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !assignmentID.isEmpty else { continue }
            guard seenIDs.insert(assignmentID).inserted else { continue }

            let nameText = cleanedText(from: match[2])
            let name = nameText.isEmpty ? "Assignment \(assignmentID)" : nameText

            assignments.append(
                GSAssignment(
                    id: assignmentID,
                    courseId: courseId,
                    name: name,
                    releaseDate: nil,
                    dueDate: nil,
                    lateDueDate: nil,
                    submissionsStatus: nil,
                    grade: nil,
                    maxGrade: nil
                )
            )
        }

        return assignments
    }

    private func parseAssignmentsFromEmbeddedJSON(from html: String, courseId: String) -> [GSAssignment] {
        let normalized = html
            .replacingOccurrences(of: "\\\\/", with: "/")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\\"", with: "\"")

        var assignments: [GSAssignment] = []
        var seenIDs = Set<String>()

        // title first, then url
        let titleURLMatches = captures(
            in: normalized,
            pattern: "\"title\"\\s*:\\s*\"([^\"]+)\"[\\s\\S]{0,800}?\"url\"\\s*:\\s*\"/courses/\(NSRegularExpression.escapedPattern(for: courseId))/assignments/([^\"/?#]+)\""
        )

        for match in titleURLMatches {
            guard match.count >= 3 else { continue }
            let rawTitle = decodeHTMLEntities(match[1])
            let assignmentID = match[2].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !assignmentID.isEmpty else { continue }
            guard seenIDs.insert(assignmentID).inserted else { continue }

            assignments.append(
                GSAssignment(
                    id: assignmentID,
                    courseId: courseId,
                    name: cleanedText(from: rawTitle),
                    releaseDate: nil,
                    dueDate: nil,
                    lateDueDate: nil,
                    submissionsStatus: nil,
                    grade: nil,
                    maxGrade: nil
                )
            )
        }

        // url first, then title
        let urlTitleMatches = captures(
            in: normalized,
            pattern: "\"url\"\\s*:\\s*\"/courses/\(NSRegularExpression.escapedPattern(for: courseId))/assignments/([^\"/?#]+)\"[\\s\\S]{0,800}?\"title\"\\s*:\\s*\"([^\"]+)\""
        )

        for match in urlTitleMatches {
            guard match.count >= 3 else { continue }
            let assignmentID = match[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !assignmentID.isEmpty else { continue }
            guard seenIDs.insert(assignmentID).inserted else { continue }

            let rawTitle = decodeHTMLEntities(match[2])
            assignments.append(
                GSAssignment(
                    id: assignmentID,
                    courseId: courseId,
                    name: cleanedText(from: rawTitle),
                    releaseDate: nil,
                    dueDate: nil,
                    lateDueDate: nil,
                    submissionsStatus: nil,
                    grade: nil,
                    maxGrade: nil
                )
            )
        }

        return assignments
    }

    private func parsePoints(from statusText: String) -> (grade: Double, maxGrade: Double)? {
        let cleaned = statusText.replacingOccurrences(of: ",", with: "")
        guard let match = captures(in: cleaned, pattern: "([0-9]+(?:\\.[0-9]+)?)\\s*/\\s*([0-9]+(?:\\.[0-9]+)?)").first,
              match.count >= 3 else {
            return nil
        }

        guard let grade = Double(match[1]),
              let max = Double(match[2]) else {
            return nil
        }

        return (grade, max)
    }

    private func extractAssignmentID(fromPathOrURL pathOrURL: String) -> String? {
        extractCourseAndAssignment(fromPathOrURL: pathOrURL)?.assignmentId
    }

    private func extractCourseAndAssignment(fromPathOrURL pathOrURL: String) -> (courseId: String, assignmentId: String)? {
        let decoded = decodeHTMLEntities(pathOrURL)
        guard let courseID = firstCapture(in: decoded, pattern: "/courses/([^/?#]+)/assignments/[^/?#]+"),
              let assignmentID = firstCapture(in: decoded, pattern: "/courses/[^/?#]+/assignments/([^/?#]+)") else {
            return nil
        }

        let cleanedCourse = courseID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedAssignment = assignmentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedCourse.isEmpty, !cleanedAssignment.isEmpty else {
            return nil
        }

        return (cleanedCourse, cleanedAssignment)
    }

    private func extractAssignmentsReactProps(from html: String) -> String? {
        guard let divTag = firstCapture(
            in: html,
            pattern: "<div[^>]*data-react-class=[\"']AssignmentsTable[\"'][^>]*>"
        ) else {
            return nil
        }

        let rawProps = firstCapture(in: divTag, pattern: "data-react-props=[\"']([\\s\\S]*?)[\"']")
        guard let rawProps else { return nil }

        return decodeHTMLEntities(rawProps)
    }

    private func normalizedURL(from raw: String, relativeTo pageURL: URL) -> URL? {
        if let absolute = URL(string: raw), absolute.scheme != nil {
            return absolute
        }

        if raw.hasPrefix("/") {
            var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)
            components?.path = raw
            components?.query = nil
            components?.fragment = nil
            return components?.url
        }

        return URL(string: raw, relativeTo: pageURL)?.absoluteURL
    }

    private func cleanedText(from htmlFragment: String) -> String {
        let withoutTags = htmlFragment.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let decoded = decodeHTMLEntities(withoutTags)
        return decoded
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseFormDefaultFields(from formHTML: String) -> [String: String] {
        var fields: [String: String] = [:]

        let inputTags = captures(in: formHTML, pattern: "<input[^>]*>")
        for match in inputTags {
            guard let tag = match.first else { continue }
            if hasAttribute(in: tag, attribute: "disabled") { continue }
            guard let nameRaw = attributeValue(in: tag, attribute: "name") else { continue }
            let name = decodeHTMLEntities(nameRaw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            let type = (attributeValue(in: tag, attribute: "type") ?? "text")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if type == "file" { continue }
            if (type == "checkbox" || type == "radio") && !hasAttribute(in: tag, attribute: "checked") {
                continue
            }

            let value = decodeHTMLEntities(attributeValue(in: tag, attribute: "value") ?? "")
            fields[name] = value
        }

        let selectTags = captures(
            in: formHTML,
            pattern: "<select[^>]*name=[\"']([^\"']+)[\"'][^>]*>([\\s\\S]*?)</select>"
        )
        for match in selectTags {
            guard match.count >= 3 else { continue }
            let name = decodeHTMLEntities(match[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let innerHTML = match[2]

            if let selected = firstCapture(
                in: innerHTML,
                pattern: "<option[^>]*selected(?:\\s*=\\s*[\"'][^\"']*[\"'])?[^>]*value=[\"']([^\"']*)[\"'][^>]*>"
            ) ?? firstCapture(
                in: innerHTML,
                pattern: "<option[^>]*value=[\"']([^\"']*)[\"'][^>]*selected(?:\\s*=\\s*[\"'][^\"']*[\"'])?[^>]*>"
            ) {
                fields[name] = decodeHTMLEntities(selected)
                continue
            }

            if let firstValue = firstCapture(
                in: innerHTML,
                pattern: "<option[^>]*value=[\"']([^\"']*)[\"'][^>]*>"
            ) {
                fields[name] = decodeHTMLEntities(firstValue)
            }
        }

        let textareas = captures(
            in: formHTML,
            pattern: "<textarea[^>]*name=[\"']([^\"']+)[\"'][^>]*>([\\s\\S]*?)</textarea>"
        )
        for match in textareas {
            guard match.count >= 3 else { continue }
            let name = decodeHTMLEntities(match[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let value = decodeHTMLEntities(cleanedText(from: match[2]))
            fields[name] = value
        }

        return fields
    }

    private func parseSubmitButtons(from formHTML: String, pageURL: URL) -> [GSSubmissionSubmitButton] {
        var buttons: [GSSubmissionSubmitButton] = []

        let inputButtons = captures(
            in: formHTML,
            pattern: "<input[^>]*type=[\"'](?:submit|button)[\"'][^>]*>"
        )
        for match in inputButtons {
            guard let tag = match.first else { continue }
            if hasAttribute(in: tag, attribute: "disabled") { continue }

            let name = (attributeValue(in: tag, attribute: "name").map(decodeHTMLEntities))?.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = decodeHTMLEntities(attributeValue(in: tag, attribute: "value") ?? "")
            let label = value.isEmpty ? "Submit" : value
            let actionURL = attributeValue(in: tag, attribute: "formaction")
                .map(decodeHTMLEntities)
                .flatMap { normalizedURL(from: $0, relativeTo: pageURL) }
            let method = (attributeValue(in: tag, attribute: "formmethod"))?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let enctype = (attributeValue(in: tag, attribute: "formenctype"))?.trimmingCharacters(in: .whitespacesAndNewlines)

            buttons.append(
                GSSubmissionSubmitButton(
                    name: name?.isEmpty == true ? nil : name,
                    value: value.isEmpty ? nil : value,
                    label: label,
                    formActionURL: actionURL,
                    formMethod: method?.isEmpty == true ? nil : method,
                    formEnctype: enctype?.isEmpty == true ? nil : enctype
                )
            )
        }

        let buttonTags = captures(
            in: formHTML,
            pattern: "<button[^>]*>([\\s\\S]*?)</button>"
        )
        for match in buttonTags {
            guard match.count >= 2 else { continue }
            let tag = match[0]
            let inner = match[1]
            if hasAttribute(in: tag, attribute: "disabled") { continue }

            let type = (attributeValue(in: tag, attribute: "type") ?? "submit")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard type == "submit" || type == "button" else { continue }

            let name = (attributeValue(in: tag, attribute: "name").map(decodeHTMLEntities))?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = attributeValue(in: tag, attribute: "value").map(decodeHTMLEntities)
            let label = cleanedText(from: inner)
            let value = (rawValue?.isEmpty == false ? rawValue : label)
            let actionURL = attributeValue(in: tag, attribute: "formaction")
                .map(decodeHTMLEntities)
                .flatMap { normalizedURL(from: $0, relativeTo: pageURL) }
            let method = (attributeValue(in: tag, attribute: "formmethod"))?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let enctype = (attributeValue(in: tag, attribute: "formenctype"))?.trimmingCharacters(in: .whitespacesAndNewlines)

            buttons.append(
                GSSubmissionSubmitButton(
                    name: name?.isEmpty == true ? nil : name,
                    value: value?.isEmpty == true ? nil : value,
                    label: label.isEmpty ? "Submit" : label,
                    formActionURL: actionURL,
                    formMethod: method?.isEmpty == true ? nil : method,
                    formEnctype: enctype?.isEmpty == true ? nil : enctype
                )
            )
        }

        // Always keep at least one default submit option.
        if buttons.isEmpty {
            buttons.append(
                GSSubmissionSubmitButton(
                    name: nil,
                    value: nil,
                    label: "Submit",
                    formActionURL: nil,
                    formMethod: nil,
                    formEnctype: nil
                )
            )
        }

        return buttons
    }

    private func parseRequiredFields(from formHTML: String) -> [GSRequiredField] {
        var result: [GSRequiredField] = []
        var seen = Set<String>()

        let inputTags = captures(in: formHTML, pattern: "<input[^>]*>")
        for match in inputTags {
            guard let tag = match.first else { continue }
            guard hasAttribute(in: tag, attribute: "required") else { continue }
            guard !hasAttribute(in: tag, attribute: "disabled") else { continue }
            guard let nameRaw = attributeValue(in: tag, attribute: "name") else { continue }
            let name = decodeHTMLEntities(nameRaw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { continue }

            let inputTypeRaw = attributeValue(in: tag, attribute: "type") ?? "text"
            let inputType = inputTypeRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let fieldType: GSRequiredFieldType
            switch inputType {
            case "text": fieldType = .text
            case "email": fieldType = .email
            case "number": fieldType = .number
            case "checkbox": fieldType = .checkbox
            case "radio": fieldType = .radio
            case "hidden": fieldType = .hidden
            default: fieldType = .unknown
            }

            let label = decodeHTMLEntities(attributeValue(in: tag, attribute: "aria-label") ?? name)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let defaultValue = decodeHTMLEntities(attributeValue(in: tag, attribute: "value") ?? "")

            result.append(
                GSRequiredField(
                    name: name,
                    label: label.isEmpty ? name : label,
                    type: fieldType,
                    options: [],
                    defaultValue: defaultValue.isEmpty ? nil : defaultValue,
                    isRequired: true
                )
            )
        }

        let textareaTags = captures(
            in: formHTML,
            pattern: "<textarea[^>]*name=[\"']([^\"']+)[\"'][^>]*required[^>]*>([\\s\\S]*?)</textarea>"
        )
        for match in textareaTags {
            guard match.count >= 3 else { continue }
            let name = decodeHTMLEntities(match[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { continue }
            let value = decodeHTMLEntities(cleanedText(from: match[2]))
            result.append(
                GSRequiredField(
                    name: name,
                    label: name,
                    type: .textarea,
                    options: [],
                    defaultValue: value.isEmpty ? nil : value,
                    isRequired: true
                )
            )
        }

        let selectTags = captures(
            in: formHTML,
            pattern: "<select[^>]*name=[\"']([^\"']+)[\"'][^>]*required[^>]*>([\\s\\S]*?)</select>"
        )
        for match in selectTags {
            guard match.count >= 3 else { continue }
            let name = decodeHTMLEntities(match[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { continue }
            let options = parseSelectOptions(from: match[2])
            let defaultValue = options.first(where: { !$0.value.isEmpty })?.value
            result.append(
                GSRequiredField(
                    name: name,
                    label: name,
                    type: .select,
                    options: options,
                    defaultValue: defaultValue,
                    isRequired: true
                )
            )
        }

        return result
    }

    private func parseSelectOptions(from innerHTML: String) -> [GSRequiredFieldOption] {
        let optionMatches = captures(
            in: innerHTML,
            pattern: "<option[^>]*value=[\"']([^\"']*)[\"'][^>]*>([\\s\\S]*?)</option>"
        )
        return optionMatches.compactMap { match in
            guard match.count >= 3 else { return nil }
            let value = decodeHTMLEntities(match[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let label = cleanedText(from: match[2])
            return GSRequiredFieldOption(value: value, label: label.isEmpty ? value : label)
        }
    }

    private func attributeValue(in htmlTag: String, attribute: String) -> String? {
        let escapedAttribute = NSRegularExpression.escapedPattern(for: attribute)
        return firstCapture(
            in: htmlTag,
            pattern: "\(escapedAttribute)\\s*=\\s*[\"']([^\"']*)[\"']"
        )
    }

    private func hasAttribute(in htmlTag: String, attribute: String) -> Bool {
        let escapedAttribute = NSRegularExpression.escapedPattern(for: attribute)
        return firstCapture(
            in: htmlTag,
            pattern: "(?:\\s|^)\(escapedAttribute)(?:\\s*=\\s*[\"'][^\"']*[\"'])?(?:\\s|>|$)"
        ) != nil
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        let wrapped = "<span>\(text)</span>"
        guard let data = wrapped.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return text
        }

        return attributed.string
    }

    private func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(location: 0, length: (text as NSString).length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }

        if match.numberOfRanges >= 2,
           let captureRange = Range(match.range(at: 1), in: text) {
            return String(text[captureRange])
        }

        if let fullRange = Range(match.range(at: 0), in: text) {
            return String(text[fullRange])
        }

        return nil
    }

    private func captures(in text: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: range)

        return matches.map { match in
            (0..<match.numberOfRanges).compactMap { idx in
                let matchRange = match.range(at: idx)
                guard matchRange.location != NSNotFound else { return nil }
                return nsText.substring(with: matchRange)
            }
        }
    }
}
