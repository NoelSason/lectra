import Foundation
import WebKit

@MainActor
final class GradescopeSubmissionWebRunnerImpl: NSObject, GradescopeSubmissionWebRunner {
    func runMultipartSubmission(
        pageURL: URL,
        targetURL: URL,
        fields: [String: String],
        fileFieldName: String,
        fileURL: URL,
        headers: [String: String]
    ) async throws -> GSWebRunnerResult {
        let fileData = try Data(contentsOf: fileURL)
        let args: [String: Any] = [
            "targetURL": targetURL.absoluteString,
            "fields": fields,
            "fileFieldName": fileFieldName,
            "fileName": fileURL.lastPathComponent,
            "mimeType": "application/pdf",
            "fileBase64": fileData.base64EncodedString(),
            "headers": sanitizedWebHeaders(headers)
        ]

        let script = """
        const target = targetURL;
        const formFields = fields || {};
        const uploadFieldName = fileFieldName;
        const uploadFileName = fileName || 'submission.pdf';
        const uploadMimeType = mimeType || 'application/pdf';
        const uploadBase64 = fileBase64 || '';
        const requestHeaders = headers || {};

        try {
          function base64ToUint8Array(base64) {
            const binaryString = atob(base64);
            const len = binaryString.length;
            const bytes = new Uint8Array(len);
            for (let i = 0; i < len; i++) {
              bytes[i] = binaryString.charCodeAt(i);
            }
            return bytes;
          }

          const payload = new FormData();
          for (const [key, value] of Object.entries(formFields)) {
            payload.append(key, String(value));
          }

          const bytes = base64ToUint8Array(uploadBase64);
          const blob = new Blob([bytes], { type: uploadMimeType });
          payload.append(uploadFieldName, blob, uploadFileName);

          const response = await fetch(target, {
            method: 'POST',
            credentials: 'include',
            headers: requestHeaders,
            body: payload,
            redirect: 'follow'
          });

          const html = await response.text();
          return {
            statusCode: response.status,
            finalURL: response.url,
            bodyHTML: html,
            jsError: ''
          };
        } catch (error) {
          return {
            statusCode: 0,
            finalURL: target,
            bodyHTML: '',
            jsError: String(error)
          };
        }
        """

        return try await runScript(pageURL: pageURL, script: script, arguments: args)
    }

    /// Submits by scraping the actual form from the loaded DOM and using the page's
    /// own CSRF token and cookies. This mirrors exactly what a user click would do.
    func runDOMFormSubmission(
        pageURL: URL,
        fileURL: URL
    ) async throws -> GSWebRunnerResult {
        let fileData = try Data(contentsOf: fileURL)
        let args: [String: Any] = [
            "fileName": fileURL.lastPathComponent,
            "mimeType": "application/pdf",
            "fileBase64": fileData.base64EncodedString()
        ]

        let script = """
        const uploadFileName = fileName || 'submission.pdf';
        const uploadMimeType = mimeType || 'application/pdf';
        const uploadBase64 = fileBase64 || '';

        try {
          function base64ToUint8Array(base64) {
            const binaryString = atob(base64);
            const len = binaryString.length;
            const bytes = new Uint8Array(len);
            for (let i = 0; i < len; i++) {
              bytes[i] = binaryString.charCodeAt(i);
            }
            return bytes;
          }

          // Find the submission form in the DOM
          const form = document.querySelector('form.js-uploadPDFForm')
                    || document.querySelector('form[action*="submissions"]');
          if (!form) {
            return {
              statusCode: 0,
              finalURL: window.location.href,
              bodyHTML: '',
              jsError: 'No submission form found in DOM'
            };
          }

          // Get the CSRF token from the page itself
          const csrfMeta = document.querySelector('meta[name="csrf-token"]');
          const csrfInput = form.querySelector('input[name="authenticity_token"]');
          const csrfToken = csrfInput
            ? csrfInput.value
            : (csrfMeta ? csrfMeta.content : '');

          // Find the file input field name from the DOM
          const fileInput = form.querySelector('input[type="file"]');
          const fileFieldName = fileInput ? fileInput.name : 'pdf_attachment';

          // Build FormData from the actual DOM form's hidden fields
          const payload = new FormData();
          const hiddenInputs = form.querySelectorAll('input[type="hidden"]');
          for (const inp of hiddenInputs) {
            if (inp.name) payload.append(inp.name, inp.value);
          }

          // Ensure CSRF token is present
          if (csrfToken && !payload.has('authenticity_token')) {
            payload.append('authenticity_token', csrfToken);
          }

          // Append the file
          const bytes = base64ToUint8Array(uploadBase64);
          const blob = new Blob([bytes], { type: uploadMimeType });
          payload.append(fileFieldName, blob, uploadFileName);

          // Append the submit button value
          const submitBtn = form.querySelector('input[type="submit"], button[type="submit"]');
          if (submitBtn && submitBtn.name) {
            payload.append(submitBtn.name, submitBtn.value || 'Upload PDF');
          }

          // Submit to the form's action URL
          const target = form.action || window.location.href;
          const response = await fetch(target, {
            method: 'POST',
            credentials: 'include',
            body: payload,
            redirect: 'follow'
          });

          const html = await response.text();
          return {
            statusCode: response.status,
            finalURL: response.url,
            bodyHTML: html,
            jsError: ''
          };
        } catch (error) {
          return {
            statusCode: 0,
            finalURL: window.location.href,
            bodyHTML: '',
            jsError: String(error)
          };
        }
        """

        return try await runScript(pageURL: pageURL, script: script, arguments: args)
    }

