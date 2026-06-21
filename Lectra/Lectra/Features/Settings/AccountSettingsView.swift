import SwiftUI

/// Settings surface for the Lectra workspace. Rebuilt to fill its sheet
/// cleanly: a fixed-width sidebar (or a horizontal tab strip when compact) and
/// a detail pane that always stretches to the full bounds — no fixed content
/// frame fighting the presentation size.
struct AccountSettingsView: View {
    enum SettingsTab: String, CaseIterable, Identifiable {
        case account = "Account"
        case intelligence = "Intelligence"
        case cloudBackup = "Cloud & Backup"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .account:      return "person.crop.circle"
            case .intelligence: return "sparkles"
            case .cloudBackup:  return "icloud"
            }
        }

        var accessibilityIdentifier: String {
            "settings.tab.\(rawValue.replacingOccurrences(of: " ", with: "").lowercased())"
        }
    }

    let userName: String
    let userEmail: String?
    let avatarURL: String?
    let isCloudSyncEnabled: Bool
    let isAutoBackupEnabled: Bool
    let isICloudAvailable: Bool
    let isSyncInProgress: Bool
    let lastCloudSyncDate: Date
    let lastBackupDate: Date
    let recoverySnapshots: [RecoverySnapshot]
    let onSetCloudSyncEnabled: (Bool) -> Void
    let onSetAutoBackupEnabled: (Bool) -> Void
    let onRunCloudSync: () -> Void
    let onRunManualBackup: () -> Void
    let onReloadRecoverySnapshots: () -> Void
    let onRestoreSnapshotAsCopy: (RecoverySnapshot) -> Void
    let onRestoreSnapshotReplacing: (RecoverySnapshot) -> Void
    let onSignOut: () -> Void
    let onDeleteAccount: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: SettingsTab
    @State private var showDeleteAccountConfirm = false

    init(
        initialTab: SettingsTab = .account,
        userName: String,
        userEmail: String? = nil,
        avatarURL: String? = nil,
        isCloudSyncEnabled: Bool,
        isAutoBackupEnabled: Bool,
        isICloudAvailable: Bool,
        isSyncInProgress: Bool,
        lastCloudSyncDate: Date,
        lastBackupDate: Date,
        recoverySnapshots: [RecoverySnapshot],
        onSetCloudSyncEnabled: @escaping (Bool) -> Void,
        onSetAutoBackupEnabled: @escaping (Bool) -> Void,
        onRunCloudSync: @escaping () -> Void,
        onRunManualBackup: @escaping () -> Void,
        onReloadRecoverySnapshots: @escaping () -> Void,
        onRestoreSnapshotAsCopy: @escaping (RecoverySnapshot) -> Void,
        onRestoreSnapshotReplacing: @escaping (RecoverySnapshot) -> Void,
        onSignOut: @escaping () -> Void,
        onDeleteAccount: @escaping () -> Void
    ) {
        self.userName = userName
        self.userEmail = userEmail
        self.avatarURL = avatarURL
        self.isCloudSyncEnabled = isCloudSyncEnabled
        self.isAutoBackupEnabled = isAutoBackupEnabled
        self.isICloudAvailable = isICloudAvailable
        self.isSyncInProgress = isSyncInProgress
        self.lastCloudSyncDate = lastCloudSyncDate
        self.lastBackupDate = lastBackupDate
        self.recoverySnapshots = recoverySnapshots
        self.onSetCloudSyncEnabled = onSetCloudSyncEnabled
        self.onSetAutoBackupEnabled = onSetAutoBackupEnabled
        self.onRunCloudSync = onRunCloudSync
        self.onRunManualBackup = onRunManualBackup
        self.onReloadRecoverySnapshots = onReloadRecoverySnapshots
        self.onRestoreSnapshotAsCopy = onRestoreSnapshotAsCopy
        self.onRestoreSnapshotReplacing = onRestoreSnapshotReplacing
        self.onSignOut = onSignOut
        self.onDeleteAccount = onDeleteAccount
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let isCompact = proxy.size.width < 720

                if isCompact {
                    VStack(spacing: 0) {
                        compactHeader
                        horizontalDivider
                        detailPane
                    }
                } else {
                    HStack(spacing: 0) {
                        sidebar
                            .frame(width: 288)
                            .frame(maxHeight: .infinity)
                            .background(LectraColor.sidebarBackground)

                        verticalDivider

                        detailPane
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LectraColor.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        LectraHaptics.selection()
                        dismiss()
                    }
                    .font(LectraTypography.bodyEmphasis)
                    .foregroundColor(LectraColor.accentSoft)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .animation(reduceMotion ? nil : LectraMotion.tabSwitch, value: selectedTab)
    }

    // MARK: - Dividers

    private var verticalDivider: some View {
        Rectangle()
            .fill(LectraColor.sidebarDivider)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    private var horizontalDivider: some View {
        Rectangle()
            .fill(LectraColor.sidebarDivider)
            .frame(height: 1)
    }

    // MARK: - Sidebar (regular width)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            profileBlock

            VStack(spacing: 6) {
                ForEach(SettingsTab.allCases) { tab in
                    sidebarTabButton(tab)
                }
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 0)

            Text("Lectra workspace account, intelligence, and backup controls.")
                .font(LectraTypography.captionMedium)
                .foregroundColor(LectraColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileAvatarView(
                avatarURL: avatarURL,
                fallbackName: userName.isEmpty ? userEmail : userName,
                size: 56
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(userName)
                    .font(LectraTypography.title)
                    .foregroundColor(LectraColor.textPrimary)
                    .lineLimit(2)

                if let userEmail, !userEmail.isEmpty {
                    Text(userEmail)
                        .font(LectraTypography.captionMedium)
                        .foregroundColor(LectraColor.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
    }

    private func sidebarTabButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            LectraHaptics.selection()
            selectedTab = tab
        } label: {
            HStack(spacing: 12) {
                tabIcon(tab, isSelected: isSelected)

                Text(tab.rawValue)
                    .font(LectraTypography.bodyEmphasis)
                    .foregroundColor(isSelected ? LectraColor.textPrimary : LectraColor.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                    .fill(isSelected ? LectraColor.sidebarSelection : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                    .stroke(isSelected ? LectraColor.accent.opacity(0.28) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(tab.accessibilityIdentifier)
    }

    // MARK: - Compact header (narrow width)

    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ProfileAvatarView(
                    avatarURL: avatarURL,
                    fallbackName: userName.isEmpty ? userEmail : userName,
                    size: 48
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(userName)
                        .font(LectraTypography.title)
                        .foregroundColor(LectraColor.textPrimary)
                        .lineLimit(1)

                    if let userEmail, !userEmail.isEmpty {
                        Text(userEmail)
                            .font(LectraTypography.captionMedium)
                            .foregroundColor(LectraColor.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SettingsTab.allCases) { tab in
                        compactTabChip(tab)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LectraColor.sidebarBackground)
    }

    private func compactTabChip(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            LectraHaptics.selection()
            selectedTab = tab
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(tab.rawValue)
                    .font(LectraTypography.bodyEmphasis)
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? LectraColor.textPrimary : LectraColor.textSecondary)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                    .fill(isSelected ? LectraColor.sidebarSelection : LectraColor.paper.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous)
                    .stroke(isSelected ? LectraColor.accent.opacity(0.28) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: LectraRadius.element, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(tab.accessibilityIdentifier)
    }

    private func tabIcon(_ tab: SettingsTab, isSelected: Bool) -> some View {
        Image(systemName: tab.systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(isSelected ? LectraColor.accentSoft : LectraColor.textSecondary)
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: LectraRadius.button, style: .continuous)
                    .fill(isSelected ? LectraColor.accent.opacity(0.16) : LectraColor.paper.opacity(0.04))
            )
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        Group {
            switch selectedTab {
            case .account:
                accountTab
            case .intelligence:
                IntelligenceSettingsView()
            case .cloudBackup:
                CloudBackupSettingsTabView(
                    isCloudSyncEnabled: isCloudSyncEnabled,
                    isAutoBackupEnabled: isAutoBackupEnabled,
                    isICloudAvailable: isICloudAvailable,
                    isSyncInProgress: isSyncInProgress,
                    lastCloudSyncDate: lastCloudSyncDate,
                    lastBackupDate: lastBackupDate,
                    recoverySnapshots: recoverySnapshots,
                    onSetCloudSyncEnabled: onSetCloudSyncEnabled,
                    onSetAutoBackupEnabled: onSetAutoBackupEnabled,
                    onRunCloudSync: onRunCloudSync,
                    onRunManualBackup: onRunManualBackup,
                    onReloadRecoverySnapshots: onReloadRecoverySnapshots,
                    onRestoreSnapshotAsCopy: onRestoreSnapshotAsCopy,
                    onRestoreSnapshotReplacing: onRestoreSnapshotReplacing
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LectraColor.background)
        .id(selectedTab)
        .transition(reduceMotion ? .opacity : LectraMotion.cardTransition)
    }

    private var accountTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Account")
                        .font(LectraTypography.displaySmall)
                        .foregroundColor(LectraColor.textPrimary)

                    Text("Lectra identity and session details.")
                        .font(LectraTypography.body)
                        .foregroundColor(LectraColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 18) {
                        ProfileAvatarView(
                            avatarURL: avatarURL,
                            fallbackName: userName.isEmpty ? userEmail : userName,
                            size: 72
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(userName)
                                .font(LectraTypography.title)
                                .foregroundColor(LectraColor.textPrimary)
                                .lineLimit(2)

                            if let userEmail, !userEmail.isEmpty {
                                Text(userEmail)
                                    .font(LectraTypography.body)
                                    .foregroundColor(LectraColor.textSecondary)
                                    .lineLimit(2)
                            }

                            LectraStatusBadge(title: "Signed in to Lectra", color: LectraColor.accentSoft)
                                .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your account details are used for this Lectra workspace session.")
                            .font(LectraTypography.body)
                            .foregroundColor(LectraColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(role: .destructive) {
                            LectraHaptics.warning()
                            onSignOut()
                        } label: {
                            Label("Sign Out of Lectra", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .buttonStyle(LectraDestructiveButtonStyle())
                    }
                }
                .padding(22)
                .background(panelBackground)

                privacyAndDeletionPanel
            }
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
        .alert("Delete Account?", isPresented: $showDeleteAccountConfirm) {
            Button("Delete Account", role: .destructive) { onDeleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your Lectra account along with all synced documents, notes, and cloud backups. This cannot be undone.")
        }
    }

    private var privacyAndDeletionPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Privacy & Data")
                    .font(LectraTypography.title)
                    .foregroundColor(LectraColor.textPrimary)

                HStack(spacing: 20) {
                    Link(destination: LectraLinks.privacyPolicy) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                            .font(LectraTypography.body)
                            .foregroundColor(LectraColor.accentSoft)
                    }
                    .accessibilityIdentifier("settings.account.privacy")

                    Link(destination: LectraLinks.support) {
                        Label("Support", systemImage: "questionmark.circle")
                            .font(LectraTypography.body)
                            .foregroundColor(LectraColor.accentSoft)
                    }
                    .accessibilityIdentifier("settings.account.support")
                }
            }

            Divider().overlay(LectraColor.edgeStroke)

            VStack(alignment: .leading, spacing: 12) {
                Text("Deleting your account removes your Lectra identity and all data stored on our servers. Documents kept only on this iPad are removed when you sign out.")
                    .font(LectraTypography.body)
                    .foregroundColor(LectraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(role: .destructive) {
                    LectraHaptics.warning()
                    showDeleteAccountConfirm = true
                } label: {
                    Label("Delete Account", systemImage: "trash")
                }
                .buttonStyle(LectraDestructiveButtonStyle())
                .accessibilityIdentifier("settings.account.delete")
            }
        }
        .padding(22)
        .background(panelBackground)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
            .fill(LectraColor.surfaceElevated.opacity(0.90))
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                    .fill(LectraGradient.spotlight.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
            .lectraShadow(LectraElevation.low())
    }
}
