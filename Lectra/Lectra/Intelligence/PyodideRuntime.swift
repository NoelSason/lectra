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
    var result: String?      // repr of the last expression, Jupyter-style
    var error: String?       // formatted traceback, if the cell raised
    var images: [String] = []  // base64-encoded PNGs (matplotlib figures)
}

/// Outcome of a `micropip` install requested from Swift.
struct PyodideInstallResult {
    var success: Bool
    var error: String?
}

/// Raw payload returned by the JS install bridge: either micropip's freeze()
/// lockfile (on success) or an error string.
private struct InstallRaw {
    var freeze: String?
    var error: String?
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
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var runContinuations: [String: CheckedContinuation<PyodideRunResult, Never>] = [:]
    private var installContinuations: [String: CheckedContinuation<InstallRaw, Never>] = [:]
    private var installLocalContinuations: [String: CheckedContinuation<Void, Never>] = [:]

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

    // MARK: Packages & files

    /// Installs `name` from PyPI via micropip, then mirrors the resolved wheels
    /// into the offline cache so later sessions install it without a network.
    /// Never throws — failures come back in `PyodideInstallResult.error`.
    func install(_ name: String) async -> PyodideInstallResult {
        do { try await start() } catch {
            return PyodideInstallResult(success: false,
                error: "Python couldn't start: \(error.localizedDescription)")
        }
        guard let webView else { return PyodideInstallResult(success: false, error: "No kernel.") }

        let reqID = UUID().uuidString
        let raw: InstallRaw = await withCheckedContinuation { cont in
            installContinuations[reqID] = cont
            let js = "window.lectraInstall(\(Self.jsString(reqID)), \(Self.jsString(name))); undefined;"
            webView.evaluateJavaScript(js) { [weak self] _, error in
                guard let self, error != nil else { return }
                if let pending = self.installContinuations.removeValue(forKey: reqID) {
                    pending.resume(returning: InstallRaw(freeze: nil, error: "Execution failed."))
                }
            }
        }

        if let err = raw.error {
            return PyodideInstallResult(success: false, error: Self.friendlyInstallError(err, name: name))
        }
        if let freeze = raw.freeze {
            let wheels = Self.wheelRefs(fromFreeze: freeze)
            await PackageCache.shared.store(topLevel: name, wheels: wheels)
        }
        return PyodideInstallResult(success: true, error: nil)
    }

    /// Writes raw bytes into the kernel's in-memory filesystem at `path`
    /// (creating parent dirs). Used to drop data files and cached wheels in.
    @discardableResult
    func writeFile(path: String, base64: String) async -> Bool {
        guard let webView else { return false }
        let js = "window.lectraWriteFile(\(Self.jsString(path)), \(Self.jsString(base64)));"
        return await withCheckedContinuation { cont in
            webView.evaluateJavaScript(js) { result, _ in
                cont.resume(returning: (result as? NSNumber)?.boolValue ?? (result as? Bool) ?? false)
            }
        }
    }

    /// Re-installs every cached wheel from disk into a freshly-booted kernel,
    /// so packages added in a previous session are available offline.
    private func reinstallCachedPackages() async {
        let paths = await PackageCache.shared.cachedWheelPaths()
        guard !paths.isEmpty, let webView else { return }
        var emfsPaths: [String] = []
        for url in paths {
            guard let data = try? Data(contentsOf: url) else { continue }
            let emfs = "/lectra_pkgs/\(url.lastPathComponent)"
            if await writeFile(path: emfs, base64: data.base64EncodedString()) {
                emfsPaths.append(emfs)
            }
        }
        guard !emfsPaths.isEmpty,
              let data = try? JSONEncoder().encode(emfsPaths),
              let json = String(data: data, encoding: .utf8) else { return }

        let reqID = UUID().uuidString
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            installLocalContinuations[reqID] = cont
            let js = "window.lectraInstallLocal(\(Self.jsString(reqID)), \(Self.jsString(json))); undefined;"
            webView.evaluateJavaScript(js) { [weak self] _, error in
                guard let self, error != nil else { return }
                if let pending = self.installLocalContinuations.removeValue(forKey: reqID) {
                    pending.resume()
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
        webView = nil
        status = .idle
    }

    // MARK: WebView construction

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(PyodideSchemeHandler(), forURLScheme: Self.scheme)
        config.userContentController.add(self, name: "lectra")
        // Deliberately NOT added to any window. An attached WKWebView puts its
        // content view in the key window's responder chain, where it swallows
        // hardware-keyboard modifiers (Shift, ⌘) from the editor. Off-window it
        // still executes JS/WASM (we only need execution, not rendering), so it
        // can't interfere with text input.
        let webView = KernelWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        self.webView = webView
        return webView
    }

    private static func jsString(_ s: String) -> String {
        // Produce a safely-escaped JS string literal via JSON.
        guard let data = try? JSONEncoder().encode(s),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return json
    }

    /// Turns a raw micropip error into a message that explains the on-device
    /// limitation rather than leaking a Python traceback.
    private static func friendlyInstallError(_ raw: String, name: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("can't find a pure python")
            || lower.contains("no matching distribution")
            || lower.contains("pure python wheel") {
            return "“\(name)” isn’t available for on-device Python (no compatible wheel)."
        }
        return raw
    }

    /// Extracts the network-fetched wheels from micropip's freeze() lockfile.
    /// Bundled packages carry relative file names, so filtering on an http(s)
    /// prefix naturally selects only the wheels we should mirror to disk.
    private static func wheelRefs(fromFreeze json: String) -> [WheelRef] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let packages = root["packages"] as? [String: Any] else { return [] }
        var refs: [WheelRef] = []
        for (_, value) in packages {
            guard let pkg = value as? [String: Any],
                  let fileName = pkg["file_name"] as? String,
                  fileName.hasPrefix("http"),
                  let url = URL(string: fileName) else { continue }
            refs.append(WheelRef(fileName: url.lastPathComponent, url: url))
        }
        return refs
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
            // Re-install any packages cached from prior sessions before the
            // kernel is reported ready, so offline imports just work.
            Task { [weak self] in
                guard let self else { return }
                await self.reinstallCachedPackages()
                self.status = .ready
                self.startContinuation?.resume()
                self.startContinuation = nil
            }
        case "installed":
            guard let reqID = body["reqID"] as? String,
                  let cont = installContinuations.removeValue(forKey: reqID) else { return }
            cont.resume(returning: InstallRaw(freeze: body["freeze"] as? String, error: nil))
        case "installedLocal":
            if let reqID = body["reqID"] as? String,
               let cont = installLocalContinuations.removeValue(forKey: reqID) {
                cont.resume()
            }
        case "installError":
            if let reqID = body["reqID"] as? String {
                if let cont = installContinuations.removeValue(forKey: reqID) {
                    cont.resume(returning: InstallRaw(
                        freeze: nil, error: (body["error"] as? String) ?? "Install failed."))
                } else if let cont = installLocalContinuations.removeValue(forKey: reqID) {
                    cont.resume()
                }
            }
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
                error: body["error"] as? String,
                images: (body["images"] as? [String]) ?? []))
        case "reset":
            break
        default:
            break
        }
    }
}

// MARK: - Kernel web view

/// A WKWebView that never accepts first-responder status, so it can't capture
/// hardware-keyboard input even if it ends up in a responder chain.
private final class KernelWebView: WKWebView {
    override var canBecomeFirstResponder: Bool { false }
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
