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
    private var activeDownloadTask: URLSessionDownloadTask?
    private var timeoutTask: Task<Void, Never>?
    private var downloadDestination: URL?
    private var isInteractive = false
    private weak var presentationAnchor: UIView?
    private var isDownloading = false

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
        self.completion = completion
        self.suggestedTitle = title
        self.presentationAnchor = view

        // Create a WKWebView configuration that shares Safari's cookie store
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        // Restore cookies before loading
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.restoreCookies()
            
            let wv = WKWebView(frame: .zero, configuration: config)
            wv.navigationDelegate = self
            self.webView = wv

            // Transform Canvas file URLs to direct download variant
            let downloadURL = Self.canvasDownloadURL(from: url)
            wv.load(URLRequest(url: downloadURL))

            // Timeout after 30 seconds if not interactive
            self.scheduleTimeout()
        }
    }

    private func scheduleTimeout(cancelInteractive: Bool = false) {
        timeoutTask?.cancel()
        if isInteractive && !cancelInteractive { return }

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self, self.completion != nil, !self.isInteractive else { return }
            self.finish(.failure(DownloaderError.timeout))
        }
    }

    func cancel() {
        webView?.stopLoading()
        activeDownloadTask?.cancel()
        timeoutTask?.cancel()
        finish(.failure(DownloaderError.cancelled))
    }

    // MARK: - Private

    private func finish(_ result: Result<URL, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        let cb = completion
        completion = nil

        if isInteractive {
            dismissInteractiveWebView()
        }

        webView?.navigationDelegate = nil
        webView = nil
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        cb?(result)
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

    /// Transforms a Canvas file page URL to its direct download variant.
    private static func canvasDownloadURL(from url: URL) -> URL {
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
}

// MARK: - WKNavigationDelegate

extension CourseBrainPDFDownloader: WKNavigationDelegate {

    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }
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
                        webView.load(URLRequest(url: correctURL))
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
        let (mimeType, responseURL, contentDisp) = await MainActor.run { () -> (String, URL?, String) in
            let resp = navigationResponse.response
            let mime = resp.mimeType?.lowercased() ?? ""
            let url = resp.url
            let disp: String
            if let http = resp as? HTTPURLResponse {
                disp = http.value(forHTTPHeaderField: "Content-Disposition") ?? ""
            } else {
                disp = ""
            }
            return (mime, url, disp)
        }

        // Detect explicit login or SSO auth redirection pages
        if let urlString = responseURL?.absoluteString.lowercased(),
           urlString.contains("login") || urlString.contains("auth") || urlString.contains("cas") || urlString.contains("berkeley") {
            await MainActor.run { self.showInteractiveWebView() }
            return .allow
        }

        // We only want to intercept if it's explicitly a PDF or an attachment
        let isPDF = mimeType.contains("pdf")
                 || mimeType.contains("octet-stream")
                 || (responseURL?.pathExtension.lowercased() == "pdf")

        if isPDF || contentDisp.lowercased().contains("attachment") {
            if let targetURL = responseURL {
                Task { @MainActor in
                    self.performAuthenticatedDownload(from: targetURL)
                }
                return .cancel // Cancel webview load, we're handling it manually
            }
        }

        return .allow
    }

    /// Fetches the shared cookies from WKWebsiteDataStore and performs a manual URLSession download.
    /// This bypasses WKDownload's notorious issues with corrupting payloads.
    private func performAuthenticatedDownload(from downloadURL: URL) {
        guard !isDownloading else { return }
        isDownloading = true

        Task { @MainActor in
            await self.saveCookies(for: downloadURL) // Save auth state right before manual download
            let cookieStore = WKWebsiteDataStore.default().httpCookieStore
            let cookies = await cookieStore.allCookies()

            var request = URLRequest(url: downloadURL)
            let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in cookieHeader {
                request.addValue(value, forHTTPHeaderField: key)
            }

            let session = URLSession(configuration: .default)
            let task = session.downloadTask(with: request) { [weak self] tempLocation, response, error in
                guard let self = self else { return }
                Task { @MainActor in
                    if let error = error {
                        self.finish(.failure(error))
                        return
                    }

                    guard let tempLocation = tempLocation,
                          let data = try? Data(contentsOf: tempLocation) else {
                        self.finish(.failure(DownloaderError.noData))
                        return
                    }

                    if let finalURL = self.savePDFToTemp(data) {
                        self.finish(.success(finalURL))
                    } else {
                        self.finish(.failure(DownloaderError.invalidPDF))
                    }
                }
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
            self.finish(.failure(error))
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        Task { @MainActor in
            // Wait a moment for any DOM redirects to execute before attempting a snapshot
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            // Check if we're stuck on an auth page
            if let host = webView.url?.host?.lowercased(), host.contains("auth") || host.contains("login") || host.contains("berkeley") {
                 self.showInteractiveWebView()
                 return
            }

            // If a download intercepted the frame, completion is nil
            guard self.completion != nil else { return }

            // Re-arm local timeout if we were interactive and finished navigating a non-auth page.
            if self.isInteractive {
                self.dismissInteractiveWebView()
                self.isInteractive = false
                self.scheduleTimeout()
            }

            await self.saveCookies(for: webView.url) // Persist Canvas session state for both interactive and inline web flows

            // Evaluate JS to see if the page explicitly renders a PDF viewer frame
            let isPDFViewer = (try? await webView.evaluateJavaScript("""
                document.contentType === 'application/pdf' || 
                document.querySelector('embed[type="application/pdf"]') !== null
            """) as? Bool) ?? false

            if isPDFViewer {
                if let data = try? await webView.pdf(), let url = self.savePDFToTemp(data) {
                    self.finish(.success(url))
                } else {
                    self.finish(.failure(DownloaderError.noData))
                }
            } else {
                // Not a PDF, didn't download, and not falling back to snapshot HTML login pages.
                self.finish(.failure(DownloaderError.invalidPDF))
            }
        }
    }
}
