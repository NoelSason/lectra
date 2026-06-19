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

                    Text("Canvas and Gradescope connections appear here.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(LectraColor.textTertiary)
                }
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
            }
        }
        .background {
            LectraColor.background.ignoresSafeArea()
            LectraGradient.appBackdrop.opacity(0.55).ignoresSafeArea()
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
                .font(LectraTypography.displaySmall)
                .foregroundColor(LectraColor.textPrimary)

            Text("Canvas and Gradescope sessions, cached access, and renewal timing.")
                .font(LectraTypography.body)
                .foregroundColor(LectraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var refreshButton: some View {
        Button {
            LectraHaptics.selection()
            Task {
                await refreshStatuses()
            }
        } label: {
            Label(isRefreshing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
        }
        .buttonStyle(LectraSecondaryButtonStyle())
        .disabled(isRefreshing)
        .accessibilityIdentifier("settings.integrations.refresh")
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
                tint: LectraColor.accentSoft,
                connectionState: .disconnected,
                expiry: nil,
                note: "Connect Canvas from Course Brain when a course file needs web sign-in."
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
            note = "Canvascope keeps Canvas session cookies locally for up to 30 days. Canvas can still require sign-in earlier."
        } else {
            expiry = .noFixedExpiration
            note = "Canvas is signed in through the embedded browser session, but the provider did not expose a fixed sign-out time."
        }

        return IntegrationStatusSnapshot(
            id: "canvas",
            title: "Canvas",
            subtitle: "Imports course files through the in-app downloader",
            systemImage: "graduationcap.fill",
            tint: LectraColor.accentSoft,
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
                tint: LectraColor.accentCool,
                connectionState: .disconnected,
                expiry: nil,
                note: "Connect Gradescope from the Gradescope workspace."
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
            tint: LectraColor.accentCool,
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
                        .font(LectraTypography.title)
                        .foregroundColor(integration.tint)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(integration.title)
                        .font(LectraTypography.title)
                        .foregroundColor(LectraColor.textPrimary)
                        .lineLimit(2)

                    Text(integration.subtitle)
                        .font(LectraTypography.body)
                        .foregroundColor(LectraColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer(minLength: 0)

                LectraStatusBadge(title: displayedState.statusLabel, color: displayedState.statusColor)
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
                        emphasisColor: LectraColor.textPrimary
                    )
                }

                if let absoluteExpiry = integration.absoluteExpiryText {
                    LabeledStatusRow(
                        label: "Ends",
                        value: absoluteExpiry,
                        emphasisColor: LectraColor.textSecondary
                    )
                }

                Text(integration.note)
                    .font(LectraTypography.captionMedium)
                    .foregroundColor(LectraColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .background(integrationCardBackground)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(integration.title). \(displayedState.statusLabel). \(integration.note)")
    }

    private var integrationCardBackground: some View {
        RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
            .fill(LectraColor.surfaceElevated.opacity(0.88))
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                    .fill(LectraGradient.spotlight.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
            .lectraShadow(LectraElevation.low())
    }
}

private struct LabeledStatusRow: View {
    let label: String
    let value: String
    let emphasisColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(LectraTypography.caption)
                .foregroundColor(LectraColor.textTertiary)
                .frame(width: 62, alignment: .leading)

            Text(value)
                .font(LectraTypography.bodyEmphasis)
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
            tint: LectraColor.accentSoft,
            connectionState: .checking,
            expiry: nil,
            note: "Reading Canvascope workspace Canvas sessions."
        ),
        IntegrationStatusSnapshot(
            id: "gradescope",
            title: "Gradescope",
            subtitle: "Checking connection",
            systemImage: "checkmark.seal.fill",
            tint: LectraColor.accentCool,
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
            return LectraColor.warning
        case .connected:
            return LectraColor.accentSoft
        case .disconnected:
            return LectraColor.paperMuted
        case .expired:
            return LectraColor.warning
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
