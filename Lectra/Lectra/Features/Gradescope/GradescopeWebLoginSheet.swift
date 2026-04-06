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

    private var technicalDetailsPresentation: TechnicalDetailsPresentation? {
        TechnicalDetailsPresentation.make(
            summary: "Technical details are available for the latest Gradescope web sign-in import attempt.",
            details: debugReport
        )
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: LectraSpacing.md) {
                Text("Gradescope Web Sign-In")
                    .font(LectraTypography.displaySmall)
                    .foregroundColor(.white)

                Text(statusMessage)
                    .font(LectraTypography.body)
                    .foregroundColor(Color.white.opacity(LectraOpacity.prominent))

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

                        LectraHaptics.selection()
                        Task { @MainActor in
                            let result = await onSessionCaptured(cookies, html)
                            if result.errorMessage == nil {
                                LectraHaptics.success()
                                dismiss()
                            } else {
                                isImporting = false
                                statusMessage = "Session import failed: \(result.errorMessage ?? "Unknown error")"
                                debugReport = result.debugReport
                                LectraHaptics.warning()
                            }
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                        .stroke(Color.white.opacity(LectraOpacity.muted), lineWidth: 1)
                )
                .lectraShadow(LectraElevation.low())

                if isImporting {
                    HStack(spacing: LectraSpacing.sm) {
                        ProgressView()
                            .tint(.white)
                        Text("Importing session…")
                            .font(LectraTypography.caption)
                            .foregroundColor(.white.opacity(LectraOpacity.primary))
                    }
                }

                if !isImporting && !lastCookies.isEmpty {
                    Button("Try Import Again") {
                        LectraHaptics.selection()
                        isImporting = true
                        statusMessage = "Retrying session import…"
                        debugReport = nil
                        Task { @MainActor in
                            let result = await onSessionCaptured(lastCookies, lastHTML)
                            if result.errorMessage == nil {
                                LectraHaptics.success()
                                dismiss()
                            } else {
                                isImporting = false
                                statusMessage = "Session import failed: \(result.errorMessage ?? "Unknown error")"
                                debugReport = result.debugReport
                                LectraHaptics.warning()
                            }
                        }
                    }
                    .buttonStyle(LectraSecondaryButtonStyle())
                }

                if let technicalDetailsPresentation {
                    TechnicalDetailsDisclosure(
                        presentation: technicalDetailsPresentation,
                        accessibilityID: "gradescope.webLogin.technicalDetails"
                    )
                }
            }
            .padding(LectraSpacing.lg)
            .background(LectraColor.surfaceElevated.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(LectraColor.accentSoft)
                }
            }
        }
        .onChange(of: statusMessage) { _, newValue in
            guard isImporting || newValue.localizedCaseInsensitiveContains("failed") else { return }
            postAccessibilityAnnouncement(newValue)
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
