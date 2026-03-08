import UIKit
import WebKit

/// Downloads a PDF from a Canvas URL using an in-app WKWebView.
///
/// WKWebView shares Safari's cookies via `WKWebsiteDataStore.default()`,
/// so the user's Canvas login session is automatically available.
/// The web view loads the URL in the background, intercepts the PDF
/// download via `WKDownloadDelegate`, and calls completion with the
/// local file URL.
@MainActor
final class CourseBrainPDFDownloader: NSObject {

    private var webView: WKWebView?
    private var completion: ((Result<URL, Error>) -> Void)?
    private var suggestedTitle: String = ""
    private var timeoutTask: Task<Void, Never>?
    private var activeDownload: WKDownload?
    private var downloadDestination: URL?

    enum DownloaderError: LocalizedError {
        case timeout
        case cancelled
        case noData

        var errorDescription: String? {
            switch self {
            case .timeout:   return "Download timed out"
            case .cancelled: return "Download was cancelled"
            case .noData:    return "No PDF data received"
            }
        }
    }

    /// Start downloading a PDF from the given URL.
    /// - Parameters:
    ///   - url: The Canvas file URL.
    ///   - title: Suggested filename for the downloaded PDF.
    ///   - completion: Called on the main thread with the local file URL on success.
    func download(from url: URL, title: String, completion: @escaping (Result<URL, Error>) -> Void) {
        self.completion = completion
        self.suggestedTitle = title

        // Create a WKWebView configuration that shares Safari's cookie store
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        self.webView = wv

        // Transform Canvas file URLs to direct download variant
        let downloadURL = Self.canvasDownloadURL(from: url)
        wv.load(URLRequest(url: downloadURL))

        // Timeout after 30 seconds
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self, self.completion != nil else { return }
            self.finish(.failure(DownloaderError.timeout))
        }
    }

    func cancel() {
        webView?.stopLoading()
        activeDownload?.cancel()
        timeoutTask?.cancel()
        finish(.failure(DownloaderError.cancelled))
    }

    // MARK: - Private

    private func finish(_ result: Result<URL, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        let cb = completion
        completion = nil
        webView?.navigationDelegate = nil
        webView = nil
        activeDownload = nil
        cb?(result)
    }

    /// Transforms a Canvas file page URL to its direct download variant.
    private static func canvasDownloadURL(from url: URL) -> URL {
        let path = url.path
        if path.contains("/files/"),
           !path.hasSuffix("/download") {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let range = components?.path.range(of: #"/files/\d+"#, options: .regularExpression) {
                let matchEnd = components!.path[range].endIndex
                components?.path.insert(contentsOf: "/download", at: matchEnd)
                if let result = components?.url {
                    return result
                }
            }
        }
        return url
    }

    /// Saves data to temp and returns the file URL.
    private func savePDFToTemp(_ data: Data) -> URL? {
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
}

// MARK: - WKNavigationDelegate

extension CourseBrainPDFDownloader: WKNavigationDelegate {

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

        // Check if the response is a PDF (by MIME type)
        let isPDF = mimeType.contains("pdf")
                 || mimeType.contains("octet-stream")
                 || (responseURL?.pathExtension.lowercased() == "pdf")

        if isPDF {
            return .download
        }

        // If the response is a disposition:attachment, download it
        if contentDisp.lowercased().contains("attachment") {
            return .download
        }

        return .allow
    }

    nonisolated func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        Task { @MainActor in
            self.activeDownload = download
            download.delegate = self
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        Task { @MainActor in
            self.activeDownload = download
            download.delegate = self
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
        // The page finished loading. If we haven't triggered a download,
        // try to grab the page content as a PDF (snapshot).
        Task { @MainActor in
            // Wait a moment for any redirects
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            // If completion is already nil, we already finished
            guard self.completion != nil else { return }

            // Try to create a PDF from the web view content
            if let data = try? await webView.pdf() {
                if let url = self.savePDFToTemp(data) {
                    self.finish(.success(url))
                } else {
                    self.finish(.failure(DownloaderError.noData))
                }
            } else {
                self.finish(.failure(DownloaderError.noData))
            }
        }
    }
}

// MARK: - WKDownloadDelegate

extension CourseBrainPDFDownloader: WKDownloadDelegate {

    nonisolated func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        let safeName = suggestedFilename.isEmpty
            ? "\(await suggestedTitle).pdf"
            : suggestedFilename
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        try? FileManager.default.removeItem(at: tempURL) // Remove if exists
        await MainActor.run { self.downloadDestination = tempURL }
        return tempURL
    }

    nonisolated func downloadDidFinish(_ download: WKDownload) {
        Task { @MainActor in
            if let dest = self.downloadDestination,
               FileManager.default.fileExists(atPath: dest.path) {
                self.finish(.success(dest))
            } else {
                self.finish(.failure(DownloaderError.noData))
            }
        }
    }

    nonisolated func download(
        _ download: WKDownload,
        didFailWithError error: Error,
        resumeData: Data?
    ) {
        Task { @MainActor in
            self.finish(.failure(error))
        }
    }
}
