import SwiftUI

struct IntegrationsSettingsView: View {
    @EnvironmentObject private var gradescopeManager: GradescopeManager

    @State private var integrations = IntegrationStatusSnapshot.placeholderStates
    @State private var isRefreshing = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    LazyVStack(spacing: 16) {
                        ForEach(integrations) { integration in
                            IntegrationStatusCard(
                                integration: integration,
                                referenceDate: timeline.date
                            )
                        }
                    }

                    Text("New providers will show up here as Lectra adds them.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.58))
                }
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
            }
        }
        .task {
            await refreshStatuses()
        }
        .onChange(of: gradescopeManager.isAuthenticated) { _, _ in
            Task {
                await refreshStatuses()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lectraCanvasSessionUpdated)) { _ in
            Task {
                await refreshStatuses()
            }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                headerCopy

                Spacer(minLength: 0)

                refreshButton
            }

            VStack(alignment: .leading, spacing: 16) {
                headerCopy
                refreshButton
            }
        }
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Integrations")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)

            Text("Track which external services are connected, how long those sessions should last, and when Lectra will need you to sign in again.")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var refreshButton: some View {
        Button {
            Task {
                await refreshStatuses()
            }
        } label: {
            Label(isRefreshing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
    }

    @MainActor
    private func refreshStatuses() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        integrations = IntegrationStatusSnapshot.placeholderStates
        defer { isRefreshing = false }

        integrations = [
            await canvasSnapshot(),
            gradescopeSnapshot()
        ]
    }

    private func canvasSnapshot() async -> IntegrationStatusSnapshot {
        let storedCookies = await CanvasCookieStore.loadMergedSession()
        let preferredCookies = preferredAuthCookies(from: storedCookies)
        let activeCookies = preferredCookies.filter { storedCookie in
            guard let expiresAt = storedCookie.cookie.expiresDate else { return true }
            return expiresAt > Date()
        }

        guard !activeCookies.isEmpty else {
            return IntegrationStatusSnapshot(
                id: "canvas",
                title: "Canvas",
                subtitle: "Imports course files through the in-app downloader",
                systemImage: "graduationcap.fill",
                tint: Color(hex: 0xF36B58),
                connectionState: .disconnected,
                expiry: nil,
                note: "Connect Canvas by opening a course file from Course Brain and completing the web sign-in flow if prompted."
            )
        }

        let providerExpiry = activeCookies
            .filter { !$0.usesSyntheticExpiry }
            .compactMap(\.cookie.expiresDate)
            .min()

        let localCacheExpiry = activeCookies
            .filter(\.usesSyntheticExpiry)
            .compactMap(\.cookie.expiresDate)
            .min()

        let expiry: IntegrationExpiry
        let note: String
        if let providerExpiry {
            expiry = .fixed(date: providerExpiry, source: .provider)
            note = "Canvas exposed a cookie expiration for the current session."
        } else if let localCacheExpiry {
            expiry = .fixed(date: localCacheExpiry, source: .localCache)
            note = "Lectra locally keeps Canvas session cookies for up to 30 days. Canvas can still require sign-in earlier."
        } else {
            expiry = .noFixedExpiration
            note = "Canvas is signed in through Lectra's embedded browser session, but the provider did not expose a fixed sign-out time."
        }

        return IntegrationStatusSnapshot(
            id: "canvas",
            title: "Canvas",
            subtitle: "Imports course files through the in-app downloader",
            systemImage: "graduationcap.fill",
            tint: Color(hex: 0xF36B58),
            connectionState: .connected,
            expiry: expiry,
            note: note
        )
    }

    private func gradescopeSnapshot() -> IntegrationStatusSnapshot {
        guard gradescopeManager.isAuthenticated else {
            return IntegrationStatusSnapshot(
                id: "gradescope",
                title: "Gradescope",
                subtitle: "Syncs assignments and imports templates",
                systemImage: "checkmark.seal.fill",
                tint: Color(hex: 0x2BA98E),
                connectionState: .disconnected,
                expiry: nil,
                note: "Connect Gradescope from Lectra's Gradescope workspace."
            )
        }

        let expiry: IntegrationExpiry = if let expirationDate = gradescopeManager.sessionExpirationDate {
            .fixed(date: expirationDate, source: .provider)
        } else {
            .noFixedExpiration
        }

        let note: String = if gradescopeManager.sessionExpirationDate != nil {
            "Gradescope exposed a cookie expiration for the current session."
        } else {
            "No fixed Gradescope sign-out time was exposed in the imported session."
        }

        return IntegrationStatusSnapshot(
            id: "gradescope",
            title: "Gradescope",
            subtitle: "Syncs assignments and imports templates",
            systemImage: "checkmark.seal.fill",
            tint: Color(hex: 0x2BA98E),
            connectionState: .connected,
            expiry: expiry,
            note: note
        )
    }

    private func preferredAuthCookies(from storedCookies: [CanvasCookieStore.StoredCookie]) -> [CanvasCookieStore.StoredCookie] {
        let authLikeCookies = storedCookies.filter { storedCookie in
            let cookieName = storedCookie.cookie.name.lowercased()
            return cookieName.contains("session")
                || cookieName.contains("auth")
                || cookieName.contains("remember")
                || cookieName.contains("token")
                || cookieName.contains("csrf")
                || cookieName.contains("sso")
        }

        if authLikeCookies.isEmpty {
            return storedCookies
        }

        return authLikeCookies
    }
}

