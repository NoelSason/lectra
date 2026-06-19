import Foundation
import UIKit
import WebKit

struct CanvasAPIFile: Decodable {
    let id: Int
    let displayName: String?
    let filename: String?
    let url: String?
    let htmlURL: String?
    let previewURL: String?
    let contentType: String?
    let mimeClass: String?
    let folderId: Int?
    let size: Int?
    let lockedForUser: Bool?
    let locked: Bool?
    let hidden: Bool?
    let hiddenForUser: Bool?

    var resolvedDisplayName: String {
        let candidates = [displayName, filename]
        for candidate in candidates {
            if let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
               !trimmed.isEmpty {
                return trimmed
            }
        }
        return "Canvas File \(id)"
    }

    func bestDownloadURLString(host: String, courseId: Int) -> String? {
        CanvasFileURLResolver.resolvedDownloadURL(
            candidateStrings: [url, htmlURL, previewURL],
            host: host,
            courseId: courseId,
            fileId: id
        )?.absoluteString
    }

    var isUnavailable: Bool {
        lockedForUser == true || locked == true || hidden == true || hiddenForUser == true
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case filename
        case url
        case htmlURL = "html_url"
        case previewURL = "preview_url"
        case contentType = "content-type"
        case contentTypeUnderscored = "content_type"
        case mimeClass = "mime_class"
        case folderId = "folder_id"
        case size
        case lockedForUser = "locked_for_user"
        case locked
        case hidden
        case hiddenForUser = "hidden_for_user"
    }

    init(
        id: Int,
        displayName: String? = nil,
        filename: String? = nil,
        url: String? = nil,
        htmlURL: String? = nil,
        previewURL: String? = nil,
        contentType: String? = nil,
        mimeClass: String? = nil,
        folderId: Int? = nil,
        size: Int? = nil,
        lockedForUser: Bool? = nil,
        locked: Bool? = nil,
        hidden: Bool? = nil,
        hiddenForUser: Bool? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.filename = filename
        self.url = url
        self.htmlURL = htmlURL
        self.previewURL = previewURL
        self.contentType = contentType
        self.mimeClass = mimeClass
        self.folderId = folderId
        self.size = size
        self.lockedForUser = lockedForUser
        self.locked = locked
        self.hidden = hidden
        self.hiddenForUser = hiddenForUser
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleInt(forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        htmlURL = try container.decodeIfPresent(String.self, forKey: .htmlURL)
        previewURL = try container.decodeIfPresent(String.self, forKey: .previewURL)
        contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
            ?? container.decodeIfPresent(String.self, forKey: .contentTypeUnderscored)
        mimeClass = try container.decodeIfPresent(String.self, forKey: .mimeClass)
        folderId = try container.decodeFlexibleIntIfPresent(forKey: .folderId)
        size = try container.decodeFlexibleIntIfPresent(forKey: .size)
        lockedForUser = try container.decodeFlexibleBoolIfPresent(forKey: .lockedForUser)
        locked = try container.decodeFlexibleBoolIfPresent(forKey: .locked)
        hidden = try container.decodeFlexibleBoolIfPresent(forKey: .hidden)
        hiddenForUser = try container.decodeFlexibleBoolIfPresent(forKey: .hiddenForUser)
    }
}

enum CanvasFileURLResolver {
    static func normalizedHost(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let host = url.host,
           !host.isEmpty {
            return host.lowercased()
        }

        if let url = URL(string: "https://\(trimmed)"),
           let host = url.host,
           !host.isEmpty {
            return host.lowercased()
        }

        return nil
    }

    static func resolvedDownloadURL(
        candidateStrings: [String?],
        host rawHost: String,
        courseId: Int,
        fileId: Int
    ) -> URL? {
        guard let host = normalizedHost(rawHost),
              let synthesized = canvasFileDownloadURL(host: host, courseId: courseId, fileId: fileId) else {
            return nil
        }

        let orderedCandidates = [candidateStrings.first ?? nil, synthesized.absoluteString]
            + Array(candidateStrings.dropFirst())

        for candidate in orderedCandidates {
            guard let url = absoluteURL(from: candidate, host: host) else { continue }

            if let forced = forcedDownloadURL(from: url) {
                return forced
            }

            if isCanvasFilesBrowserURL(url) || isCanvasAPIFileDetailURL(url) {
                continue
            }

            return url
        }

        return synthesized
    }

