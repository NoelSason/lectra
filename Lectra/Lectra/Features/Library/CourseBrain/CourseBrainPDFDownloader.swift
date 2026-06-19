import UIKit
import WebKit

/// Downloads a PDF from a Canvas URL using an in-app WKWebView.
///
/// WKWebView shares Safari's cookies via `WKWebsiteDataStore.default()`,
/// so the user's Canvas login session is automatically available.
/// The web view loads the URL in the background, intercepts the PDF
/// download via `WKDownloadDelegate`, and calls completion with the
/// local file URL.
///
/// If a login redirect (e.g., CalNet) is detected, the `presentationAnchor`
/// is used to display the WKWebView interactively so the user can sign in.
@MainActor
final class CourseBrainPDFDownloader: NSObject {

    private var webView: WKWebView?
    private var completion: ((Result<URL, Error>) -> Void)?
    private var suggestedTitle: String = ""
    private var activeDownloadTask: URLSessionTask?
    private var timeoutTask: Task<Void, Never>?
    private var downloadDestination: URL?
    private var isInteractive = false
    private weak var presentationAnchor: UIView?
    private var isDownloading = false
    private var targetHost: String?
    private var currentDownloadID = UUID()
    private var interceptedPDFDownloadID: UUID?
    private var skipDirectCanvasAttempt = false

    enum DownloaderError: LocalizedError {
        case timeout
        case cancelled
        case noData
        case authenticationRequired
        case invalidPDF

        var errorDescription: String? {
            switch self {
            case .timeout:   return "Download timed out"
            case .cancelled: return "Download was cancelled"
            case .noData:    return "No PDF data received"
            case .authenticationRequired: return "Authentication required. Please sign in via the Canvascope extension."
            case .invalidPDF: return "The downloaded file is not a valid PDF."
            }
        }
    }

