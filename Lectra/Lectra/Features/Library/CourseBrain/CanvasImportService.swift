import Foundation
import SwiftUI
import Combine

@MainActor
final class CanvasImportService: ObservableObject {

    struct Progress: Equatable {
        var completed: Int
        var total: Int
        var currentTitle: String?
        var currentCourseName: String?

        static let empty = Progress(completed: 0, total: 0, currentTitle: nil, currentCourseName: nil)
    }

    enum Phase: Equatable {
        case idle
        case running
        case finished(imported: Int, skipped: Int, failed: Int)
        case cancelled(imported: Int, skipped: Int, failed: Int)
        case failed(message: String)
    }

    struct Dependencies {
        let canvasFolderId: () -> UUID?
        let findOrCreateFolder: (_ name: String, _ parentFolderId: UUID?) -> UUID
        let documentIdForSourceURL: (URL) -> UUID?
        let importDownloadedPDF: (
            _ tempURL: URL,
            _ title: String,
            _ sourceURL: URL,
            _ folderId: UUID,
            _ createdAt: Date
        ) -> UUID?
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Progress = .empty

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    private var activeDownloader: CourseBrainPDFDownloader?
    private var cancelRequested = false
    private var runTask: Task<Void, Never>?
    private var activePlan: [PlannedDownload] = []

    func start(courses: [CourseTwin], dependencies: Dependencies) {
        if isRunning {
            Task { @MainActor [weak self] in
                guard let self else { return }
                print("[CanvasImport] ◆ planning additional courses…")
                let newPlan = await Self.buildPlan(for: courses)
                guard !newPlan.isEmpty else { return }
                self.appendPlan(newPlan, dependencies: dependencies)
            }
            return
        }
        cancelRequested = false

        guard dependencies.canvasFolderId() != nil else {
            phase = .failed(message: "The Canvas import folder isn't set up yet.")
            return
        }

        progress = .empty
        phase = .running
        runTask = Task { @MainActor [weak self] in
            guard let self else { return }
            print("[CanvasImport] ◆ planning…")
            let plan = await Self.buildPlan(for: courses)
            self.activePlan = plan
            self.progress = Progress(completed: 0, total: plan.count, currentTitle: nil, currentCourseName: nil)

            if plan.isEmpty {
                print("[CanvasImport] ⤓ nothing to import (plan empty)")
                self.phase = .finished(imported: 0, skipped: 0, failed: 0)
                return
            }

            await self.run(dependencies: dependencies)
        }
    }

    private func appendPlan(_ newPlan: [PlannedDownload], dependencies: Dependencies) {
        let existingURLs = Set(activePlan.map { $0.sourceURL.absoluteString.lowercased() })
        let filtered = newPlan.filter { !existingURLs.contains($0.sourceURL.absoluteString.lowercased()) }
        guard !filtered.isEmpty else { return }

        if isRunning {
            activePlan.append(contentsOf: filtered)
            progress.total = activePlan.count
            print("[CanvasImport] ◆ appended \(filtered.count) items to active plan (new total: \(activePlan.count))")
        } else {
            // Started/finished in the interim, launch a new task
            activePlan = filtered
            progress = Progress(completed: 0, total: filtered.count, currentTitle: nil, currentCourseName: nil)
            phase = .running
            runTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.run(dependencies: dependencies)
            }
        }
    }

    func cancel() {
        guard isRunning else { return }
        cancelRequested = true
        activeDownloader?.cancel()
    }

    func reset() {
        guard !isRunning else { return }
        phase = .idle
        progress = .empty
    }

    // MARK: - Plan

    fileprivate struct PlannedDownload {
        let courseId: Int
        let courseFolderName: String
        let leafFolderPathComponents: [String]
        let title: String
        let sourceURL: URL
    }

