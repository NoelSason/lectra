//
//  DocumentCardView.swift
//  Lectra
//
//  Lectra workspace document card for library grids.
//

import SwiftUI
import PDFKit

struct LibraryGridMetrics {
    let cardWidth: CGFloat
    let pdfPreviewHeight: CGFloat
    let pdfFooterHeight: CGFloat
    let pdfTotalHeight: CGFloat
    let folderArtworkHeight: CGFloat
    let folderFooterHeight: CGFloat
    let folderTotalHeight: CGFloat
    let sectionGap: CGFloat
    let folderGridSpacing: CGFloat
    let documentGridSpacing: CGFloat
    let documentShadowColor: Color
    let documentShadowRadius: CGFloat
    let documentShadowYOffset: CGFloat

    static func root(cardWidth: CGFloat) -> LibraryGridMetrics {
        LibraryGridMetrics(
            cardWidth: cardWidth,
            pdfPreviewHeight: 120,
            pdfFooterHeight: 60,
            pdfTotalHeight: 188,
            folderArtworkHeight: 128,
            folderFooterHeight: 52,
            folderTotalHeight: 188,
            sectionGap: 32,
            folderGridSpacing: 28,
            documentGridSpacing: 34,
            documentShadowColor: LectraColor.background.opacity(0.28),
            documentShadowRadius: 4,
            documentShadowYOffset: 1
        )
    }

    static func nested(cardWidth: CGFloat) -> LibraryGridMetrics {
        LibraryGridMetrics(
            cardWidth: cardWidth,
            pdfPreviewHeight: 120,
            pdfFooterHeight: 60,
            pdfTotalHeight: 188,
            folderArtworkHeight: 128,
            folderFooterHeight: 52,
            folderTotalHeight: 188,
            sectionGap: 24,
            folderGridSpacing: 24,
            documentGridSpacing: 30,
            documentShadowColor: LectraColor.background.opacity(0.28),
            documentShadowRadius: 4,
            documentShadowYOffset: 1
        )
    }
}

struct DocumentCardView: View {
    @ObservedObject var document: LocalDocument
    let subtitle: String
    let metrics: LibraryGridMetrics
    var onOptionsTap: (() -> Void)? = nil
    var onFavoriteToggle: (() -> Void)? = nil
    var onSyncRetryTap: (() -> Void)? = nil
    @State private var favoritePulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            previewCard

            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(displayTitle)
                        .font(LectraTypography.bodyEmphasis)
                        .foregroundColor(LectraColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityIdentifier("library.document.title.\(document.id.uuidString)")

                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusDotColor)
                            .frame(width: 5, height: 5)

