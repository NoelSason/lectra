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

    var bestDownloadURLString: String? {
        for candidate in [url, htmlURL, previewURL] {
            if let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
               !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    var isUnavailable: Bool {
        lockedForUser == true || locked == true || hidden == true
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case filename
        case url
        case htmlURL = "html_url"
        case previewURL = "preview_url"
        case contentType = "content-type"
        case mimeClass = "mime_class"
        case folderId = "folder_id"
        case size
        case lockedForUser = "locked_for_user"
        case locked
        case hidden
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
        mimeClass = try container.decodeIfPresent(String.self, forKey: .mimeClass)
        folderId = try container.decodeFlexibleIntIfPresent(forKey: .folderId)
        size = try container.decodeFlexibleIntIfPresent(forKey: .size)
        lockedForUser = try container.decodeFlexibleBoolIfPresent(forKey: .lockedForUser)
        locked = try container.decodeFlexibleBoolIfPresent(forKey: .locked)
        hidden = try container.decodeFlexibleBoolIfPresent(forKey: .hidden)
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
        let sessionResult = await fetchAllViaURLSession(host: host, courseId: courseId, cookies: cookies)
        if !sessionResult.files.isEmpty {
            print("[CanvasAPI] course=\(courseId) host=\(host) source=urlsession folders=\(sessionResult.folders.count) files=\(sessionResult.files.count)")
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
        let files: [CanvasAPIFile] = await paginated(
            session: session,
            startURL: URL(string: "https://\(host)/api/v1/courses/\(courseId)/files?per_page=100")
        )

        return Result(folders: folders, files: files, source: .urlSession)
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

                for (const module of modules) {
                    for (const item of (module.items || [])) {
                        if (String(item.type || '').toLowerCase() !== 'file') continue;
                        if (item.content_id !== undefined && item.content_id !== null && seen.has(String(item.content_id))) continue;
                        if (!item.url) continue;

                        const detailURL = new URL(item.url, window.location.origin);
                        const detailPath = detailURL.pathname + detailURL.search;
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
                            if (!file.html_url && item.html_url) file.html_url = item.html_url;
                            if (!file.url && item.url) file.url = item.url;
                            files.push(file);
                            if (file.id !== undefined && file.id !== null) seen.add(String(file.id));
                        } catch (error) {
                            errors.push('Module file JSON parse failed from ' + response.url);
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
