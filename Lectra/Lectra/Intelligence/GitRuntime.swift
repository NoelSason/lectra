//
//  GitRuntime.swift
//  Lectra
//
//  Runs real git (isomorphic-git) inside a hidden WKWebView, mirroring the
//  PyodideRuntime pattern: an off-window web view, a custom `lectragit://` scheme
//  serving the bundled JS, and a JS<->Swift bridge. The difference is that git
//  needs a filesystem and a network transport, so both are bridged to native
//  Swift:
//    - `gitfs`   ops map to FileManager, so the app sandbox is the single source
//      of truth shared with the terminal shell and the code editor.
//    - `githttp` ops go through URLSession (with GitHub auth injected), which
//      avoids WebKit's CORS wall against github.com.
//
//  One GitRuntime owns one web view; git commands are serialized through it.
//

import Foundation
import Combine
import WebKit

struct GitResult {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}

@MainActor
final class GitRuntime: NSObject, ObservableObject {

    enum Status: Equatable { case idle, starting, ready, failed(String) }
    @Published private(set) var status: Status = .idle

    private var webView: WKWebView?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var gitContinuations: [String: CheckedContinuation<GitResult, Never>] = [:]
    /// Streams `onProgress` lines from the in-flight command to the terminal.
    private var progressHandler: ((String) -> Void)?

    private static let scheme = "lectragit"
    private static let hostPage = "lectragit:///git_host.html"

    /// The sandbox container root; all fs ops are confined to it.
    private let sandboxRoot = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .standardizedFileURL

    private let urlSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 300
        return URLSession(configuration: cfg)
    }()

    // MARK: Lifecycle

    func start() async throws {
        let trace = LectraPerformanceTrace.begin(.web, "GitRuntimeStart")
        defer { LectraPerformanceTrace.end(trace) }

        switch status {
        case .ready: return
        case .starting:
            while status == .starting { try await Task.sleep(nanoseconds: 50_000_000) }
            if case .failed(let m) = status { throw GitError.boot(m) }
            return
        default: break
        }

        status = .starting
        let webView = ensureWebView()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            startContinuation = cont
            guard let url = URL(string: Self.hostPage) else {
                cont.resume(throwing: GitError.boot("Bad host URL"))
                startContinuation = nil
                return
            }
            webView.load(URLRequest(url: url))
        }
    }

    /// Runs one `git` invocation. `argv` is everything after `git` (e.g.
    /// ["commit", "-m", "msg"]); `cwd` is the absolute working-tree directory.
    /// Progress lines (clone/fetch/push) stream through `onProgress`.
    func run(argv: [String], cwd: String, onProgress: ((String) -> Void)? = nil) async -> GitResult {
        let trace = LectraPerformanceTrace.begin(.web, "GitCommand")
        defer { LectraPerformanceTrace.end(trace) }

        do { try await start() } catch {
            return GitResult(stdout: "", stderr: "git couldn't start: \(error.localizedDescription)\n", exitCode: 1)
        }
        guard let webView else {
            return GitResult(stdout: "", stderr: "git: no runtime\n", exitCode: 1)
        }
        let reqID = UUID().uuidString
        progressHandler = onProgress
        let argvJSON = Self.jsString(Self.jsonArray(argv))
        let result: GitResult = await withCheckedContinuation { cont in
            gitContinuations[reqID] = cont
            let js = "window.lectraGit(\(Self.jsString(reqID)), \(argvJSON), \(Self.jsString(cwd))); undefined;"
            webView.evaluateJavaScript(js) { [weak self] _, error in
                guard let self, let error else { return }
                if let pending = self.gitContinuations.removeValue(forKey: reqID) {
                    pending.resume(returning: GitResult(stdout: "", stderr: "git failed: \(error.localizedDescription)\n", exitCode: 1))
                }
            }
        }
        progressHandler = nil
        return result
    }

    func shutdown() {
        guard let webView else { return }
        let ucc = webView.configuration.userContentController
        ucc.removeScriptMessageHandler(forName: "lectragit")
        ucc.removeScriptMessageHandler(forName: "gitfs")
        ucc.removeScriptMessageHandler(forName: "githttp")
        self.webView = nil
        status = .idle
    }

    // MARK: WebView construction

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(GitSchemeHandler(), forURLScheme: Self.scheme)
        let ucc = config.userContentController
        ucc.add(self, name: "lectragit")
        ucc.addScriptMessageHandler(self, contentWorld: .page, name: "gitfs")
        ucc.addScriptMessageHandler(self, contentWorld: .page, name: "githttp")
        config.userContentController = ucc
        // Off-window, like the Pyodide kernel: executes JS without joining the
        // responder chain, so it can't steal hardware-keyboard input.
        let webView = GitKernelWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        self.webView = webView
        return webView
    }

    // MARK: Path confinement

    private func resolved(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let root = sandboxRoot.path.hasSuffix("/") ? sandboxRoot.path : sandboxRoot.path + "/"
        guard url.path == sandboxRoot.path || url.path.hasPrefix(root) else {
            throw GitError.fs("EPERM", "path escapes the app sandbox")
        }
        return url
    }

    // MARK: JS helpers

    private static func jsString(_ s: String) -> String {
        guard let data = try? JSONEncoder().encode(s), let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return json
    }
    private static func jsonArray(_ arr: [String]) -> String {
        guard let data = try? JSONEncoder().encode(arr), let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    enum GitError: LocalizedError {
        case boot(String)
        case fs(String, String) // code, message
        var errorDescription: String? {
            switch self { case .boot(let m): return m; case .fs(_, let m): return m }
        }
    }
}