                        Text(subtitle)
                            .font(LectraTypography.captionMedium)
                            .foregroundColor(LectraColor.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .accessibilityIdentifier("library.document.metadata.\(document.id.uuidString)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let onOptionsTap {
                    optionsButton(action: onOptionsTap)
                }
            }
            .frame(maxWidth: .infinity, minHeight: metrics.pdfFooterHeight, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: metrics.pdfTotalHeight, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayTitle). Last modified \(subtitle).")
        .accessibilityIdentifier("library.document.card.\(document.id.uuidString)")
    }

    private var previewCard: some View {
        Group {
            if document.localPDFURL != nil {
                CachedDocumentThumbnailView(
                    document: document,
                    size: CGSize(width: metrics.cardWidth, height: metrics.pdfPreviewHeight)
                )
            } else {
                ZStack {
                    LinearGradient(
                        colors: [LectraColor.placeholderStart, LectraColor.placeholderEnd],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(spacing: 4) {
                        Image(systemName: document.status == .downloading ? "arrow.down.circle" : "doc.text")
                            .font(LectraTypography.titleSmall)
                            .foregroundColor(LectraColor.textPrimary.opacity(0.86))

                        if document.status == .downloading {
                            ProgressView()
                                .tint(LectraColor.textPrimary)
                        }
                    }
                }
            }
        }
        .frame(width: metrics.cardWidth, height: metrics.pdfPreviewHeight)
        .background(LectraColor.paper)
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [Color.clear, LectraColor.background.opacity(0.45)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 48)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomLeading) { syncCloudIndicator }
        .overlay(alignment: .topTrailing) { favoriteButton }
        .clipShape(RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous)
                .stroke(LectraGlass.hairlineStroke, lineWidth: 0.5)
        )
        .lectraShadow((
            color: LectraColor.background.opacity(0.42),
            radius: LectraElevation.libraryCardRadius + 2,
            y: LectraElevation.libraryCardYOffset + 1
        ))
        .frame(width: metrics.cardWidth, height: metrics.pdfPreviewHeight)
    }

    @ViewBuilder
    private var syncCloudIndicator: some View {
        if let cloud = cloudGlyph {
            Group {
                if document.syncState == .failed, let onSyncRetryTap {
                    Button(action: onSyncRetryTap) { cloudChip(symbol: cloud.symbol, tint: cloud.tint) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Retry sync")
                } else {
                    cloudChip(symbol: cloud.symbol, tint: cloud.tint)
                }
            }
            .padding(8)
        }
    }

    private func cloudChip(symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay(Circle().stroke(LectraGlass.hairlineStroke, lineWidth: 0.5))
            )
            .accessibilityLabel("Sync status")
    }

    private var cloudGlyph: (symbol: String, tint: Color)? {
        if document.conflictState == .needsReview {
            return ("exclamationmark.triangle.fill", LectraColor.accent)
        }

        switch document.syncState {
        case .idle:
            if document.ocrState == .needsOCR {
                return ("text.viewfinder", LectraColor.warningSubtle)
            }
            return nil
        case .synced:
            return ("checkmark.icloud.fill", LectraColor.success)
        case .savingLocal, .flattening, .queuedUpload, .uploading:
            return ("arrow.triangle.2.circlepath.icloud", LectraColor.info)
        case .failed:
            return ("exclamationmark.icloud.fill", LectraColor.accentSoft)
        }
    }

    private var favoriteButton: some View {
        Button {
            LectraHaptics.tap()
            withAnimation(LectraMotion.bounce) {
                favoritePulse.toggle()
            }
            onFavoriteToggle?()
        } label: {
            Image(systemName: document.isFavorite ? "star.fill" : "star")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(document.isFavorite ? LectraColor.warning : LectraColor.textPrimary)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .overlay(Circle().stroke(LectraGlass.hairlineStroke, lineWidth: 0.5))
                )
                .scaleEffect(favoritePulse ? 1.12 : 1.0)
                .padding(8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(document.isFavorite ? "Remove favorite" : "Mark favorite")
        .accessibilityValue(document.isFavorite ? "Favorite" : "Not favorite")
        .accessibilityIdentifier("library.document.favorite.\(document.id.uuidString)")
    }

    private var statusDotColor: Color {
        switch document.status {
        case .annotated: return LectraColor.success
        case .pendingAnnotation: return LectraColor.warningSubtle
        case .downloading: return LectraColor.info
        case .error: return LectraColor.accent
        default: return LectraColor.textTertiary.opacity(0.6)
        }
    }

    private func optionsButton(action: @escaping () -> Void) -> some View {
        Button {
            LectraHaptics.tap()
            action()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(LectraColor.textSecondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: LectraRadius.button, style: .continuous)
                        .fill(LectraColor.surfaceFloating.opacity(0.6))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More options for \(displayTitle)")
        .accessibilityIdentifier("library.document.options.\(document.id.uuidString)")
    }

    private var displayTitle: String {
        let trimmedTitle = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "Untitled PDF" : trimmedTitle
    }
}

struct DocumentSyncBadgeView: View {
    enum Size {
        case regular
        case compact

        var fontSize: CGFloat {
            switch self {
            case .regular:
                return 11
            case .compact:
                return 9
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .regular:
                return 8
            case .compact:
                return 6
            }
        }

        var height: CGFloat {
            switch self {
            case .regular:
                return 24
            case .compact:
                return 14
            }
        }
    }

    let state: DocumentSyncState
    var size: Size = .regular
    var onRetryTap: (() -> Void)? = nil

    var body: some View {
        Group {
            if state == .failed, let onRetryTap {
                Button(action: onRetryTap) {
                    badge(title: "Retry", color: LectraColor.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry sync")
                .accessibilityValue("Sync failed")
            } else {
                badge(title: title, color: color)
            }
        }
        .accessibilityLabel("Sync status")
        .accessibilityValue(title)
    }

    private var title: String {
        switch state {
        case .idle:
            return ""
        case .savingLocal, .flattening:
            return "Saving"
        case .queuedUpload:
            return "Queued"
        case .uploading:
            return "Uploading"
        case .synced:
            return "Synced"
        case .failed:
            return "Retry"
        }
    }

    private var color: Color {
        switch state {
        case .idle:
            return .clear
        case .savingLocal, .flattening, .uploading:
            return LectraColor.accentCool
        case .queuedUpload:
            return LectraColor.warningSubtle
        case .synced:
            return LectraColor.accentSoft
        case .failed:
            return LectraColor.accentSoft
        }
    }

    private func badge(title: String, color: Color) -> some View {
        LectraStatusBadge(
            title: title,
            color: color,
            size: size == .compact ? .compact : .regular
        )
    }
}

struct CachedDocumentThumbnailView: View {
    @ObservedObject var document: LocalDocument
    let size: CGSize

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .task(id: taskID) {
            await loadThumbnail()
        }
    }

    private var taskID: String {
        "\(document.id.uuidString)-\(document.thumbnailRevision)-\(Int(size.width))x\(Int(size.height))"
    }

    @MainActor
    private func loadThumbnail() async {
        guard let url = document.localPDFURL else {
            image = nil
            return
        }
        image = await ThumbnailCache.shared.loadThumbnail(
            documentId: document.id,
            pdfURL: url,
            revision: document.thumbnailRevision,
            size: size
        )
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [LectraColor.paper, LectraColor.paperMuted],
                startPoint: .top,
                endPoint: .bottom
            )
            ProgressView()
                .tint(LectraColor.accent)
        }
    }
}