private struct IntegrationStatusCard: View {
    let integration: IntegrationStatusSnapshot
    let referenceDate: Date

    private var displayedState: IntegrationDisplayState {
        if case .connected = integration.connectionState,
           case .fixed(let date, _) = integration.expiry,
           date <= referenceDate {
            return .expired
        }
        return IntegrationDisplayState(from: integration.connectionState)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(integration.tint.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: integration.systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(integration.tint)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(integration.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    Text(integration.subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer(minLength: 0)

                StatusBadge(state: displayedState)
            }

            VStack(alignment: .leading, spacing: 10) {
                LabeledStatusRow(
                    label: "Status",
                    value: displayedState.statusLabel,
                    emphasisColor: displayedState.statusColor
                )

                if let expirySummary = integration.expirySummary(referenceDate: referenceDate) {
                    LabeledStatusRow(
                        label: "Access",
                        value: expirySummary,
                        emphasisColor: Color.white.opacity(0.86)
                    )
                }

                if let absoluteExpiry = integration.absoluteExpiryText {
                    LabeledStatusRow(
                        label: "Ends",
                        value: absoluteExpiry,
                        emphasisColor: Color.white.opacity(0.68)
                    )
                }

                Text(integration.note)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.54))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusBadge: View {
    let state: IntegrationDisplayState

    var body: some View {
        Text(state.statusLabel)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(state.statusColor)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(state.statusColor.opacity(0.12))
            .clipShape(Capsule())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
    }
}

private struct LabeledStatusRow: View {
    let label: String
    let value: String
    let emphasisColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color.white.opacity(0.42))
                .frame(width: 62, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(emphasisColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct IntegrationStatusSnapshot: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let connectionState: IntegrationConnectionState
    let expiry: IntegrationExpiry?
    let note: String

    static let placeholderStates: [IntegrationStatusSnapshot] = [
        IntegrationStatusSnapshot(
            id: "canvas",
            title: "Canvas",
            subtitle: "Checking connection",
            systemImage: "graduationcap.fill",
            tint: Color(hex: 0xF36B58),
            connectionState: .checking,
            expiry: nil,
            note: "Reading Lectra's live and saved Canvas sessions."
        ),
        IntegrationStatusSnapshot(
            id: "gradescope",
            title: "Gradescope",
            subtitle: "Checking connection",
            systemImage: "checkmark.seal.fill",
            tint: Color(hex: 0x2BA98E),
            connectionState: .checking,
            expiry: nil,
            note: "Reading the current Gradescope session."
        )
    ]

    var absoluteExpiryText: String? {
        guard case .fixed(let date, _) = expiry else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    func expirySummary(referenceDate: Date) -> String? {
        switch expiry {
        case .fixed(let date, let source):
            guard date > referenceDate else {
                return source == .provider ? "Session expired" : "Local cache expired"
            }
            let duration = Self.countdownString(until: date, from: referenceDate)
            switch source {
            case .provider:
                return "Reauthentication in \(duration)"
            case .localCache:
                return "Local session cache for \(duration)"
            }
        case .noFixedExpiration:
            return "No fixed sign-out time exposed"
        case nil:
            return nil
        }
    }

    private static func countdownString(until date: Date, from referenceDate: Date) -> String {
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: referenceDate, to: date)
        let days = max(components.day ?? 0, 0)
        let hours = max(components.hour ?? 0, 0)
        let minutes = max(components.minute ?? 0, 0)

        if days > 0 {
            return "\(days)d \(max(hours, 0))h"
        }
        if hours > 0 {
            return "\(hours)h \(max(minutes, 0))m"
        }
        return "\(max(minutes, 1))m"
    }
}

private enum IntegrationConnectionState {
    case checking
    case connected
    case disconnected
}

private enum IntegrationDisplayState {
    case checking
    case connected
    case disconnected
    case expired

    init(from baseState: IntegrationConnectionState) {
        switch baseState {
        case .checking:
            self = .checking
        case .connected:
            self = .connected
        case .disconnected:
            self = .disconnected
        }
    }

    var statusLabel: String {
        switch self {
        case .checking:
            return "Checking"
        case .connected:
            return "Signed In"
        case .disconnected:
            return "Not Connected"
        case .expired:
            return "Expired"
        }
    }

    var statusColor: Color {
        switch self {
        case .checking:
            return Color(hex: 0xFFB44B)
        case .connected:
            return LectraColor.success
        case .disconnected:
            return Color(hex: 0xF36B58)
        case .expired:
            return Color(hex: 0xFFB44B)
        }
    }
}

private enum IntegrationExpiry {
    case fixed(date: Date, source: ExpirySource)
    case noFixedExpiration
}

private enum ExpirySource {
    case provider
    case localCache
}
