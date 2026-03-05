import SwiftUI
import WebKit
import UIKit

struct GradescopeWebLoginSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var statusMessage = "Sign in to Gradescope in the web view. We will import your session automatically."
    @State private var isImporting = false
    @State private var lastCookies: [HTTPCookie] = []
    @State private var lastHTML: String?
    @State private var debugReport: String?

    let onSessionCaptured: ([HTTPCookie], String?) async -> (errorMessage: String?, debugReport: String?)

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Gradescope Web Sign-In")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)

                Text(statusMessage)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.74))

                GradescopeWebSessionView(
                    onPageLoaded: { url in
                        if let url {
                            statusMessage = "Current page: \(url.host ?? "gradescope.com")\(url.path)"
                        }
                    },
                    onAuthenticatedSessionDetected: { cookies, html in
                        lastCookies = cookies
                        lastHTML = html
                        guard !isImporting else { return }
                        isImporting = true
                        statusMessage = "Authenticated session detected. Importing into Lectra…"
                        debugReport = nil

                        Task { @MainActor in
                            let result = await onSessionCaptured(cookies, html)
                            if result.errorMessage == nil {
                                dismiss()
                            } else {
                                isImporting = false
                                statusMessage = "Session import failed: \(result.errorMessage ?? "Unknown error")"
                                debugReport = result.debugReport
                            }
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

                if isImporting {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text("Importing session…")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                if !isImporting && !lastCookies.isEmpty {
                    Button("Try Import Again") {
                        isImporting = true
                        statusMessage = "Retrying session import…"
                        debugReport = nil
                        Task { @MainActor in
                            let result = await onSessionCaptured(lastCookies, lastHTML)
                            if result.errorMessage == nil {
                                dismiss()
                            } else {
                                isImporting = false
                                statusMessage = "Session import failed: \(result.errorMessage ?? "Unknown error")"
                                debugReport = result.debugReport
                            }
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if let debugReport {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Import Debug Report")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                            Spacer(minLength: 0)
                            Button("Copy") {
                                UIPasteboard.general.string = debugReport
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: 0xE84D4D))
                        }

                        ScrollView {
                            Text(debugReport)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundColor(.white.opacity(0.75))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 110, maxHeight: 190)
                        .padding(8)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .padding(16)
            .background(Color(hex: 0x111214).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Color(hex: 0xE84D4D))
                }
            }
        }
    }
}

private struct GradescopeWebSessionView: UIViewRepresentable {
    let onPageLoaded: (URL?) -> Void
    let onAuthenticatedSessionDetected: ([HTTPCookie], String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        if let loginURL = URL(string: "https://www.gradescope.com/login") {
            webView.load(URLRequest(url: loginURL))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: GradescopeWebSessionView

        init(_ parent: GradescopeWebSessionView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let pageURL = webView.url
            parent.onPageLoaded(pageURL)

            webView.evaluateJavaScript("document.documentElement.outerHTML.toString()") { [weak self, weak webView] result, _ in
                guard let self, let webView else { return }
                let html = result as? String

                guard self.isAuthenticatedGradescopePage(url: pageURL, html: html) else { return }

                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    let hasSessionCookie = cookies.contains {
                        $0.name == "_gradescope_session"
                        && $0.domain.lowercased().contains("gradescope.com")
                    }
                    guard hasSessionCookie else { return }
                    self.parent.onAuthenticatedSessionDetected(cookies, html)
                }
            }
        }

        private func isAuthenticatedGradescopePage(url: URL?, html: String?) -> Bool {
            guard let url else { return false }

            let host = (url.host ?? "").lowercased()
            guard host.contains("gradescope.com") else { return false }

            let path = url.path.lowercased()
            guard let html else { return false }
            let normalized = html.lowercased()

            let hasAuthSignals =
                normalized.contains("coursebox--shortname")
                || normalized.contains("href=\"/logout\"")
                || normalized.contains("student courses")
                || normalized.contains("instructor courses")
                || normalized.contains("name=\"csrf-token\"")
                || normalized.contains("/sign_out")

            if (path.hasPrefix("/account") || path.hasPrefix("/courses")) && hasAuthSignals {
                return true
            }

            if normalized.contains("coursebox--shortname") { return true }
            if normalized.contains("href=\"/logout\"") { return true }
            if normalized.contains("student courses") || normalized.contains("instructor courses") { return true }

            return false
        }
    }
}