    private static func buildPlan(for courses: [CourseTwin]) async -> [PlannedDownload] {
        var plan: [PlannedDownload] = []
        var seenURLs: Set<String> = []

        // Cookies are the same for every course in this batch.
        let cookies = await CanvasCookieStore.loadMergedSession().map(\.cookie)
        print("[CanvasImport] cookies available: \(cookies.count)")

        for course in courses {
            let assignmentNameById: [String: String] = course.missions.reduce(into: [:]) { acc, mission in
                let trimmed = mission.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                acc[mission.assignmentId] = trimmed
            }

            let courseFolderName: String = {
                let trimmed = course.metadata.courseName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
                if let code = course.metadata.courseCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
                    return code
                }
                return "Course \(course.courseId)"
            }()

            // === Files API discovery ===
            // The course-brain snapshot frequently records folder browser
            // URLs ("/files/folder/...") instead of individual files. Hit
            // Canvas's REST API directly to get the real file objects and
            // folder hierarchy.
            var plannedAPIPDFCount = 0
            let inferredHost = course.metadata.platformDomain?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? course.resources.compactMap { $0.url?.host }.first
                ?? course.modules.flatMap(\.items).compactMap { $0.url?.host }.first
            if let rawHost = inferredHost,
               let host = CanvasFileURLResolver.normalizedHost(rawHost) {
                let api = await CanvasFilesAPI.fetchAll(host: host, courseId: course.courseId, cookies: cookies)
                let folderById: [Int: CanvasAPIFolder] = Dictionary(api.folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

                for file in api.files {
                    if file.isUnavailable { continue }
                    guard let urlString = file.bestDownloadURLString(host: host, courseId: course.courseId),
                          let url = URL(string: urlString) else { continue }

                    let title = file.resolvedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let isPDF =
                        (file.contentType ?? "").lowercased().contains("pdf")
                        || (file.mimeClass ?? "").lowercased() == "pdf"
                        || title.lowercased().hasSuffix(".pdf")
                        || (file.filename ?? "").lowercased().hasSuffix(".pdf")
                    guard isPDF else { continue }

                    let key = canonicalKey(url)
                    guard seenURLs.insert(key).inserted else { continue }

                    var pathComponents: [String] = ["Files"]
                    if let folderId = file.folderId, let folder = folderById[folderId] {
                        pathComponents.append(contentsOf: parseAPIFolderPath(folder.fullName))
                    }

                    plan.append(PlannedDownload(
                        courseId: course.courseId,
                        courseFolderName: courseFolderName,
                        leafFolderPathComponents: pathComponents,
                        title: title.isEmpty ? (file.filename ?? "Untitled") : title,
                        sourceURL: url
                    ))
                    plannedAPIPDFCount += 1
                }
            }

            if plannedAPIPDFCount > 0 {
                print("[CanvasImport] course=\(course.courseId) planned \(plannedAPIPDFCount) PDF(s) from Canvas API; skipping snapshot fallback")
                continue
            }

            for resource in course.resources where resource.kind == .assignment {
                guard let rawURL = resource.url,
                      let sourceURL = CanvasFileURLResolver.pdfSourceURL(
                        from: rawURL,
                        title: resource.title,
                        contentType: resource.contentType
                      )
                else { continue }
                let key = canonicalKey(sourceURL)
                guard seenURLs.insert(key).inserted else { continue }

                let assignmentName: String = {
                    if let assignmentId = resource.assignmentId,
                       let mapped = assignmentNameById[assignmentId],
                       !mapped.isEmpty {
                        return mapped
                    }
                    let fallback = resource.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    return fallback.isEmpty ? "Assignment" : fallback
                }()

                plan.append(PlannedDownload(
                    courseId: course.courseId,
                    courseFolderName: courseFolderName,
                    leafFolderPathComponents: ["Assignments", sanitizeSegment(assignmentName)],
                    title: resource.title,
                    sourceURL: sourceURL
                ))
            }

            for resource in course.resources where resource.kind == .file {
                guard let rawURL = resource.url,
                      let sourceURL = CanvasFileURLResolver.pdfSourceURL(
                        from: rawURL,
                        title: resource.title,
                        contentType: resource.contentType
                      )
                else { continue }
                let key = canonicalKey(sourceURL)
                guard seenURLs.insert(key).inserted else { continue }

                var pathComponents: [String] = ["Files"]
                pathComponents.append(contentsOf: parseFolderPath(resource.folderPath))

                plan.append(PlannedDownload(
                    courseId: course.courseId,
                    courseFolderName: courseFolderName,
                    leafFolderPathComponents: pathComponents,
                    title: resource.title,
                    sourceURL: sourceURL
                ))
            }

            for module in course.modules {
                for item in module.items where item.type.lowercased().contains("file") {
                    guard let rawURL = item.url,
                          let sourceURL = CanvasFileURLResolver.pdfSourceURL(
                            from: rawURL,
                            title: item.title,
                            contentType: nil
                          )
                    else { continue }
                    let key = canonicalKey(sourceURL)
                    guard seenURLs.insert(key).inserted else { continue }

                    let moduleSegment = sanitizeSegment(module.name)
                    plan.append(PlannedDownload(
                        courseId: course.courseId,
                        courseFolderName: courseFolderName,
                        leafFolderPathComponents: ["Files", moduleSegment],
                        title: item.title,
                        sourceURL: sourceURL
                    ))
                }
            }
        }

        return plan
    }

