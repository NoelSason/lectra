import Foundation
import WebKit

@MainActor
final class GradescopeWebScrapeService: NSObject {
    private struct ScrapeResult {
        let assignments: [GSAssignment]
        let debugLines: [String]
    }

    private let parser: GradescopeHTMLParser

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<ScrapeResult, Error>?
    private var requestedCourseID: String?
    private var attemptCount = 0
    private var debugLines: [String] = []

    private let maxAttempts = 3

    init(parser: GradescopeHTMLParser) {
        self.parser = parser
    }

    func fetchAssignments(courseId: String) async throws -> [GSAssignment] {
        let result = try await fetchAssignmentsWithDebug(courseId: courseId)
        return result.assignments
    }

    func fetchAssignmentsWithDebug(courseId: String) async throws -> (assignments: [GSAssignment], debugLines: [String]) {
        guard continuation == nil else {
            throw GSError.network("Gradescope web scraper is busy")
        }

        requestedCourseID = courseId
        attemptCount = 0
        debugLines = ["web-scrape start: course=\(courseId)"]

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        guard let url = URL(string: "https://www.gradescope.com/courses/\(courseId)") else {
            throw GSError.network("Invalid course URL")
        }

        debugLines.append("web-scrape load: \(url.path)")
        webView.load(URLRequest(url: url))

        let result = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
        return (result.assignments, result.debugLines)
    }