    func runFormSubmission(
        pageURL: URL,
        targetURL: URL,
        fields: [String: String],
        headers: [String: String]
    ) async throws -> GSWebRunnerResult {
        let args: [String: Any] = [
            "targetURL": targetURL.absoluteString,
            "fields": fields,
            "headers": sanitizedWebHeaders(headers)
        ]

        let script = """
        const target = targetURL;
        const formFields = fields || {};
        const requestHeaders = headers || {};
        try {
          const params = new URLSearchParams();
          for (const [key, value] of Object.entries(formFields)) {
            params.append(key, String(value));
          }

          const response = await fetch(target, {
            method: 'POST',
            credentials: 'include',
            headers: requestHeaders,
            body: params,
            redirect: 'follow'
          });

          const html = await response.text();
          return {
            statusCode: response.status,
            finalURL: response.url,
            bodyHTML: html,
            jsError: ''
          };
        } catch (error) {
          return {
            statusCode: 0,
            finalURL: target,
            bodyHTML: '',
            jsError: String(error)
          };
        }
        """

        return try await runScript(pageURL: pageURL, script: script, arguments: args)
    }

    private func runScript(pageURL: URL, script: String, arguments: [String: Any]) async throws -> GSWebRunnerResult {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let navigation = NavigationDelegate()
        webView.navigationDelegate = navigation

        await syncCookies(to: configuration.websiteDataStore.httpCookieStore)

        try await navigation.load(webView: webView, url: pageURL)

        let rawResult: Any
        do {
            rawResult = try await withCheckedThrowingContinuation { continuation in
                webView.callAsyncJavaScript(
                    script,
                    arguments: arguments,
                    in: nil,
                    in: .page
                ) { result in
                    switch result {
                    case .success(let value):
                        continuation.resume(returning: value)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            throw GSError.webRunnerFailed(error.localizedDescription)
        }

        guard let dict = rawResult as? [String: Any] else {
            throw GSError.webRunnerFailed("Unexpected JavaScript result")
        }

        guard let statusCode = dict["statusCode"] as? Int,
              let finalURLRaw = dict["finalURL"] as? String,
              let finalURL = URL(string: finalURLRaw),
              let bodyHTML = dict["bodyHTML"] as? String else {
            throw GSError.webRunnerFailed("Missing expected result fields")
        }

        if let jsError = dict["jsError"] as? String,
           !jsError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw GSError.webRunnerFailed(jsError)
        }

        return GSWebRunnerResult(statusCode: statusCode, finalURL: finalURL, bodyHTML: bodyHTML)
    }

    private func sanitizedWebHeaders(_ headers: [String: String]) -> [String: String] {
        var sanitized: [String: String] = [:]
        for (key, value) in headers {
            let lowered = key.lowercased()
            if lowered == "x-csrf-token" || lowered == "x-requested-with" {
                sanitized[key] = value
                continue
            }
            if lowered == "content-type"
                || lowered == "content-length"
                || lowered == "host"
                || lowered == "origin"
                || lowered == "referer"
                || lowered.hasPrefix("sec-")
                || lowered == "user-agent" {
                continue
            }
        }
        return sanitized
    }

    private func syncCookies(to cookieStore: WKHTTPCookieStore) async {
        let cookies = (HTTPCookieStorage.shared.cookies ?? []).filter { cookie in
            cookie.domain.lowercased().contains("gradescope.com")
        }

        guard !cookies.isEmpty else { return }

        await withCheckedContinuation { continuation in
            let group = DispatchGroup()
            for cookie in cookies {
                group.enter()
                cookieStore.setCookie(cookie) {
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                continuation.resume()
            }
        }
    }

    private final class NavigationDelegate: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, Error>?

        func load(webView: WKWebView, url: URL) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.continuation = continuation
                webView.load(URLRequest(url: url))
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            continuation?.resume()
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