    // MARK: - Execution

    private func run(dependencies: Dependencies) async {
        var imported = 0
        var skipped = 0
        var failed = 0
        var folderIdCache: [String: UUID] = [:]

        guard let canvascopeId = dependencies.canvasFolderId() else {
            phase = .failed(message: "The Canvas import folder isn't set up yet.")
            return
        }

        print("[CanvasImport] ▶︎ starting batch — \(activePlan.count) item(s)")

        // Reuse a single downloader across the batch. Each download was
        // previously creating its own WKWebView (and a new WebContent
        // process), which iOS started reaping aggressively after a few
        // dozen items.
        let downloader = CourseBrainPDFDownloader()
        self.activeDownloader = downloader

        var index = 0
        while index < activePlan.count {
            if cancelRequested { break }

            let item = activePlan[index]

            progress = Progress(
                completed: index,
                total: activePlan.count,
                currentTitle: item.title,
                currentCourseName: item.courseFolderName
            )

            if dependencies.documentIdForSourceURL(item.sourceURL) != nil {
                print("[CanvasImport] [\(index + 1)/\(activePlan.count)] skip already-imported \"\(item.title)\"")
                skipped += 1
                progress = Progress(
                    completed: index + 1,
                    total: activePlan.count,
                    currentTitle: item.title,
                    currentCourseName: item.courseFolderName
                )
                index += 1
                continue
            }

            print("[CanvasImport] [\(index + 1)/\(activePlan.count)] downloading \"\(item.title)\"")
            print("[CanvasImport]    URL: \(item.sourceURL.absoluteString)")

            let downloadResult: Result<URL, Error> = await withCheckedContinuation { continuation in
                downloader.download(from: item.sourceURL, title: item.title) { result in
                    continuation.resume(returning: result)
                }
            }

            switch downloadResult {
            case .success(let tempURL):
                let currentParent = folderId(
                    for: item,
                    canvasFolderId: canvascopeId,
                    cache: &folderIdCache,
                    dependencies: dependencies
                )
                if dependencies.importDownloadedPDF(tempURL, item.title, item.sourceURL, currentParent, Date()) != nil {
                    print("[CanvasImport]    ✓ imported")
                    imported += 1
                } else {
                    print("[CanvasImport]    ✗ saved download but failed to register LocalDocument")
                    failed += 1
                }
            case .failure(let error):
                print("[CanvasImport]    ✗ failed → \(error.localizedDescription)")
                failed += 1
            }

            progress = Progress(
                completed: index + 1,
                total: activePlan.count,
                currentTitle: item.title,
                currentCourseName: item.courseFolderName
            )

            index += 1
        }

        downloader.teardown()
        self.activeDownloader = nil
        print("[CanvasImport] ⤓ batch complete — imported=\(imported) skipped=\(skipped) failed=\(failed)")

        let finalProgress = Progress(
            completed: cancelRequested ? progress.completed : activePlan.count,
            total: activePlan.count,
            currentTitle: nil,
            currentCourseName: nil
        )
        progress = finalProgress

        phase = cancelRequested
            ? .cancelled(imported: imported, skipped: skipped, failed: failed)
            : .finished(imported: imported, skipped: skipped, failed: failed)
    }