    static func pdfSourceURL(from url: URL, title: String?, contentType: String?) -> URL? {
        guard hasPDFSignal(url: url, title: title, contentType: contentType) else {
            return nil
        }

        if let forced = forcedDownloadURL(from: url) {
            return forced
        }

        if isCanvasFilesBrowserURL(url) || isCanvasAPIFileDetailURL(url) {
            return nil
        }

        return url
    }

    static func forcedDownloadURL(from url: URL) -> URL? {
        if let previewURL = previewDownloadURL(from: url) {
            return previewURL
        }

        guard !isCanvasFilesBrowserURL(url),
              let host = url.host,
              let courseId = courseId(from: url),
              let fileId = fileId(from: url) else {
            return nil
        }

        return canvasFileDownloadURL(host: host, courseId: courseId, fileId: fileId)
    }

    static func isCanvasFilesBrowserURL(_ url: URL) -> Bool {
        let lowerPath = url.path.lowercased()
        if lowerPath.contains("/files/folder") {
            return true
        }

        let components = pathComponents(from: url)
        return components.last?.lowercased() == "files"
    }

    private static func hasPDFSignal(url: URL, title: String?, contentType: String?) -> Bool {
        let lowerPath = url.path.lowercased()
        let lowerTitle = (title ?? "").lowercased()
        let lowerCT = (contentType ?? "").lowercased()

        if lowerCT.contains("pdf") { return true }
        if lowerPath.hasSuffix(".pdf") || lowerTitle.hasSuffix(".pdf") { return true }

        let nonPDFExtensions = [
            ".docx", ".doc", ".xlsx", ".xls", ".pptx", ".ppt", ".pages", ".numbers", ".key",
            ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".heic", ".webp", ".svg",
            ".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm",
            ".mp3", ".wav", ".m4a", ".aac", ".flac",
            ".zip", ".rar", ".7z", ".tar", ".gz", ".tgz",
            ".html", ".htm", ".txt", ".csv", ".rtf",
            ".py", ".ipynb", ".java", ".c", ".cpp", ".h", ".swift", ".js", ".ts",
            ".json", ".xml", ".yaml", ".yml"
        ]
        for ext in nonPDFExtensions {
            if lowerPath.hasSuffix(ext) || lowerTitle.hasSuffix(ext) { return false }
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

        if fileId(from: url) != nil { return true }
        if previewFileId(from: url) != nil { return true }
        if (url.query?.lowercased() ?? "").contains("download_frd") { return true }

        return false
    }

    private static func previewDownloadURL(from url: URL) -> URL? {
        guard let host = url.host,
              let courseId = courseId(from: url),
              pathComponents(from: url).contains(where: { $0.lowercased() == "files" }),
              let fileId = previewFileId(from: url) else {
            return nil
        }

        return canvasFileDownloadURL(host: host, courseId: courseId, fileId: fileId)
    }

    private static func canvasFileDownloadURL(host: String, courseId: Int, fileId: Int) -> URL? {
        guard let normalizedHost = normalizedHost(host) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = normalizedHost
        components.path = "/courses/\(courseId)/files/\(fileId)/download"
        components.queryItems = [URLQueryItem(name: "download_frd", value: "1")]
        return components.url
    }

    private static func absoluteURL(from raw: String?, host: String) -> URL? {
        guard let raw,
              let normalizedHost = normalizedHost(host) else {
            return nil
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        guard let base = URL(string: "https://\(normalizedHost)") else {
            return nil
        }
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }

    private static func isCanvasAPIFileDetailURL(_ url: URL) -> Bool {
        let components = pathComponents(from: url).map { $0.lowercased() }
        guard components.contains("api"),
              courseId(from: url) != nil,
              fileId(from: url) != nil else {
            return false
        }
        return true
    }

    private static func courseId(from url: URL) -> Int? {
        let components = pathComponents(from: url).map { $0.lowercased() }
        guard let index = components.firstIndex(of: "courses"),
              components.count > index + 1 else {
            return nil
        }
        return Int(components[index + 1])
    }

    private static func fileId(from url: URL) -> Int? {
        let components = pathComponents(from: url).map { $0.lowercased() }
        guard let index = components.firstIndex(of: "files"),
              components.count > index + 1 else {
            return nil
        }
        return Int(components[index + 1])
    }

    private static func previewFileId(from url: URL) -> Int? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name.lowercased() == "preview" }
            .flatMap { $0.value }
            .flatMap(Int.init)
    }

