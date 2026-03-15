import SwiftUI

struct CloudBackupSettingsTabView: View {
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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cloud & Backup")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)

                    Text("Control Lectra's explicit iCloud sync and the local backup snapshots used to protect your documents.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.66))
                        .fixedSize(horizontal: false, vertical: true)
                }

                statusCard
                controlsCard
                recoveryCard

                Text("Cloud sync stays off until you turn it on. Manual backup always creates a local snapshot and uses iCloud Drive when it is available.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.56))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Status")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)

                Spacer(minLength: 0)

                Text(isCloudSyncEnabled ? "Sync Enabled" : "Sync Off")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isCloudSyncEnabled ? LectraColor.success : Color(hex: 0xF36B58))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background((isCloudSyncEnabled ? LectraColor.success : Color(hex: 0xF36B58)).opacity(0.12))
                    .clipShape(Capsule())
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 16)],
                alignment: .leading,
                spacing: 16
            ) {
                metric(title: "iCloud", value: isICloudAvailable ? "Available" : "Unavailable")
                metric(title: "Last Sync", value: lastCloudSyncDate.formatted(date: .abbreviated, time: .shortened))
                metric(title: "Last Backup", value: lastBackupDate.formatted(date: .abbreviated, time: .shortened))
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    actionButton(
                        title: isSyncInProgress ? "Syncing…" : "Sync Now",
                        systemImage: "arrow.clockwise",
                        isDisabled: isSyncInProgress,
                        action: onRunCloudSync
                    )

                    actionButton(
                        title: "Backup Now",
                        systemImage: "externaldrive",
                        isDisabled: false,
                        action: onRunManualBackup
                    )
                }

                VStack(spacing: 12) {
                    actionButton(
                        title: isSyncInProgress ? "Syncing…" : "Sync Now",
                        systemImage: "arrow.clockwise",
                        isDisabled: isSyncInProgress,
                        action: onRunCloudSync
                    )

                    actionButton(
                        title: "Backup Now",
                        systemImage: "externaldrive",
                        isDisabled: false,
                        action: onRunManualBackup
                    )
                }
            }
        }
        .padding(22)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recovery Center")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)

                    Text("Restore snapshot copies safely, or replace current local versions when you need a full rollback.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.56))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button("Reload") {
                    onReloadRecoverySnapshots()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: 0xE84D4D))
                .frame(minHeight: LectraSizing.minHitTarget)
                .accessibilityIdentifier("settings.cloud.reloadSnapshots")
            }

            if recoverySnapshots.isEmpty {
                Text("No recovery snapshots yet. Run a manual backup or iCloud sync to populate recovery points.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 12) {
                    ForEach(recoverySnapshots.prefix(6)) { snapshot in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)

                                    Text("\(snapshot.itemCount) document\(snapshot.itemCount == 1 ? "" : "s") in \(snapshot.source)")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Color.white.opacity(0.58))
                                }

                                Spacer(minLength: 0)

                                Text(snapshot.location == .iCloudDrive ? "iCloud Drive" : "On Device")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(snapshot.location == .iCloudDrive ? Color(hex: 0x2E8DFF) : LectraColor.success)
                                    .padding(.horizontal, 10)
                                    .frame(height: 24)
                                    .background((snapshot.location == .iCloudDrive ? Color(hex: 0x2E8DFF) : LectraColor.success).opacity(0.14))
                                    .clipShape(Capsule())
                            }

                            if !snapshot.items.isEmpty {
                                Text(snapshot.items.prefix(3).map(\.title).joined(separator: " • "))
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(Color.white.opacity(0.72))
                                    .lineLimit(2)
                            }

                            HStack(spacing: 10) {
                                snapshotActionButton(title: "Restore Copy") {
                                    onRestoreSnapshotAsCopy(snapshot)
                                }

                                snapshotActionButton(title: "Replace Current") {
                                    onRestoreSnapshotReplacing(snapshot)
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
        .padding(22)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsToggleRow(
                title: "Cloud Sync",
                subtitle: "Explicit opt-in only",
                isOn: isCloudSyncEnabled,
                onToggle: onSetCloudSyncEnabled
            )

            divider

            settingsToggleRow(
                title: "Automatic Backup",
                subtitle: "Create a backup snapshot after successful sync work",
                isOn: isAutoBackupEnabled,
                onToggle: onSetAutoBackupEnabled
            )
        }
        .padding(.horizontal, 22)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color.white.opacity(0.42))

            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func actionButton(
        title: String,
        systemImage: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isDisabled ? Color.white.opacity(0.06) : Color(hex: 0x4A222A))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func snapshotActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: LectraSizing.minHitTarget)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func settingsToggleRow(
        title: String,
        subtitle: String,
        isOn: Bool,
        onToggle: @escaping (Bool) -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.56))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Toggle("", isOn: Binding(get: { isOn }, set: onToggle))
                .labelsHidden()
                .tint(Color(hex: 0x4A222A))
                .accessibilityLabel(title)
                .accessibilityValue(isOn ? "On" : "Off")
        }
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }
}