    private func folderId(
        for item: PlannedDownload,
        canvasFolderId: UUID,
        cache folderIdCache: inout [String: UUID],
        dependencies: Dependencies
    ) -> UUID {
        let courseFolderKey = "course:\(item.courseId)"
        let courseFolderId: UUID
        if let cached = folderIdCache[courseFolderKey] {
            courseFolderId = cached
        } else {
            courseFolderId = dependencies.findOrCreateFolder(item.courseFolderName, canvasFolderId)
            folderIdCache[courseFolderKey] = courseFolderId
        }

        var currentParent = courseFolderId
        var pathSoFar = courseFolderKey
        for segment in item.leafFolderPathComponents {
            let resolved = segment.isEmpty ? "Untitled" : segment
            pathSoFar += "/" + resolved.lowercased()
            if let cached = folderIdCache[pathSoFar] {
                currentParent = cached
            } else {
                let newId = dependencies.findOrCreateFolder(resolved, currentParent)
                folderIdCache[pathSoFar] = newId
                currentParent = newId
            }
        }
        return currentParent
    }

    // MARK: - Helpers

    private static let nonPDFExtensions: [String] = [
        ".docx", ".doc", ".xlsx", ".xls", ".pptx", ".ppt", ".pages", ".numbers", ".key",
        ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".heic", ".webp", ".svg",
        ".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm",
        ".mp3", ".wav", ".m4a", ".aac", ".flac",
        ".zip", ".rar", ".7z", ".tar", ".gz", ".tgz",
        ".html", ".htm", ".txt", ".csv", ".rtf",
        ".py", ".ipynb", ".java", ".c", ".cpp", ".h", ".swift", ".js", ".ts",
        ".json", ".xml", ".yaml", ".yml"
    ]

    private static func isLikelyPDF(url: URL, title: String?, contentType: String?) -> Bool {
        let path = url.path.lowercased()
        let lowerTitle = (title ?? "").lowercased()
        let lowerCT = (contentType ?? "").lowercased()

        // Folder browser URLs (`/files/folder/...`) are HTML, not files.
        if path.contains("/files/folder") { return false }

        // Strong positives — definitely a PDF.
        if path.hasSuffix(".pdf") || lowerTitle.hasSuffix(".pdf") { return true }
        if lowerCT.contains("pdf") { return true }

        // Strong negatives — definitely not a PDF.
        for ext in nonPDFExtensions {
            if path.hasSuffix(ext) || lowerTitle.hasSuffix(ext) { return false }
        }
        if lowerCT.hasPrefix("image/")
            || lowerCT.hasPrefix("video/")
            || lowerCT.hasPrefix("audio/")
            || lowerCT.hasPrefix("text/html")
            || lowerCT.contains("zip")
            || lowerCT.contains("word")
            || lowerCT.contains("excel")
            || lowerCT.contains("powerpoint")
            || lowerCT.contains("presentation")
            || lowerCT.contains("spreadsheet")
            || lowerCT.contains("sheet") {
            return false
        }

        // Canvas file URLs only count when they have a numeric file id —
        // /files/12345, /files/12345/download. Anything else (folder
        // browsers, /file_contents, /quiz_files) is HTML.
        if path.range(of: #"/files/\d+"#, options: .regularExpression) != nil {
            return true
        }
        if (url.query?.lowercased() ?? "").contains("download_frd") { return true }

        return false
    }

    /// Canvas API returns folder paths like "course files/Module 1/Subfolder".
    /// Drop the leading "course files" segment and normalise the rest.
    private static func parseAPIFolderPath(_ fullName: String) -> [String] {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let segments = trimmed.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let first = segments.first?.lowercased(),
           first == "course files" || first == "courses files" {
            return Array(segments.dropFirst()).map(sanitizeSegment)
        }
        return segments.map(sanitizeSegment)
    }

    private static func parseFolderPath(_ raw: String?) -> [String] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return raw
            .split(whereSeparator: { $0 == ">" || $0 == "/" })
            .map { sanitizeSegment(String($0)) }
            .filter { !$0.isEmpty && $0.lowercased() != "course files" }
    }

    private static func sanitizeSegment(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let scrubbed = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return scrubbed.isEmpty ? "Untitled" : scrubbed
    }

    private static func canonicalKey(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = nil
        components?.fragment = nil
        if let path = components?.percentEncodedPath {
            components?.percentEncodedPath = path.lowercased()
        }
        if let host = components?.percentEncodedHost {
            components?.percentEncodedHost = host.lowercased()
        }
        return components?.url?.absoluteString.lowercased() ?? url.absoluteString.lowercased()
    }
}