    private func evaluateAssignments(on webView: WKWebView) {
        debugLines.append("web-scrape evaluate attempt \(attemptCount + 1)")
        webView.evaluateJavaScript(assignmentsExtractionScript) { [weak self, weak webView] result, error in
            guard let self else { return }

            if let error {
                self.finish(with: .failure(GSError.network(error.localizedDescription)))
                return
            }

            let courseID = self.requestedCourseID ?? ""
            let candidatesJSON = (result as? String) ?? "[]"
            let jsAssignments = self.parseAssignmentsFromJSResult(candidatesJSON, courseId: courseID)
            self.debugLines.append("web-scrape js assignments=\(jsAssignments.count)")

            if !jsAssignments.isEmpty {
                self.finish(with: .success(ScrapeResult(assignments: jsAssignments, debugLines: self.debugLines)))
                return
            }

            webView?.evaluateJavaScript("document.documentElement.outerHTML.toString()") { [weak self, weak webView] htmlResult, htmlError in
                guard let self else { return }

                if let htmlError {
                    self.finish(with: .failure(GSError.network(htmlError.localizedDescription)))
                    return
                }

                let html = (htmlResult as? String) ?? ""
                if self.parser.isLikelyLoginPage(html) {
                    self.debugLines.append("web-scrape html appears to be login page")
                    self.finish(with: .failure(GSError.unauthorized))
                    return
                }

                let parsedAssignments = (try? self.parser.parseAssignments(from: html, courseId: courseID)) ?? []
                self.debugLines.append("web-scrape html parser assignments=\(parsedAssignments.count)")
                self.debugLines.append("web-scrape html signals \(self.assignmentHTMLSignals(in: html))")
                if !parsedAssignments.isEmpty || self.attemptCount >= self.maxAttempts {
                    self.finish(with: .success(ScrapeResult(assignments: parsedAssignments, debugLines: self.debugLines)))
                    return
                }

                self.attemptCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self, weak webView] in
                    guard let self, let webView else { return }
                    self.evaluateAssignments(on: webView)
                }
            }
        }
    }

    private func parseAssignmentsFromJSResult(_ jsonString: String, courseId: String) -> [GSAssignment] {
        guard let data = jsonString.data(using: .utf8),
              let rawItems = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        var assignments: [GSAssignment] = []
        var seenIDs = Set<String>()

        for item in rawItems {
            guard let assignmentID = item["id"] as? String else { continue }
            let trimmedID = assignmentID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty else { continue }

            let candidateCourseID = (item["courseId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !candidateCourseID.isEmpty && candidateCourseID != courseId {
                continue
            }

            guard seenIDs.insert(trimmedID).inserted else { continue }

            let rawName = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = rawName.isEmpty ? "Assignment \(trimmedID)" : rawName

            assignments.append(
                GSAssignment(
                    id: trimmedID,
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

    private var assignmentsExtractionScript: String {
        """
        (() => {
          const courseLinkRegex = /\\/courses\\/([^\\/?#]+)\\/assignments\\/([^\\/?#]+)/;
          const looseLinkRegex = /\\/assignments\\/([^\\/?#]+)/;
          const seen = new Set();
          const out = [];

          const add = (courseId, assignmentId, name) => {
            const id = (assignmentId || '').trim();
            if (!id) return;
            const key = `${courseId || ''}:${id}`;
            if (seen.has(key)) return;
            seen.add(key);
            out.push({
              courseId: (courseId || '').trim(),
              id,
              name: (name || '').replace(/\\s+/g, ' ').trim()
            });
          };

          document.querySelectorAll('a[href*="/assignments/"]').forEach((anchor) => {
            const href = anchor.getAttribute('href') || '';
            const courseMatch = href.match(courseLinkRegex);
            if (courseMatch) {
              add(courseMatch[1], courseMatch[2], anchor.textContent || '');
              return;
            }

            const looseMatch = href.match(looseLinkRegex);
            if (!looseMatch) return;
            add('', looseMatch[1], anchor.textContent || '');
          });

          document.querySelectorAll('[data-assignment-id]').forEach((element) => {
            const assignmentId = element.getAttribute('data-assignment-id') || '';
            if (!assignmentId) return;

            let courseId = element.getAttribute('data-course-id') || '';
            let name = '';

            const row = element.closest('tr, li, div');
            if (row) {
              const candidate = row.querySelector('th, h1, h2, h3, h4, .table--primaryLink, a');
              if (candidate) {
                name = candidate.textContent || '';
                const href = candidate.getAttribute && candidate.getAttribute('href');
                if (!courseId && href) {
                  const courseMatch = href.match(courseLinkRegex);
                  if (courseMatch) {
                    courseId = courseMatch[1];
                  }
                }
              }
            }

            add(courseId, assignmentId, name);
          });

          document.querySelectorAll('[data-react-class="AssignmentsTable"]').forEach((element) => {
            const raw = element.getAttribute('data-react-props');
            if (!raw) return;
            try {
              const parsed = JSON.parse(raw);
              const rows = parsed.table_data || [];
              rows.forEach((row) => {
                if (row.type !== 'assignment') return;
                const url = String(row.url || '');
                const courseMatch = url.match(courseLinkRegex);
                if (courseMatch) {
                  add(courseMatch[1], courseMatch[2], String(row.title || ''));
                  return;
                }

                const looseMatch = url.match(looseLinkRegex);
                if (looseMatch) {
                  add('', looseMatch[1], String(row.title || ''));
                }
              });
            } catch (_) {}
          });

          return JSON.stringify(out);
        })()
        """
    }

    private func finish(with result: Result<ScrapeResult, Error>) {
        continuation?.resume(with: result)
        continuation = nil

        webView?.navigationDelegate = nil
        webView = nil

        requestedCourseID = nil
        attemptCount = 0
        debugLines = []
    }

    private func assignmentHTMLSignals(in html: String) -> String {
        let assignmentLinks = matchCount(in: html, pattern: "/courses/[^\"'\\s<>]+/assignments/[^\"'\\s<>]+")
        let looseAssignmentLinks = matchCount(in: html, pattern: "/assignments/[^\"'\\s<>]+")
        let dataAssignmentIDs = matchCount(in: html, pattern: "data-assignment-id=[\"'][^\"']+[\"']")
        let assignmentsTable = matchCount(in: html, pattern: "AssignmentsTable")
        let noAssignmentsText = html.lowercased().contains("no assignments") ? "yes" : "no"
        return "links=\(assignmentLinks), loose-links=\(looseAssignmentLinks), data-ids=\(dataAssignmentIDs), table-markers=\(assignmentsTable), no-assignments-text=\(noAssignmentsText)"
    }

    private func matchCount(in text: String, pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return 0
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }
}

extension GradescopeWebScrapeService: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        evaluateAssignments(on: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(GSError.network(error.localizedDescription)))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(GSError.network(error.localizedDescription)))
    }
}
