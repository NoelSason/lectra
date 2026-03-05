import SwiftUI
import WebKit

struct GradescopeSubmissionWebSheet: View {
    @Environment(\.dismiss) private var dismiss

    let url: URL

    @State private var currentURL: URL?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("Use this page to add group partners and assign pages before final submission.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.72))

                GradescopeSubmissionWebView(url: url, onNavigation: { currentURL = $0 })
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                if let currentURL {
                    Text(currentURL.absoluteString)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.62))
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .background(Color(hex: 0x111214).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(Color(hex: 0xE84D4D))
                }
            }
        }
    }
}

private struct GradescopeSubmissionWebView: UIViewRepresentable {
    let url: URL
    let onNavigation: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        syncSharedCookies(to: webView.configuration.websiteDataStore.httpCookieStore) {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private func syncSharedCookies(to cookieStore: WKHTTPCookieStore, completion: @escaping () -> Void) {
        let cookies = (HTTPCookieStorage.shared.cookies ?? []).filter { cookie in
            cookie.domain.lowercased().contains("gradescope.com")
        }

        guard !cookies.isEmpty else {
            completion()
            return
        }

        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            cookieStore.setCookie(cookie) {
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: GradescopeSubmissionWebView

        init(_ parent: GradescopeSubmissionWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onNavigation(webView.url)
        }
    }
}