    private static func pathComponents(from url: URL) -> [String] {
        url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
    }
}

struct CanvasAPIFolder: Decodable {
    let id: Int
    let name: String
    let fullName: String
    let parentFolderId: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case parentFolderId = "parent_folder_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleInt(forKey: .id)
        name = (try container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        fullName = (try container.decodeIfPresent(String.self, forKey: .fullName)) ?? name
        parentFolderId = try container.decodeFlexibleIntIfPresent(forKey: .parentFolderId)
    }
}

private struct CanvasAPIModule: Decodable {
    let items: [CanvasAPIModuleItem]

    enum CodingKeys: String, CodingKey {
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = (try container.decodeIfPresent([CanvasAPIModuleItem].self, forKey: .items)) ?? []
    }
}

private struct CanvasAPIModuleItem: Decodable {
    let contentId: Int?
    let title: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case contentId = "content_id"
        case contentIdCamel = "contentId"
        case title
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contentId = try container.decodeFlexibleIntIfPresent(forKey: .contentId)
            ?? container.decodeFlexibleIntIfPresent(forKey: .contentIdCamel)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        type = try container.decodeIfPresent(String.self, forKey: .type)
    }
}

enum CanvasFilesAPI {
    struct Result {
        let folders: [CanvasAPIFolder]
        let files: [CanvasAPIFile]
        let source: Source

        static let empty = Result(folders: [], files: [], source: .none)
    }

    enum Source: Equatable {
        case none
        case urlSession
        case webView
    }

    static func fetchAll(host: String, courseId: Int, cookies: [HTTPCookie]) async -> Result {
        guard let host = CanvasFileURLResolver.normalizedHost(host) else {
            print("[CanvasAPI] course=\(courseId) invalid host")
            return .empty
        }

        let sessionResult = await fetchAllViaURLSession(host: host, courseId: courseId, cookies: cookies)
        if !sessionResult.files.isEmpty {
            print("[CanvasAPI] course=\(courseId) host=\(host) source=urlsession folders=\(sessionResult.folders.count) files=\(sessionResult.files.count)")
            return sessionResult
        }

        if cookies.isEmpty {
            print("[CanvasAPI] course=\(courseId) host=\(host) source=urlsession files=0 folders=\(sessionResult.folders.count); skipping webview API discovery because no Canvas cookies are stored")
            return sessionResult
        }

        print("[CanvasAPI] course=\(courseId) host=\(host) source=urlsession files=0 folders=\(sessionResult.folders.count); trying webview session")
        let webResult = await CanvasFilesWebFetcher(host: host, courseId: courseId).fetch()
        print("[CanvasAPI] course=\(courseId) host=\(host) source=webview folders=\(webResult.folders.count) files=\(webResult.files.count)")

        if !webResult.files.isEmpty || !webResult.folders.isEmpty {
            return webResult
        }
        return sessionResult
    }

    private static func fetchAllViaURLSession(host: String, courseId: Int, cookies: [HTTPCookie]) async -> Result {
        let storage = HTTPCookieStorage()
        for cookie in cookies {
            storage.setCookie(cookie)
        }

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = storage
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60

        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        let folders: [CanvasAPIFolder] = await paginated(
            session: session,
            startURL: URL(string: "https://\(host)/api/v1/courses/\(courseId)/folders?per_page=100")
        )
        let courseFiles: [CanvasAPIFile] = await paginated(
            session: session,
            startURL: URL(string: "https://\(host)/api/v1/courses/\(courseId)/files?per_page=100")
        )
        let modules: [CanvasAPIModule] = await paginated(
            session: session,
            startURL: URL(string: "https://\(host)/api/v1/courses/\(courseId)/modules?include[]=items&per_page=100")
        )
        let moduleFiles = await fetchModuleFileDetails(
            session: session,
            host: host,
            courseId: courseId,
            modules: modules,
            existingFiles: courseFiles
        )
        let files = mergedFiles(courseFiles + moduleFiles)

        return Result(folders: folders, files: files, source: .urlSession)
    }