    /// Start downloading a PDF from the given URL.
    /// - Parameters:
    ///   - url: The Canvas file URL.
    ///   - title: Suggested filename for the downloaded PDF.
    ///   - in: The view to present the interactive login webview over, if required.
    ///   - completion: Called on the main thread with the local file URL on success.
    func download(from url: URL, title: String, in view: UIView? = nil, completion: @escaping (Result<URL, Error>) -> Void) {
        let downloadID = UUID()
        currentDownloadID = downloadID
        self.completion = completion
        self.suggestedTitle = title
        self.presentationAnchor = view
        self.targetHost = url.host?.lowercased()
        self.isDownloading = false
        self.activeDownloadTask = nil

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.restoreCookies()
            guard self.isCurrentDownload(downloadID) else { return }

            // Fast path: try downloading directly via URLSession with the
            // cookies we already have. This avoids spinning up a WKWebView per
            // file (which on iOS spawns a new WebContent process every time
            // and gets killed under load), and it carries cookies through
            // SSO redirects properly using a dedicated HTTPCookieStorage.
            print("[Downloader] ▶︎ download start title=\"\(title)\" url=\(url.absoluteString)")
            if !self.skipDirectCanvasAttempt {
                let directOutcome = await self.attemptDirectDownload(originalURL: url)
                guard self.isCurrentDownload(downloadID) else { return }
                switch directOutcome {
                case .success(let localURL):
                    print("[Downloader] ✓ direct success → \(localURL.lastPathComponent)")
                    self.finish(.success(localURL), for: downloadID)
                    return
                case .failure(let error):
                    print("[Downloader] ✗ direct failure (giving up) → \(error.localizedDescription)")
                    self.finish(.failure(error), for: downloadID)
                    return
                case .needsAuth(let reason):
                    self.skipDirectCanvasAttempt = true
                    print("[Downloader] ↻ direct needsAuth (\(reason)) — falling back to WKWebView")
                }
            } else {
                print("[Downloader] ↻ direct skipped — using WKWebView session")
            }

            // Slow path: open a WKWebView so the user can sign in interactively.
            // Reused if this downloader is invoked multiple times.
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()

            if self.webView == nil {
                let wv = WKWebView(frame: .zero, configuration: config)
                wv.navigationDelegate = self
                self.webView = wv
            }

            let downloadURL = Self.canvasDownloadURL(from: url)
            self.webView?.load(URLRequest(url: downloadURL))

            // Timeout after 30 seconds if not interactive
            self.scheduleTimeout(for: downloadID)
        }
    }

    // MARK: - URLSession fast path

    private enum DirectOutcome {
        case success(URL)
        case needsAuth(String)
        case failure(Error)
    }

    private func attemptDirectDownload(originalURL: URL) async -> DirectOutcome {
        let downloadURL = Self.canvasDownloadURL(from: originalURL)

        // Pull cookies from both the persisted store (Canvascope extension)
        // and the live WKWebsiteDataStore (anything we picked up during a
        // previous interactive sign-in) and put them in a dedicated
        // HTTPCookieStorage so URLSession will reattach them on each redirect.
        let merged = await CanvasCookieStore.loadMergedSession()
        guard !merged.isEmpty else {
            return .needsAuth("no cookies stored")
        }

        let storage = HTTPCookieStorage()
        for stored in merged {
            storage.setCookie(stored.cookie)
        }

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = storage
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: downloadURL)
        request.setValue("application/pdf,application/octet-stream;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            print("[Downloader]   urlsession error → \(error.localizedDescription)")
            return .needsAuth("URLSession error: \(error.localizedDescription)")
        }

        guard let httpResp = response as? HTTPURLResponse else {
            return .failure(DownloaderError.noData)
        }

        let status = httpResp.statusCode
        let finalURL = httpResp.url
        let finalHost = finalURL?.host?.lowercased() ?? ""
        let contentType = (httpResp.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        let contentDisp = (httpResp.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased()

        print("[Downloader]   urlsession status=\(status) finalURL=\(finalURL?.absoluteString ?? "nil") contentType=\(contentType) contentDisp=\(contentDisp) bytes=\(data.count)")

        if status == 401 || status == 403 {
            return .needsAuth("HTTP \(status)")
        }
        let landedOnPDF =
            contentType.contains("pdf")
            || contentDisp.contains("attachment")
            || finalURL?.pathExtension.lowercased() == "pdf"
        if !finalHost.isEmpty, !isOnCanvasTargetHost(finalHost), !landedOnPDF {
            return .needsAuth("redirected to non-canvas host \(finalHost)")
        }
        if status >= 400 {
            return .failure(DownloaderError.noData)
        }

        // Did we land on an HTML page? That usually means Canvas redirected
        // us out of the file (Files tab disabled, file unpublished, login
        // required) — we can't extract a PDF from that.
        if contentType.contains("text/html") {
            // If the HTML body looks like a login form, treat as auth needed.
            if let bodyString = String(data: data.prefix(8192), encoding: .utf8)?.lowercased(),
               bodyString.contains("password") || bodyString.contains("/login") || bodyString.contains("/cas") {
                return .needsAuth("HTML login page")
            }
            return .failure(DownloaderError.invalidPDF)
        }

        // Validate magic bytes — Canvas occasionally serves a redirect HTML
        // page with a generic mime type, so this is the source of truth.
        guard isPDFSignatureValid(data) else {
            return .failure(DownloaderError.invalidPDF)
        }

        // Looks like a real PDF — keep cookies fresh for the next call.
        if let finalURL { CanvasCookieStore.persist(merged.map(\.cookie), primaryHost: finalURL.host) }
        _ = contentDisp

        guard let localURL = savePDFToTemp(data) else {
            return .failure(DownloaderError.invalidPDF)
        }
        return .success(localURL)
    }

    private func isCurrentDownload(_ downloadID: UUID) -> Bool {
        completion != nil && currentDownloadID == downloadID
    }

    private func scheduleTimeout(for downloadID: UUID, cancelInteractive: Bool = false) {
        timeoutTask?.cancel()
        if isInteractive && !cancelInteractive { return }

        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self,
                  self.isCurrentDownload(downloadID),
                  !self.isInteractive else { return }
            self.finish(.failure(DownloaderError.timeout), for: downloadID)
        }
    }

    func cancel() {
        let downloadID = currentDownloadID
        webView?.stopLoading()
        activeDownloadTask?.cancel()
        timeoutTask?.cancel()
        finish(.failure(DownloaderError.cancelled), for: downloadID)
    }

    // MARK: - Private

    private func finish(_ result: Result<URL, Error>, for downloadID: UUID? = nil) {
        if let downloadID, !isCurrentDownload(downloadID) { return }

        switch result {
        case .success(let url):
            print("[Downloader] ⤓ finish success → \(url.lastPathComponent)")
        case .failure(let error):
            print("[Downloader] ⤓ finish failure → \(error.localizedDescription)")
        }
        timeoutTask?.cancel()
        timeoutTask = nil
        let cb = completion
        completion = nil

        if isInteractive {
            dismissInteractiveWebView()
            isInteractive = false
        }

        // Stop the WebView's loading but keep it around — callers may reuse
        // this downloader for a sequence of files (CanvasImportService does).
        webView?.stopLoading()
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        isDownloading = false
        interceptedPDFDownloadID = nil
        cb?(result)
    }

    /// Permanently release the WKWebView. Call when no further downloads
    /// will happen on this instance (e.g. at the end of an import batch).
    func teardown() {
        currentDownloadID = UUID()
        timeoutTask?.cancel()
        timeoutTask = nil
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        isDownloading = false
        interceptedPDFDownloadID = nil
        completion = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
    }

    private func showInteractiveWebView() {
        guard !isInteractive, let webView = webView, let rootVC = getMainWindowRootViewController() else { return }
        isInteractive = true
        timeoutTask?.cancel() // Pause timeout while user logs in

        let vc = UIViewController()
        vc.view.backgroundColor = .systemBackground
        vc.title = "Campus Login"
        vc.navigationItem.rightBarButtonItem = UIBarButtonItem(primaryAction: UIAction(title: "Cancel") { [weak self] _ in
            self?.finish(.failure(DownloaderError.cancelled))
        })

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.alpha = 0
        vc.view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: vc.view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor)
        ])

        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet

        rootVC.present(nav, animated: true) {
            UIView.animate(withDuration: 0.3) {
                webView.alpha = 1
            }
        }
    }

    private func dismissInteractiveWebView() {
        guard let webView = webView, let rootVC = getMainWindowRootViewController() else { return }
        rootVC.dismiss(animated: true) {
            webView.removeFromSuperview()
        }
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

    /// Returns true if `host` is the Canvas host we started with — i.e. once we're
    /// here, the user is back from any SSO / 2FA flow.
    private func isOnCanvasTargetHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased(), !host.isEmpty else { return false }
        if let target = targetHost, !target.isEmpty {
            if host == target { return true }
            if host.hasSuffix("." + target) { return true }
        }
        if host.contains("instructure.com") { return true }
        if host.contains("bcourses") { return true }
        return false
    }

    private func shouldAttachCookies(to url: URL) -> Bool {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }

        // Canvas hands us short-lived signed CDN URLs after the WKWebView
        // response. Those URLs are already authorized by their token. Sending
        // every Canvas/CalNet cookie to them can blow past CDN header limits
        // and produce HTTP 494 responses instead of PDFs.
        if host.contains("inst-fs") || host.contains("inscloudgate.net") || host.contains("canvas-user-content") {
            return false
        }

        return isOnCanvasTargetHost(host) || host.contains("berkeley.edu")
    }

    private func cookies(_ cookies: [HTTPCookie], matching url: URL) -> [HTTPCookie] {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return [] }
        return cookies.filter { cookie in
            let domain = cookie.domain
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == domain || host.hasSuffix("." + domain)
        }
    }

    /// True if the page URL/host smells like an authentication / SSO / 2FA
    /// redirect that the user needs to interact with.
    private func looksLikeAuthFlow(host: String?, urlString: String?) -> Bool {
        let lowerHost = host?.lowercased() ?? ""
        let lower = urlString?.lowercased() ?? ""

        if !lowerHost.isEmpty, !isOnCanvasTargetHost(lowerHost) { return true }

        let needles = [
            "/login", "/signin", "/sign-in",
            "/auth", "/cas",
            "/oauth", "/sso", "/idp",
            "saml", "shibboleth",
            "duosecurity", "duo.com", "/duo/", "/2fa/",
            "okta", "microsoftonline", "accounts.google", "ping", "auth0"
        ]
        return needles.contains(where: { lower.contains($0) })
    }

    /// Transforms a Canvas file page URL to its direct download variant.
    private static func canvasDownloadURL(from url: URL) -> URL {
        if let forced = CanvasFileURLResolver.forcedDownloadURL(from: url) {
            return forced
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        
        // Canvas uses ?download_frd=1 to force bypass the HTML viewer
        var queryItems = components?.queryItems ?? []
        queryItems.removeAll { $0.name == "download_frd" || $0.name == "wrap" }
        queryItems.append(URLQueryItem(name: "download_frd", value: "1"))
        components?.queryItems = queryItems
        
        let path = url.path
        if path.contains("/files/"),
           !path.hasSuffix("/download") {
            if let range = components?.path.range(of: #"/files/\d+"#, options: .regularExpression) {
                let matchEnd = components!.path[range].endIndex
                components?.path.insert(contentsOf: "/download", at: matchEnd)
            }
        }
        
        return components?.url ?? url
    }

    /// Persist current cookies to UserDefaults, converting session cookies to long-lived ones
    private func saveCookies(for url: URL?) async {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await cookieStore.allCookies()

        CanvasCookieStore.persist(cookies, primaryHost: url?.host)
    }

    /// Restore cookies from UserDefaults to the WKWebView DataStore container
    private func restoreCookies() async {
        await CanvasCookieStore.restoreIntoDefaultWebViewStore()
    }

    /// Saves data to temp and returns the file URL.
    private func savePDFToTemp(_ data: Data) -> URL? {
        guard isPDFSignatureValid(data) else { return nil }

        let safeName = suggestedTitle
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = safeName.hasSuffix(".pdf") ? safeName : "\(safeName).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: tempURL, options: [.atomic])
            return tempURL
        } catch {
            return nil
        }
    }

    /// Verifies the magic bytes of the downloaded data to ensure it's a real PDF.
    /// Scans the first 1024 bytes since some web frameworks or `webView.pdf()` snapshots
    /// prepend metadata or stream boundary headers before the actual `%PDF` signature.
    private func isPDFSignatureValid(_ data: Data) -> Bool {
        guard data.count > 4 else { return false }
        
        // Ensure we don't scan the whole file if it's huge, just the header area
        let searchRange = data.startIndex..<min(data.startIndex + 1024, data.endIndex)
        let magicBytes = Data([0x25, 0x50, 0x44, 0x46]) // "%PDF"
        
        return data.range(of: magicBytes, in: searchRange) != nil
    }

    private func dataPrefixDescription(_ data: Data) -> String {
        let prefix = data.prefix(32)
        let hex = prefix.map { String(format: "%02x", $0) }.joined(separator: " ")
        let asciiBytes = prefix.map { byte -> UInt8 in
            (byte >= 32 && byte <= 126) ? byte : 46
        }
        let ascii = String(decoding: asciiBytes, as: UTF8.self)
        return "hex=\(hex) ascii=\"\(ascii)\""
    }

    private func shouldIgnoreNavigationFailure(_ error: Error, currentURL: URL?) -> Bool {
        let nsError = error as NSError
        let isFrameInterrupted = nsError.domain == "WebKitErrorDomain" && nsError.code == 102
        let isCancelled = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
        guard isFrameInterrupted || isCancelled else { return false }

        let isExpectedPDFInterruption =
            interceptedPDFDownloadID == currentDownloadID
            || isDownloading
            || activeDownloadTask != nil
        if isExpectedPDFInterruption { return true }

        if isInteractive { return true }

        let failingURLString =
            (nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String)
            ?? (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.absoluteString
            ?? (nsError.userInfo["NSErrorFailingURLStringKey"] as? String)
            ?? currentURL?.absoluteString

        let failingHost =
            (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.host
            ?? failingURLString.flatMap { URL(string: $0)?.host }
            ?? currentURL?.host

        return looksLikeAuthFlow(host: failingHost, urlString: failingURLString)
    }
}

// MARK: - WKNavigationDelegate

extension CourseBrainPDFDownloader: WKNavigationDelegate {

    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        let request = await MainActor.run { navigationAction.request }
        guard let url = request.url else { return .allow }
        let host = url.host?.lowercased() ?? ""

        // If navigating to a Canvas file page that isn't the force-download variant
        if (host.contains("instructure.com") || host.contains("canvas") || host.contains("berkeley")),
           url.path.contains("/files/") {
            
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let isDownloadVariant = queryItems.contains { $0.name == "download_frd" && $0.value == "1" }
            let isDownloadPath = url.path.hasSuffix("/download")
            
            if !isDownloadVariant || !isDownloadPath {
                let correctURL = await MainActor.run { Self.canvasDownloadURL(from: url) }
                if correctURL.absoluteString != url.absoluteString {
                    await MainActor.run {
                        _ = webView.load(URLRequest(url: correctURL))
                    }
                    return .cancel
                }
            }
        }
        return .allow
    }

    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {

        // Access main-actor-isolated properties on MainActor
        let (mimeType, responseURL, contentDisp, downloadID) = await MainActor.run { () -> (String, URL?, String, UUID) in
            let resp = navigationResponse.response
            let mime = resp.mimeType?.lowercased() ?? ""
            let url = resp.url
            let disp: String
            if let http = resp as? HTTPURLResponse {
                disp = http.value(forHTTPHeaderField: "Content-Disposition") ?? ""
            } else {
                disp = ""
            }
            return (mime, url, disp, self.currentDownloadID)
        }

        print("[Downloader] webview navResponse mime=\(mimeType) url=\(responseURL?.absoluteString ?? "nil") disp=\(contentDisp)")

        // Don't open the interactive modal here. Many Canvas deployments
        // (Berkeley/CalNet etc.) bounce file requests through the SSO host as
        // a transient redirect even when the user is already signed in — if we
        // present the modal on every response that smells like auth we end up
        // flashing a "Campus Login" sheet for every PDF in the course.
        // We only show the modal from `didFinish` once a page has actually
        // settled on a non-Canvas host (i.e. the user really does need to act).

        // We only want to intercept if it's explicitly a PDF or an attachment
        let isPDF = mimeType.contains("pdf")
                 || mimeType.contains("octet-stream")
                 || (responseURL?.pathExtension.lowercased() == "pdf")

        if isPDF || contentDisp.lowercased().contains("attachment") {
            if let targetURL = responseURL {
                await MainActor.run {
                    self.interceptedPDFDownloadID = downloadID
                }
                Task { @MainActor in
                    guard self.isCurrentDownload(downloadID) else { return }
                    self.performAuthenticatedDownload(from: targetURL, for: downloadID)
                }
                return .cancel // Cancel webview load, we're handling it manually
            }
        }

        return .allow
    }

    /// Fetches the shared cookies from WKWebsiteDataStore and performs a manual URLSession download.
    /// This bypasses WKDownload's notorious issues with corrupting payloads.
    private func performAuthenticatedDownload(from downloadURL: URL, for downloadID: UUID) {
        guard isCurrentDownload(downloadID), !isDownloading else { return }
        isDownloading = true

        Task { @MainActor in
            guard self.isCurrentDownload(downloadID) else { return }
            await self.saveCookies(for: self.webView?.url ?? downloadURL) // Save auth state right before manual download
            let cookieStore = WKWebsiteDataStore.default().httpCookieStore
            let cookies = await cookieStore.allCookies()
            guard self.isCurrentDownload(downloadID) else { return }

            let shouldAttachCookies = self.shouldAttachCookies(to: downloadURL)
            let requestCookies = shouldAttachCookies ? self.cookies(cookies, matching: downloadURL) : []

            var request = URLRequest(url: downloadURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 30
            request.setValue("application/pdf,application/octet-stream;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            if !requestCookies.isEmpty {
                let cookieHeader = HTTPCookie.requestHeaderFields(with: requestCookies)
                for (key, value) in cookieHeader {
                    request.addValue(value, forHTTPHeaderField: key)
                }
            }
            print("[Downloader]   signed pdf request host=\(downloadURL.host ?? "nil") cookies=\(requestCookies.count)")

            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 90
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.httpShouldSetCookies = shouldAttachCookies
            config.httpCookieAcceptPolicy = shouldAttachCookies ? .always : .never
            if shouldAttachCookies {
                let storage = HTTPCookieStorage()
                for cookie in requestCookies {
                    storage.setCookie(cookie)
                }
                config.httpCookieStorage = storage
            } else {
                config.httpCookieStorage = nil
            }

            let session = URLSession(configuration: config)
            let task = session.dataTask(with: request) { data, response, error in
                Task { @MainActor in
                    session.finishTasksAndInvalidate()
                    guard self.isCurrentDownload(downloadID) else { return }

                    let http = response as? HTTPURLResponse
                    let status = http?.statusCode ?? -1
                    let finalURL = http?.url ?? response?.url
                    let contentType = (http?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
                    let contentDisp = (http?.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased()
                    print("[Downloader]   signed pdf status=\(status) finalURL=\(finalURL?.absoluteString ?? "nil") contentType=\(contentType) contentDisp=\(contentDisp) bytes=\(data?.count ?? 0)")

                    if let error = error {
                        self.finish(.failure(error), for: downloadID)
                        return
                    }

                    if status >= 400 {
                        if let data, !data.isEmpty {
                            print("[Downloader]   error body prefix \(self.dataPrefixDescription(data))")
                        }
                        self.finish(.failure(DownloaderError.noData), for: downloadID)
                        return
                    }

                    guard let data, !data.isEmpty else {
                        self.finish(.failure(DownloaderError.noData), for: downloadID)
                        return
                    }

                    if let finalURL = self.savePDFToTemp(data) {
                        self.finish(.success(finalURL), for: downloadID)
                    } else {
                        print("[Downloader]   invalid pdf prefix \(self.dataPrefixDescription(data))")
                        self.finish(.failure(DownloaderError.invalidPDF), for: downloadID)
                    }
                }
            }
            guard self.isCurrentDownload(downloadID) else {
                task.cancel()
                session.invalidateAndCancel()
                return
            }
            self.activeDownloadTask = task
            task.resume()
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor in
            if self.shouldIgnoreNavigationFailure(error, currentURL: webView.url) {
                print("[Downloader] webview didFail ignored during auth/download → \(error.localizedDescription)")
                return
            }
            print("[Downloader] webview didFail → \(error.localizedDescription)")
            self.finish(.failure(error), for: self.currentDownloadID)
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor in
            if self.shouldIgnoreNavigationFailure(error, currentURL: webView.url) {
                print("[Downloader] webview didFailProvisional ignored during auth/download → \(error.localizedDescription)")
                return
            }
            print("[Downloader] webview didFailProvisional → \(error.localizedDescription)")
            self.finish(.failure(error), for: self.currentDownloadID)
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        Task { @MainActor in
            let downloadID = self.currentDownloadID
            // Wait a moment for any DOM redirects to execute before attempting a snapshot
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            // If a download intercepted the frame, completion is nil
            guard self.isCurrentDownload(downloadID) else { return }

            let currentHost = webView.url?.host
            let currentURLString = webView.url?.absoluteString
            print("[Downloader] webview didFinish url=\(currentURLString ?? "nil")")

            // Persist any cookies dropped by SSO providers along the way so we can
            // re-authenticate silently next time.
            await self.saveCookies(for: webView.url)
            guard self.isCurrentDownload(downloadID) else { return }
            if self.isDownloading || self.activeDownloadTask != nil {
                return
            }

            // If we're not back on the original Canvas host yet (or this looks like
            // an SSO / Duo / 2FA hop), figure out whether the user actually needs
            // to interact with the page. A transient SSO redirect (e.g. Berkeley's
            // CalNet validating an existing session) shouldn't flash the modal —
            // the redirect chain will finish on its own. Only if we see a real
            // login form / Duo prompt do we present the interactive WebView.
            let stillAuthing = self.looksLikeAuthFlow(host: currentHost, urlString: currentURLString)
            if stillAuthing {
                let needsInteraction = (try? await webView.evaluateJavaScript("""
                    (function() {
                        const hasPasswordInput = document.querySelector('input[type="password"]') !== null;
                        const hasUsernameInput = document.querySelector('input[type="text"][name*="user" i], input[type="email"]') !== null;
                        const hasDuoFrame = document.querySelector('iframe[src*="duo" i], iframe[src*="2fa" i]') !== null;
                        const hasDuoPrompt = document.querySelector('[data-app*="duo" i], [class*="duo-" i], [id*="duo_" i]') !== null;
                        return hasPasswordInput || hasUsernameInput || hasDuoFrame || hasDuoPrompt;
                    })()
                """) as? Bool) ?? false

                if needsInteraction {
                    self.showInteractiveWebView()
                }
                // Either way, don't finish the request here — wait for the next
                // didFinish (the redirect will complete or the user will sign in).
                return
            }

            // We're back on Canvas. If the modal was up for sign-in, dismiss it
            // and re-arm the timeout for the actual download leg.
            if self.isInteractive {
                self.dismissInteractiveWebView()
                self.isInteractive = false
                self.scheduleTimeout(for: downloadID)
            }

            // Evaluate JS to see if the page explicitly renders a PDF viewer frame
            let isPDFViewer = (try? await webView.evaluateJavaScript("""
                document.contentType === 'application/pdf' ||
                document.querySelector('embed[type="application/pdf"]') !== null
            """) as? Bool) ?? false

            if isPDFViewer {
                if let data = try? await webView.pdf(), let url = self.savePDFToTemp(data) {
                    self.finish(.success(url), for: downloadID)
                } else {
                    self.finish(.failure(DownloaderError.noData), for: downloadID)
                }
            } else {
                // Not a PDF, didn't download — let the request time out or be
                // resolved by `decidePolicyFor navigationResponse` if a download
                // is still pending.
                self.finish(.failure(DownloaderError.invalidPDF), for: downloadID)
            }
        }
    }
}
