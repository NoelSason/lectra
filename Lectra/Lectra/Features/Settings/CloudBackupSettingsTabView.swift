import SwiftUI

struct CloudBackupSettingsTabView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            VStack(alignment: .leading, spacing: LectraSpacing.lg) {
                hero
                statusCard
                controlsCard
                recoveryCard

                Text("Cloud sync stays off until you turn it on. Manual backup always creates a local snapshot and uses iCloud Drive when it is available.")
                    .font(LectraTypography.captionMedium)
                    .foregroundColor(Color.white.opacity(LectraOpacity.prominent))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LectraSpacing.xl)
        }
        .background(LectraGradient.appBackdrop.ignoresSafeArea())
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: LectraSpacing.md) {
            LectraStatusBadge(
                title: isCloudSyncEnabled ? "Sync Enabled" : "Sync Off",
                color: isCloudSyncEnabled ? LectraColor.info : LectraColor.canvasTint,
                size: .large
            )

            Text("Cloud & Backup")
                .font(LectraTypography.displaySmall)
                .foregroundColor(.white)

            Text("Control Lectra's explicit iCloud sync and the local recovery snapshots that protect your documents when a save or upload needs a second chance.")
                .font(LectraTypography.body)
                .foregroundColor(Color.white.opacity(LectraOpacity.prominent))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(LectraSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LectraRadius.hero, style: .continuous)
                .fill(LectraColor.surfaceElevated.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: LectraRadius.hero, style: .continuous)
                        .fill(LectraGradient.spotlight.opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LectraRadius.hero, style: .continuous)
                        .stroke(Color.white.opacity(LectraOpacity.subtle), lineWidth: 1)
                )
        )
        .lectraShadow(LectraElevation.medium())
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: LectraSpacing.md) {
            HStack(spacing: LectraSpacing.md) {
                VStack(alignment: .leading, spacing: LectraSpacing.xs) {
                    Text("Status")
                        .font(LectraTypography.title)
                        .foregroundColor(.white)

                    Text("Check iCloud availability, recent sync activity, and your latest local protection point.")
                        .font(LectraTypography.captionMedium)
                        .foregroundColor(Color.white.opacity(LectraOpacity.prominent))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                LectraStatusBadge(
                    title: isCloudSyncEnabled ? "Sync Enabled" : "Sync Off",
                    color: isCloudSyncEnabled ? LectraColor.success : LectraColor.canvasTint
                )
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: LectraSpacing.md)],
                alignment: .leading,
                spacing: LectraSpacing.md
            ) {
                metric(title: "iCloud", value: isICloudAvailable ? "Available" : "Unavailable")
                metric(title: "Last Sync", value: lastCloudSyncDate.formatted(date: .abbreviated, time: .shortened))
                metric(title: "Last Backup", value: lastBackupDate.formatted(date: .abbreviated, time: .shortened))
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: LectraSpacing.sm) {
                    actionButton(
                        title: isSyncInProgress ? "Syncing…" : "Sync Now",
                        systemImage: "arrow.clockwise",
                        style: .primary,
                        isDisabled: isSyncInProgress,
                        action: {
                            LectraHaptics.tap()
                            onRunCloudSync()
                        }
                    )

                    actionButton(
                        title: "Backup Now",
                        systemImage: "externaldrive.badge.icloud",
                        style: .secondary,
                        isDisabled: false,
                        action: {
                            LectraHaptics.tap()
                            onRunManualBackup()
                        }
                    )
                }

                VStack(spacing: LectraSpacing.sm) {
                    actionButton(
                        title: isSyncInProgress ? "Syncing…" : "Sync Now",
                        systemImage: "arrow.clockwise",
                        style: .primary,
                        isDisabled: isSyncInProgress,
                        action: {
                            LectraHaptics.tap()
                            onRunCloudSync()
                        }
                    )

                    actionButton(
                        title: "Backup Now",
                        systemImage: "externaldrive.badge.icloud",
                        style: .secondary,
                        isDisabled: false,
                        action: {
                            LectraHaptics.tap()
                            onRunManualBackup()
                        }
                    )
                }
            }
        }
        .padding(LectraSpacing.lg)
        .lectraCard(cornerRadius: LectraRadius.panel)
    }

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: LectraSpacing.md) {
            HStack(alignment: .top, spacing: LectraSpacing.md) {
                VStack(alignment: .leading, spacing: LectraSpacing.xs) {
                    Text("Recovery Center")
                        .font(LectraTypography.title)
                        .foregroundColor(.white)

                    Text("Restore a snapshot as a safe copy, or replace the current local version when you need a full rollback.")
                        .font(LectraTypography.captionMedium)
                        .foregroundColor(Color.white.opacity(LectraOpacity.prominent))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button("Reload") {
                    LectraHaptics.selection()
                    onReloadRecoverySnapshots()
                }
                .buttonStyle(LectraSecondaryButtonStyle())
                .accessibilityIdentifier("settings.cloud.reloadSnapshots")
            }

            if recoverySnapshots.isEmpty {
                VStack(alignment: .leading, spacing: LectraSpacing.sm) {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(LectraTypography.title)
                        .foregroundColor(LectraColor.info)

                    Text("No recovery snapshots yet.")
                        .font(LectraTypography.headlineMedium)
                        .foregroundColor(.white)

                    Text("Run a manual backup or complete an iCloud sync to start building recovery points.")
                        .font(LectraTypography.body)
                        .foregroundColor(Color.white.opacity(LectraOpacity.prominent))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(LectraSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(LectraOpacity.faint))
                .overlay(
                    RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous)
                        .stroke(Color.white.opacity(LectraOpacity.subtle), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous))
            } else {
                VStack(spacing: LectraSpacing.sm) {
                    ForEach(recoverySnapshots.prefix(6)) { snapshot in
                        snapshotRow(snapshot)
                            .transition(reduceMotion ? .opacity : LectraMotion.cardTransition)
                    }
                }
                .animation(reduceMotion ? nil : LectraMotion.tabSwitch, value: recoverySnapshots.count)
            }
        }
        .padding(LectraSpacing.lg)
        .lectraCard(cornerRadius: LectraRadius.panel)
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsToggleRow(
                title: "Cloud Sync",
                subtitle: "Explicit opt-in only",
                isOn: isCloudSyncEnabled
            ) { newValue in
                LectraHaptics.selection()
                onSetCloudSyncEnabled(newValue)
            }

            divider

            settingsToggleRow(
                title: "Automatic Backup",
                subtitle: "Create a backup snapshot after successful sync work",
                isOn: isAutoBackupEnabled
            ) { newValue in
                LectraHaptics.selection()
                onSetAutoBackupEnabled(newValue)
            }
        }
        .padding(.horizontal, LectraSpacing.lg)
        .lectraCard(cornerRadius: LectraRadius.panel)
    }

    private func snapshotRow(_ snapshot: RecoverySnapshot) -> some View {
        VStack(alignment: .leading, spacing: LectraSpacing.sm) {
            HStack(alignment: .top, spacing: LectraSpacing.md) {
                VStack(alignment: .leading, spacing: LectraSpacing.xs) {
                    Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(LectraTypography.bodyEmphasis)
                        .foregroundColor(.white)

                    Text("\(snapshot.itemCount) document\(snapshot.itemCount == 1 ? "" : "s") in \(snapshot.source)")
                        .font(LectraTypography.captionMedium)
                        .foregroundColor(Color.white.opacity(LectraOpacity.prominent))
                }

                Spacer(minLength: 0)

                LectraStatusBadge(
                    title: snapshot.location == .iCloudDrive ? "iCloud Drive" : "On Device",
                    color: snapshot.location == .iCloudDrive ? LectraColor.info : LectraColor.success
                )
            }

            if !snapshot.items.isEmpty {
                Text(snapshot.items.prefix(3).map(\.title).joined(separator: " • "))
                    .font(LectraTypography.captionMedium)
                    .foregroundColor(Color.white.opacity(LectraOpacity.primary))
                    .lineLimit(2)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: LectraSpacing.sm) {
                    Button("Restore Copy") {
                        LectraHaptics.tap()
                        onRestoreSnapshotAsCopy(snapshot)
                    }
                    .buttonStyle(LectraSecondaryButtonStyle())

                    Button("Replace Current") {
                        LectraHaptics.warning()
                        onRestoreSnapshotReplacing(snapshot)
                    }
                    .buttonStyle(LectraDestructiveButtonStyle())
                }

                VStack(spacing: LectraSpacing.sm) {
                    Button("Restore Copy") {
                        LectraHaptics.tap()
                        onRestoreSnapshotAsCopy(snapshot)
                    }
                    .buttonStyle(LectraSecondaryButtonStyle())

                    Button("Replace Current") {
                        LectraHaptics.warning()
                        onRestoreSnapshotReplacing(snapshot)
                    }
                    .buttonStyle(LectraDestructiveButtonStyle())
                }
            }
        }
        .padding(LectraSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(LectraOpacity.faint))
        .overlay(
            RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous)
                .stroke(Color.white.opacity(LectraOpacity.subtle), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous))
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: LectraSpacing.xs) {
            Text(title)
                .font(LectraTypography.footnoteBold)
                .foregroundColor(Color.white.opacity(LectraOpacity.strong))

            Text(value)
                .font(LectraTypography.bodyEmphasis)
                .foregroundColor(Color.white.opacity(LectraOpacity.primary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LectraSpacing.md)
        .background(Color.white.opacity(LectraOpacity.faint))
        .overlay(
            RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous)
                .stroke(Color.white.opacity(LectraOpacity.subtle), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous))
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        systemImage: String,
        style: ActionButtonStyle,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if style == .primary {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(LectraPrimaryButtonStyle(disabled: isDisabled))
            .disabled(isDisabled)
        } else {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(LectraSecondaryButtonStyle())
            .disabled(isDisabled)
        }
    }

    private func settingsToggleRow(
        title: String,
        subtitle: String,
        isOn: Bool,
        onToggle: @escaping (Bool) -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: LectraSpacing.md) {
            VStack(alignment: .leading, spacing: LectraSpacing.xs) {
                Text(title)
                    .font(LectraTypography.headlineMedium)
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(LectraTypography.captionMedium)
                    .foregroundColor(Color.white.opacity(LectraOpacity.prominent))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: Binding(get: { isOn }, set: onToggle))
                .labelsHidden()
                .tint(LectraColor.surfaceCard)
                .accessibilityLabel(title)
                .accessibilityValue(isOn ? "On" : "Off")
        }
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(LectraOpacity.subtle))
            .frame(height: 1)
    }

    private enum ActionButtonStyle {
        case primary
        case secondary
    }
}