    private static func fetchModuleFileDetails(
        session: URLSession,
        host: String,
        courseId: Int,
        modules: [CanvasAPIModule],
        existingFiles: [CanvasAPIFile]
    ) async -> [CanvasAPIFile] {
        guard !modules.isEmpty else { return [] }

        let decoder = JSONDecoder()
        var files: [CanvasAPIFile] = []
        var seenIds = Set(existingFiles.map(\.id))

        for module in modules {
            for item in module.items {
                guard item.type?.lowercased() == "file",
                      let contentId = item.contentId,
                      !seenIds.contains(contentId) else {
                    continue
                }

                guard let detailURL = URL(string: "https://\(host)/api/v1/courses/\(courseId)/files/\(contentId)") else {
                    continue
                }

                do {
                    var request = URLRequest(url: detailURL)
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse else { continue }

                    if http.statusCode == 401 || http.statusCode == 403 {
                        print("[CanvasAPI] module file auth-blocked status=\(http.statusCode) url=\(detailURL.absoluteString)")
                        if let synthesized = synthesizedModuleFile(item: item, host: host, courseId: courseId) {
                            files.append(synthesized)
                            seenIds.insert(synthesized.id)
                        }
                        continue
                    }
                    if http.statusCode >= 400 {
                        print("[CanvasAPI] module file http-error status=\(http.statusCode) url=\(detailURL.absoluteString)")
                        if let synthesized = synthesizedModuleFile(item: item, host: host, courseId: courseId) {
                            files.append(synthesized)
                            seenIds.insert(synthesized.id)
                        }
                        continue
                    }

                    let file = try decoder.decode(CanvasAPIFile.self, from: data)
                    files.append(file)
                    seenIds.insert(file.id)
                } catch {
                    if let synthesized = synthesizedModuleFile(item: item, host: host, courseId: courseId) {
                        files.append(synthesized)
                        seenIds.insert(synthesized.id)
                    } else {
                        print("[CanvasAPI] module file decode/network error: \(error.localizedDescription)")
                    }
                }
            }
        }

        return files
    }

    private static func synthesizedModuleFile(item: CanvasAPIModuleItem, host: String, courseId: Int) -> CanvasAPIFile? {
        guard let contentId = item.contentId,
              let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty,
              title.lowercased().hasSuffix(".pdf") else {
            return nil
        }

        return CanvasAPIFile(
            id: contentId,
            displayName: title,
            filename: title,
            htmlURL: "https://\(host)/courses/\(courseId)/files/\(contentId)",
            contentType: "application/pdf",
            mimeClass: "pdf"
        )
    }

    private static func mergedFiles(_ files: [CanvasAPIFile]) -> [CanvasAPIFile] {
        var seenIds: Set<Int> = []
        var merged: [CanvasAPIFile] = []
        for file in files {
            guard seenIds.insert(file.id).inserted else { continue }
            merged.append(file)
        }
        return merged
    }

    private static func paginated<Element: Decodable>(session: URLSession, startURL: URL?) async -> [Element] {
        var nextURL = startURL
        var results: [Element] = []
        let decoder = JSONDecoder()

        for _ in 0..<30 {
            guard let url = nextURL else { break }
            do {
                var request = URLRequest(url: url)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { break }
                if http.statusCode == 401 || http.statusCode == 403 {
                    print("[CanvasAPI] paginated auth-blocked status=\(http.statusCode) url=\(url.absoluteString)")
                    break
                }
                if http.statusCode >= 400 {
                    print("[CanvasAPI] paginated http-error status=\(http.statusCode) url=\(url.absoluteString)")
                    break
                }
                if let finalHost = http.url?.host?.lowercased(),
                   let originalHost = url.host?.lowercased(),
                   finalHost != originalHost {
                    print("[CanvasAPI] paginated redirected off-canvas host=\(finalHost) url=\(url.absoluteString)")
                    break
                }

                let pageItems = try decoder.decode([Element].self, from: data)
                results.append(contentsOf: pageItems)
                nextURL = parseNextLink(from: http.value(forHTTPHeaderField: "Link"))
            } catch {
                print("[CanvasAPI] paginated decode/network error: \(error.localizedDescription)")
                break
            }
        }

        return results
    }

