import SwiftUI

struct AccountSettingsView: View {
    enum SettingsTab: String, CaseIterable, Identifiable {
        case account = "Account"
        case integrations = "Integrations"
        case cloudBackup = "Cloud & Backup"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .account:
                return "person.crop.circle"
            case .integrations:
                return "link"
            case .cloudBackup:
                return "icloud"
            }
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

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab

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
        onSignOut: @escaping () -> Void
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
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let isCompactLayout = proxy.size.width < 860

                Group {
                    if isCompactLayout {
                        VStack(spacing: 0) {
                            compactHeader

                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 1)

                            detailPane
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .background(Color(hex: 0x0F1115))
                        }
                    } else {
                        HStack(spacing: 0) {
                            sidebar
                                .frame(width: 284)
                                .background(Color(hex: 0x15181E))

                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 1)

                            detailPane
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .background(Color(hex: 0x0F1115))
                        }
                    }
                }
            }
            .frame(idealWidth: 980, maxWidth: 1020, minHeight: 700, idealHeight: 748, maxHeight: 780)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(Color(hex: 0xE84D4D))
                }
            }
        }
        .preferredColorScheme(.dark)
        .lectraSheetPageSizing()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                ProfileAvatarView(
                    avatarURL: avatarURL,
                    fallbackName: userName.isEmpty ? userEmail : userName,
                    size: 56
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(userName)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    if let userEmail, !userEmail.isEmpty {
                        Text(userEmail)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.58))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)

            VStack(spacing: 8) {
                ForEach(SettingsTab.allCases) { tab in
                    settingsTabButton(tab, compact: false)
                }
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 0)

            Text("Only Lectra account, integration, and backup controls live here.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.white.opacity(0.44))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
        }
    }

    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ProfileAvatarView(
                    avatarURL: avatarURL,
                    fallbackName: userName.isEmpty ? userEmail : userName,
                    size: 48
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(userName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    if let userEmail, !userEmail.isEmpty {
                        Text(userEmail)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.58))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(SettingsTab.allCases) { tab in
                        settingsTabButton(tab, compact: true)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .background(Color(hex: 0x15181E))
    }

    private func settingsTabButton(_ tab: SettingsTab, compact: Bool) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 20)

                Text(tab.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                if !compact {
                    Spacer(minLength: 0)
                }
            }
            .foregroundColor(selectedTab == tab ? .white : Color.white.opacity(0.66))
            .padding(.horizontal, 14)
            .frame(minHeight: LectraSizing.minHitTarget)
            .background(selectedTab == tab ? Color(hex: 0x4A222A) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        .accessibilityIdentifier("settings.tab.\(tab.rawValue.replacingOccurrences(of: " ", with: "").lowercased())")
    }

    @ViewBuilder
    private var detailPane: some View {
        switch selectedTab {
        case .account:
            accountTab
        case .integrations:
            IntegrationsSettingsView()
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

    private var accountTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Account")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)

                    Text("This panel only keeps the app-level account details Lectra actually uses.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.66))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 18) {
                        ProfileAvatarView(
                            avatarURL: avatarURL,
                            fallbackName: userName.isEmpty ? userEmail : userName,
                            size: 76
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(userName)
                                .font(.system(size: 25, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(2)

                            if let userEmail, !userEmail.isEmpty {
                                Text(userEmail)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(Color.white.opacity(0.62))
                                    .lineLimit(2)
                            }

                            Text("Signed in to Lectra")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(LectraColor.success)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(LectraColor.success.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Google account details are used for your Lectra session. Integrations and backups are managed in the tabs alongside this one.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)

                        Button(role: .destructive, action: onSignOut) {
                            Label("Sign Out of Lectra", systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(hex: 0xFF8E8E))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color.red.opacity(0.16))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(22)
                .background(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
    }
}

private extension View {
    @ViewBuilder
    func lectraSheetPageSizing() -> some View {
        if #available(iOS 18.0, *) {
            self.presentationSizing(.page)
        } else {
            self
        }
    }
}
