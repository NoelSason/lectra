//
//  PyodideRuntime.swift
//  Lectra
//
//  Runs real CPython inside Lectra with no server. Python ships as Pyodide
//  (CPython compiled to WebAssembly) and executes in a hidden WKWebView; only
//  the SwiftUI notebook UI is native. All runtime assets are bundled under
//  Resources/Pyodide and served over the custom `lectrapy://` scheme — loading
//  Pyodide from `file://` trips WebKit's fetch/CORS restrictions, so the scheme
//  handler is what makes this work offline.
//
//  One PyodideRuntime is one persistent kernel: state carries across cell runs,
//  like a Jupyter kernel. `restart()` clears the namespace.
//

import Foundation
import Combine
import WebKit
import UIKit

/// Raw result of executing one cell. Mapped to notebook outputs by the model.
struct PyodideRunResult {
    var stdout: String
    var stderr: String
    var result: String?   // repr of the last expression, Jupyter-style
    var error: String?    // formatted traceback, if the cell raised
}

@MainActor
final class PyodideRuntime: NSObject, ObservableObject {

    enum KernelStatus: Equatable {
        case idle
        case starting
        case ready
        case failed(String)
    }

    @Published private(set) var status: KernelStatus = .idle

    private var webView: WKWebView?
    /// A dedicated, non-key host window for the kernel's WKWebView. Keeping the
    /// web context in its own window (never made key) lets it load and run while
    /// staying out of the editor's responder chain — otherwise WKWebView
    /// swallows hardware-keyboard commands (Shift, ⌘A, …) from the text view.
    private var kernelWindow: UIWindow?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var runContinuations: [String: CheckedContinuation<PyodideRunResult, Never>] = [:]

    private static let scheme = "lectrapy"
    private static let hostPage = "lectrapy:///pyodide_host.html"

    // MARK: Lifecycle

    /// Boots the kernel if needed and resolves once Python is ready. Safe to
    /// call repeatedly; concurrent callers share the single boot.
    func start() async throws {
        switch status {
        case .ready: return
        case .starting:
            // Wait for the in-flight boot by polling the published status.
            while status == .starting { try await Task.sleep(nanoseconds: 50_000_000) }
            if case .failed(let m) = status { throw PyodideError.boot(m) }
            return
        default: break
        }

        status = .starting
        let webView = ensureWebView()

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            startContinuation = cont
            guard let url = URL(string: Self.hostPage) else {
                cont.resume(throwing: PyodideError.boot("Bad host URL"))
                startContinuation = nil
                return
            }
            webView.load(URLRequest(url: url))
        }
    }

    /// Runs `code` in the kernel and returns its captured output. Never throws —
    /// Python errors come back inside `PyodideRunResult.error`.
    func run(_ code: String, cellID: String) async -> PyodideRunResult {
        do { try await start() } catch {
            return PyodideRunResult(stdout: "", stderr: "", result: nil,
                                    error: "Python couldn't start: \(error.localizedDescription)")
        }
        guard let webView else {
            return PyodideRunResult(stdout: "", stderr: "", result: nil, error: "No kernel.")
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<PyodideRunResult, Never>) in
            runContinuations[cellID] = cont
            // `lectraRun` is async, so it returns a Promise. End the script with
            // `undefined;` so evaluateJavaScript doesn't try (and fail) to bridge
            // the Promise — the real result arrives via the message handler.
            let js = "window.lectraRun(\(Self.jsString(cellID)), \(Self.jsString(code))); undefined;"
            webView.evaluateJavaScript(js) { [weak self] _, error in
                guard let self, let error else { return }
                // JS dispatch failed outright; resolve so the cell isn't stuck.
                if let pending = self.runContinuations.removeValue(forKey: cellID) {
                    pending.resume(returning: PyodideRunResult(
                        stdout: "", stderr: "", result: nil,
                        error: "Execution failed: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// Clears the kernel namespace (a lightweight "restart").
    func restart() {
        webView?.evaluateJavaScript("window.lectraReset && window.lectraReset();")
    }

    /// Tears down the kernel and detaches its web context. Call when the
    /// notebook screen closes so the WASM runtime is released.
    func shutdown() {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "lectra")
        webView?.removeFromSuperview()
        webView = nil
        status = .idle
    }

    // MARK: WebView construction

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(PyodideSchemeHandler(), forURLScheme: Self.scheme)
        config.userContentController.add(self, name: "lectra")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView.isHidden = true
        // Keep the web context out of the responder chain — otherwise the
        // off-screen WKWebView intercepts hardware-keyboard events (e.g. the
        // Shift modifier) from the SwiftUI editor above it.
        webView.isUserInteractionEnabled = false
        // Attach behind everything in the key window so the JS/WASM context
        // runs reliably while the notebook is open.
        if let window = Self.keyWindow {
            window.insertSubview(webView, at: 0)
        }
        self.webView = webView
        return webView
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ??
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first
    }

    private static func jsString(_ s: String) -> String {
        // Produce a safely-escaped JS string literal via JSON.
        guard let data = try? JSONEncoder().encode(s),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return json
    }

    enum PyodideError: LocalizedError {
        case boot(String)
        var errorDescription: String? {
            switch self { case .boot(let m): return m }
        }
    }
}

// MARK: - JS → Swift bridge

extension PyodideRuntime: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController,
                              didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        handle(type: type, body: body)
    }

    private func handle(type: String, body: [String: Any]) {
        switch type {
        case "ready":
            status = .ready
            startContinuation?.resume()
            startContinuation = nil
        case "fatal":
            let msg = (body["error"] as? String) ?? "Python failed to start."
            status = .failed(msg)
            startContinuation?.resume(throwing: PyodideError.boot(msg))
            startContinuation = nil
        case "result":
            guard let cellID = body["cellID"] as? String,
                  let cont = runContinuations.removeValue(forKey: cellID) else { return }
            cont.resume(returning: PyodideRunResult(
                stdout: (body["stdout"] as? String) ?? "",
                stderr: (body["stderr"] as? String) ?? "",
                result: body["result"] as? String,
                error: body["error"] as? String))
        case "reset":
            break
        default:
            break
        }
    }
}

// MARK: - Bundled-asset scheme handler

/// Serves the bundled Pyodide files over `lectrapy://` with correct MIME types.
private final class PyodideSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL)); return
        }
        let name = url.lastPathComponent.isEmpty ? "pyodide_host.html" : url.lastPathComponent
        guard let fileURL = Self.bundledURL(for: name),
              let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": Self.mimeType(for: name),
                "Content-Length": String(data.count),
                "Access-Control-Allow-Origin": "*"
            ])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    /// Resolves a bundled file whether the Pyodide assets ship as a folder
    /// reference ("Pyodide/…") or flattened into the bundle root.
    private static func bundledURL(for name: String) -> URL? {
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        if let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Pyodide") {
            return url
        }
        return Bundle.main.url(forResource: base, withExtension: ext)
    }

    private static func mimeType(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "html": return "text/html"
        case "js", "mjs": return "text/javascript"
        case "wasm": return "application/wasm"
        case "json": return "application/json"
        case "zip": return "application/zip"
        default: return "application/octet-stream"
        }
    }
}