    private static func parseNextLink(from header: String?) -> URL? {
        guard let header, !header.isEmpty else { return nil }
        for raw in header.split(separator: ",") {
            let part = raw.trimmingCharacters(in: .whitespaces)
            guard part.contains("rel=\"next\"") else { continue }
            if let openBracket = part.firstIndex(of: "<"),
               let closeBracket = part.firstIndex(of: ">") {
                let urlString = String(part[part.index(after: openBracket)..<closeBracket])
                return URL(string: urlString)
            }
        }
        return nil
    }
}

@MainActor
private final class CanvasFilesWebFetcher: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private let messageHandlerName = "canvasFilesAPI"
    private let host: String
    private let courseId: Int
    private var webView: WKWebView?
    private var userContentController: WKUserContentController?
    private var continuation: CheckedContinuation<CanvasFilesAPI.Result, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var didStartExtraction = false
    private var isInteractive = false
    private weak var interactiveController: UIViewController?

    init(host: String, courseId: Int) {
        self.host = host.lowercased()
        self.courseId = courseId
    }

    func fetch() async -> CanvasFilesAPI.Result {
        await CanvasCookieStore.restoreIntoDefaultWebViewStore()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let userContentController = WKUserContentController()
        userContentController.add(self, name: messageHandlerName)
        config.userContentController = userContentController
        self.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        self.webView = webView

        guard let courseURL = URL(string: "https://\(host)/courses/\(courseId)") else {
            return .empty
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.scheduleTimeout()
            webView.load(URLRequest(url: courseURL))
        }
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard let self else { return }
            await MainActor.run {
                guard self.continuation != nil else { return }
                print("[CanvasAPI] webview timeout course=\(self.courseId)")
                self.finish(.empty)
            }
        }
    }

    private func finish(_ result: CanvasFilesAPI.Result) {
        timeoutTask?.cancel()
        timeoutTask = nil

        let continuation = continuation
        self.continuation = nil

        webView?.stopLoading()
        webView?.navigationDelegate = nil
        userContentController?.removeScriptMessageHandler(forName: messageHandlerName)
        userContentController = nil
        dismissInteractiveWebView()
        webView = nil

        continuation?.resume(returning: result)
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor in
            print("[CanvasAPI] webview didFail: \(error.localizedDescription)")
            self.finish(.empty)
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor in
            print("[CanvasAPI] webview didFailProvisional: \(error.localizedDescription)")
            self.finish(.empty)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard self.continuation != nil, !self.didStartExtraction else { return }

            let currentURLString = webView.url?.absoluteString ?? "nil"
            let currentHost = webView.url?.host?.lowercased()
            print("[CanvasAPI] webview didFinish url=\(currentURLString)")

            await self.persistCurrentCookies(for: webView.url)

            guard self.isOnCanvasHost(currentHost) else {
                self.showInteractiveWebViewIfPossible()
                return
            }

            self.didStartExtraction = true
            self.startAPIExtraction(in: webView)
        }
    }

    private func startAPIExtraction(in webView: WKWebView) {
        let script = """
        (function() {
            const post = (payload) => {
                window.webkit.messageHandlers.\(messageHandlerName).postMessage(JSON.stringify(payload));
            };

            function nextFromLink(header) {
                if (!header) return null;
                const parts = header.split(',');
                for (const part of parts) {
                    if (!part.includes('rel="next"')) continue;
                    const match = part.match(/<([^>]+)>/);
                    if (!match) continue;
                    const url = new URL(match[1], window.location.origin);
                    return url.pathname + url.search;
                }
                return null;
            }

            async function loadAll(path) {
                const items = [];
                const errors = [];
                let next = path;
                for (let i = 0; i < 30 && next; i++) {
                    const response = await fetch(next, {
                        credentials: 'same-origin',
                        headers: { 'Accept': 'application/json' }
                    });
                    if (!response.ok) {
                        errors.push(response.status + ' ' + response.url);
                        break;
                    }
                    const text = await response.text();
                    try {
                        const page = JSON.parse(text);
                        if (Array.isArray(page)) {
                            items.push(...page);
                        } else {
                            errors.push('Non-array response from ' + response.url);
                            break;
                        }
                    } catch (error) {
                        errors.push('JSON parse failed from ' + response.url + ': ' + text.slice(0, 160));
                        break;
                    }
                    next = nextFromLink(response.headers.get('Link'));
                }
                return { items, errors };
            }

            async function loadModuleFileDetails(modules, existingFiles) {
                const files = [];
                const errors = [];
                const seen = new Set();

                for (const file of existingFiles) {
                    if (file && file.id !== undefined && file.id !== null) {
                        seen.add(String(file.id));
                    }
                    if (file && file.url) {
                        seen.add(String(file.url));
                    }
                    if (file && file.html_url) {
                        seen.add(String(file.html_url));
                    }
                }

                function numericID(value) {
                    if (value === undefined || value === null) return null;
                    const parsed = Number(String(value));
                    return Number.isFinite(parsed) ? parsed : null;
                }

                function addUnique(paths, path) {
                    if (!path || paths.includes(path)) return;
                    paths.push(path);
                }

                function apiDetailPaths(item) {
                    const paths = [];
                    const contentID = numericID(item.content_id);
                    if (contentID !== null) {
                        addUnique(paths, '/api/v1/courses/\(courseId)/files/' + encodeURIComponent(String(contentID)));
                    }

                    if (item.url) {
                        const itemURL = new URL(item.url, window.location.origin);
                        const fileMatch = itemURL.pathname.match(/\\/files\\/(\\d+)/);
                        if (fileMatch && fileMatch[1]) {
                            addUnique(paths, '/api/v1/courses/\(courseId)/files/' + encodeURIComponent(fileMatch[1]));
                        }
                        if (itemURL.pathname.includes('/api/v1/') && itemURL.pathname.includes('/files/')) {
                            addUnique(paths, itemURL.pathname + itemURL.search);
                        }
                    }

                    return paths;
                }

                function itemFilePageURL(item) {
                    if (!item.url) return null;
                    const itemURL = new URL(item.url, window.location.origin);
                    if (itemURL.pathname.includes('/files/folder')) return null;
                    if (!/\\/courses\\/\\d+\\/files\\/\\d+/.test(itemURL.pathname)) return null;
                    return itemURL.href;
                }

                function synthesizeModuleFile(item) {
                    const contentID = numericID(item.content_id);
                    if (contentID === null) return null;
                    const title = String(item.title || '').trim();
                    if (!title.toLowerCase().endsWith('.pdf')) return null;

                    return {
                        id: contentID,
                        display_name: title,
                        filename: title,
                        html_url: window.location.origin + '/courses/\(courseId)/files/' + encodeURIComponent(String(contentID)),
                        'content-type': 'application/pdf',
                        mime_class: 'pdf'
                    };
                }

                for (const module of modules) {
                    for (const item of (module.items || [])) {
                        if (String(item.type || '').toLowerCase() !== 'file') continue;
                        const contentID = numericID(item.content_id);
                        if (contentID !== null && seen.has(String(contentID))) continue;

                        let resolved = false;
                        for (const detailPath of apiDetailPaths(item)) {
                            if (seen.has(detailPath)) continue;
                            seen.add(detailPath);

                            const response = await fetch(detailPath, {
                                credentials: 'same-origin',
                                headers: { 'Accept': 'application/json' }
                            });
                            if (!response.ok) {
                                errors.push(response.status + ' ' + response.url);
                                continue;
                            }

                            try {
                                const file = await response.json();
                                if (!file.display_name && item.title) file.display_name = item.title;
                                if (!file.filename && item.title) file.filename = item.title;
                                if (!file.html_url && itemFilePageURL(item)) file.html_url = itemFilePageURL(item);
                                files.push(file);
                                if (file.id !== undefined && file.id !== null) seen.add(String(file.id));
                                resolved = true;
                                break;
                            } catch (error) {
                                errors.push('Module file JSON parse failed from ' + response.url);
                            }
                        }

                        if (!resolved) {
                            const synthesized = synthesizeModuleFile(item);
                            if (synthesized) {
                                files.push(synthesized);
                                seen.add(String(synthesized.id));
                            }
                        }
                    }
                }

                return { items: files, errors };
            }

            (async function() {
                try {
                    const folders = await loadAll('/api/v1/courses/\(courseId)/folders?per_page=100');
                    const files = await loadAll('/api/v1/courses/\(courseId)/files?per_page=100');
                    const modules = await loadAll('/api/v1/courses/\(courseId)/modules?include[]=items&per_page=100');
                    const moduleFiles = await loadModuleFileDetails(modules.items, files.items);
                    const mergedFiles = files.items.concat(moduleFiles.items);
                    post({
                        folders: folders.items,
                        files: mergedFiles,
                        errors: folders.errors.concat(files.errors).concat(modules.errors).concat(moduleFiles.errors)
                    });
                } catch (error) {
                    post({
                        folders: [],
                        files: [],
                        errors: [String(error && error.message ? error.message : error)]
                    });
                }
            })();

            return true;
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in
                guard let self, self.continuation != nil else { return }
                print("[CanvasAPI] webview API extraction failed to start: \(error.localizedDescription)")
                self.finish(.empty)
            }
        }
    }

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor in
            guard self.continuation != nil else { return }
            guard let raw = message.body as? String else {
                print("[CanvasAPI] webview API extraction returned unsupported message type")
                self.finish(.empty)
                return
            }

            do {
                let data = Data(raw.utf8)
                let envelope = try JSONDecoder().decode(CanvasAPIEnvelope.self, from: data)
                if !envelope.errors.isEmpty {
                    print("[CanvasAPI] webview API errors: \(envelope.errors.joined(separator: " | "))")
                }
                self.finish(CanvasFilesAPI.Result(
                    folders: envelope.folders,
                    files: envelope.files,
                    source: .webView
                ))
            } catch {
                print("[CanvasAPI] webview API extraction failed: \(error.localizedDescription)")
                self.finish(.empty)
            }
        }
    }

    private func showInteractiveWebViewIfPossible() {
        guard !isInteractive,
              let webView,
              let rootVC = getMainWindowRootViewController() else {
            return
        }

        isInteractive = true
        timeoutTask?.cancel()

        let vc = UIViewController()
        vc.view.backgroundColor = .systemBackground
        vc.title = "Campus Login"
        vc.navigationItem.rightBarButtonItem = UIBarButtonItem(primaryAction: UIAction(title: "Cancel") { [weak self] _ in
            self?.finish(.empty)
        })

        webView.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: vc.view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor)
        ])

        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet
        interactiveController = nav
        rootVC.present(nav, animated: true)
    }

    private func dismissInteractiveWebView() {
        guard isInteractive else { return }
        isInteractive = false
        let webView = webView
        interactiveController?.dismiss(animated: true) {
            webView?.removeFromSuperview()
        }
        interactiveController = nil
    }

    private func getMainWindowRootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        var topController = windowScene?.windows.first?.rootViewController
        while let presented = topController?.presentedViewController {
            topController = presented
        }
        return topController
    }

    private func isOnCanvasHost(_ currentHost: String?) -> Bool {
        guard let currentHost, !currentHost.isEmpty else { return false }
        if currentHost == host { return true }
        if currentHost.hasSuffix("." + host) { return true }
        return false
    }

    private func persistCurrentCookies(for url: URL?) async {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await cookieStore.allCookies()
        CanvasCookieStore.persist(cookies, primaryHost: url?.host ?? host)
    }

    private struct CanvasAPIEnvelope: Decodable {
        let folders: [CanvasAPIFolder]
        let files: [CanvasAPIFile]
        let errors: [String]
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleInt(forKey key: Key) throws -> Int {
        if let value = try decodeFlexibleIntIfPresent(forKey: key) {
            return value
        }
        throw DecodingError.valueNotFound(
            Int.self,
            DecodingError.Context(codingPath: codingPath + [key], debugDescription: "Expected Int or numeric String")
        )
    }

    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return Int(string)
        }
        return nil
    }

    func decodeFlexibleBoolIfPresent(forKey key: Key) throws -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let int = try? decodeIfPresent(Int.self, forKey: key) {
            return int != 0
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            switch string.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }
}