// MARK: - JS -> Swift: command results & progress

extension GitRuntime: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            status = .ready
            startContinuation?.resume()
            startContinuation = nil
        case "fatal":
            let m = (body["error"] as? String) ?? "git failed to start."
            status = .failed(m)
            startContinuation?.resume(throwing: GitError.boot(m))
            startContinuation = nil
        case "gitProgress":
            if let line = body["line"] as? String, !line.isEmpty { progressHandler?(line) }
        case "gitResult":
            guard let reqID = body["reqID"] as? String, let cont = gitContinuations.removeValue(forKey: reqID) else { return }
            cont.resume(returning: GitResult(
                stdout: (body["stdout"] as? String) ?? "",
                stderr: (body["stderr"] as? String) ?? "",
                exitCode: Int32((body["exitCode"] as? Int) ?? 1)))
        default: break
        }
    }
}

// MARK: - JS -> Swift -> JS: fs and http adapters (reply-based)

extension GitRuntime: WKScriptMessageHandlerWithReply {
    func userContentController(_ controller: WKUserContentController,
                              didReceive message: WKScriptMessage,
                              replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any] else { replyHandler(["ok": false, "message": "bad message"], nil); return }
        switch message.name {
        case "gitfs": handleFS(body, reply: replyHandler)
        case "githttp": handleHTTP(body, reply: replyHandler)
        default: replyHandler(["ok": false, "message": "unknown handler"], nil)
        }
    }

    private func handleFS(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) {
        let trace = LectraPerformanceTrace.begin(.web, "GitFSOperation")
        defer { LectraPerformanceTrace.end(trace) }

        guard let op = body["op"] as? String, let path = body["path"] as? String else {
            reply(["ok": false, "code": "EINVAL", "message": "missing op/path"], nil); return
        }
        let fm = FileManager.default
        do {
            let url = try resolved(path)
            switch op {
            case "readFile":
                guard let data = fm.contents(atPath: url.path) else { throw GitError.fs("ENOENT", "no such file: \(path)") }
                reply(["ok": true, "dataB64": data.base64EncodedString()], nil)
            case "writeFile":
                let b64 = (body["dataB64"] as? String) ?? ""
                let data = Data(base64Encoded: b64) ?? Data()
                try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard fm.createFile(atPath: url.path, contents: data) else { throw GitError.fs("EIO", "write failed: \(path)") }
                reply(["ok": true], nil)
            case "unlink":
                if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
                reply(["ok": true], nil)
            case "readdir":
                let entries = try fm.contentsOfDirectory(atPath: url.path)
                reply(["ok": true, "entries": entries], nil)
            case "mkdir":
                try fm.createDirectory(at: url, withIntermediateDirectories: false)
                reply(["ok": true], nil)
            case "rmdir":
                try fm.removeItem(at: url)
                reply(["ok": true], nil)
            case "stat", "lstat":
                reply(try statReply(url: url, follow: op == "stat", fm: fm), nil)
            case "rename":
                guard let newPath = body["newPath"] as? String else { throw GitError.fs("EINVAL", "missing newPath") }
                let dst = try resolved(newPath)
                if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
                try fm.moveItem(at: url, to: dst)
                reply(["ok": true], nil)
            case "readlink":
                let dest = try fm.destinationOfSymbolicLink(atPath: url.path)
                reply(["ok": true, "target": dest], nil)
            case "symlink":
                guard let target = body["target"] as? String else { throw GitError.fs("EINVAL", "missing target") }
                try fm.createSymbolicLink(atPath: url.path, withDestinationPath: target)
                reply(["ok": true], nil)
            default:
                reply(["ok": false, "code": "ENOSYS", "message": "unsupported fs op \(op)"], nil)
            }
        } catch let GitError.fs(code, msg) {
            reply(["ok": false, "code": code, "message": msg], nil)
        } catch let err as NSError {
            // Map common Cocoa errors to POSIX-ish codes isomorphic-git expects.
            let code: String
            switch err.code {
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError: code = "ENOENT"
            case NSFileWriteFileExistsError: code = "EEXIST"
            default: code = "EIO"
            }
            reply(["ok": false, "code": code, "message": err.localizedDescription], nil)
        }
    }

    private func statReply(url: URL, follow: Bool, fm: FileManager) throws -> [String: Any] {
        let target = follow ? url.resolvingSymlinksInPath() : url
        guard let attrs = try? fm.attributesOfItem(atPath: target.path) else {
            throw GitError.fs("ENOENT", "no such file: \(target.path)")
        }
        let ftype = attrs[.type] as? FileAttributeType
        let type: String
        let mode: Int
        switch ftype {
        case .typeDirectory: type = "dir"; mode = 0o040000
        case .typeSymbolicLink: type = "symlink"; mode = 0o120000
        default: type = "file"; mode = 0o100644
        }
        let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return ["ok": true, "type": type, "mode": mode, "size": size,
                "mtimeMs": mtime * 1000, "ctimeMs": mtime * 1000, "ino": 0]
    }

    private func handleHTTP(_ body: [String: Any], reply: @escaping (Any?, String?) -> Void) {
        let trace = LectraPerformanceTrace.begin(.web, "GitHTTPRequest")
        guard let urlStr = body["url"] as? String, let url = URL(string: urlStr) else {
            LectraPerformanceTrace.end(trace)
            reply(["ok": false, "message": "bad url"], nil); return
        }
        let method = (body["method"] as? String) ?? "GET"
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let headers = body["headers"] as? [String: String] {
            for (k, v) in headers where k.lowercased() != "accept-encoding" {
                request.setValue(v, forHTTPHeaderField: k)
            }
        }
        request.setValue("Lectra-git", forHTTPHeaderField: "User-Agent")
        if let b64 = body["bodyB64"] as? String, let data = Data(base64Encoded: b64) {
            request.httpBody = data
        }
        // Inject GitHub auth for GitHub hosts (works for OAuth tokens and PATs
        // over git smart-HTTP via Basic auth).
        if let host = url.host, host == "github.com" || host.hasSuffix(".github.com") || host.hasSuffix(".githubusercontent.com"),
           let token = GitHubAuth.shared.token, !token.isEmpty {
            let cred = "x-access-token:\(token)"
            if let credData = cred.data(using: .utf8) {
                request.setValue("Basic \(credData.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }
        }
        urlSession.dataTask(with: request) { data, response, error in
            if let error {
                DispatchQueue.main.async { reply(["ok": false, "message": error.localizedDescription], nil) }
                LectraPerformanceTrace.end(trace)
                return
            }
            let http = response as? HTTPURLResponse
            var headers: [String: String] = [:]
            for (k, v) in (http?.allHeaderFields ?? [:]) {
                if let ks = k as? String, let vs = v as? String { headers[ks.lowercased()] = vs }
            }
            let payload: [String: Any] = [
                "ok": true,
                "url": urlStr,
                "statusCode": http?.statusCode ?? 0,
                "statusMessage": HTTPURLResponse.localizedString(forStatusCode: http?.statusCode ?? 0),
                "headers": headers,
                "bodyB64": (data ?? Data()).base64EncodedString(),
            ]
            DispatchQueue.main.async { reply(payload, nil) }
            LectraPerformanceTrace.end(trace)
        }.resume()
    }
}

// MARK: - Web view & scheme handler

private final class GitKernelWebView: WKWebView {
    override var canBecomeFirstResponder: Bool { false }
}

/// Serves the bundled isomorphic-git assets over `lectragit://`.
private final class GitSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { task.didFailWithError(URLError(.badURL)); return }
        let name = url.lastPathComponent.isEmpty ? "git_host.html" : url.lastPathComponent
        guard let fileURL = Self.bundledURL(for: name), let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": Self.mimeType(for: name),
                           "Content-Length": String(data.count),
                           "Access-Control-Allow-Origin": "*"])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private static func bundledURL(for name: String) -> URL? {
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        if let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Git") { return url }
        return Bundle.main.url(forResource: base, withExtension: ext)
    }
    private static func mimeType(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "html": return "text/html"
        case "js", "mjs": return "text/javascript"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }
}
