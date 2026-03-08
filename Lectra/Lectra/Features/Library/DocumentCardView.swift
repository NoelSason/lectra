//
//  DocumentCardView.swift
//  Lectra
//
//  Goodnotes-style document card for library grids.
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
            pdfPreviewHeight: 88,
            pdfFooterHeight: 52,
            pdfTotalHeight: 148,
            folderArtworkHeight: 128,
            folderFooterHeight: 44,
            folderTotalHeight: 180,
            sectionGap: 32,
            folderGridSpacing: 28,
            documentGridSpacing: 34,
            documentShadowColor: Color.black.opacity(0.12),
            documentShadowRadius: 4,
            documentShadowYOffset: 1
        )
    }

    static func nested(cardWidth: CGFloat) -> LibraryGridMetrics {
        LibraryGridMetrics(
            cardWidth: cardWidth,
            pdfPreviewHeight: 84,
            pdfFooterHeight: 52,
            pdfTotalHeight: 144,
            folderArtworkHeight: 128,
            folderFooterHeight: 44,
            folderTotalHeight: 180,
            sectionGap: 24,
            folderGridSpacing: 24,
            documentGridSpacing: 30,
            documentShadowColor: Color.black.opacity(0.12),
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            previewCard

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(displayTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.95))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    if let onOptionsTap {
                        Button(action: onOptionsTap) {
                            Image(systemName: "ellipsis.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.8))
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 6) {
                    if document.syncState != .idle {
                        DocumentSyncBadgeView(
                            state: document.syncState,
                            size: .compact,
                            onRetryTap: onSyncRetryTap
                        )
                        .fixedSize()
                    }

                    Text("Last modified \(subtitle)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: metrics.pdfFooterHeight, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: metrics.pdfTotalHeight, alignment: .topLeading)
        .clipped()
    }

    private var previewCard: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if document.localPDFURL != nil {
                    CachedDocumentThumbnailView(
                        document: document,
                        size: CGSize(width: metrics.cardWidth, height: metrics.pdfPreviewHeight)
                    )
                } else {
                    ZStack {
                        LinearGradient(
                            colors: [Color(hex: 0xD86A6A), Color(hex: 0xB54747)],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        VStack(spacing: 4) {
                            Image(systemName: document.status == .downloading ? "arrow.down.circle" : "doc.text")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.85))

                            if document.status == .downloading {
                                ProgressView()
                                    .tint(.white)
                            }
                        }
                    }
                }
            }
            .frame(width: metrics.cardWidth, height: metrics.pdfPreviewHeight)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(LectraGlass.hairlineStroke, lineWidth: 0.5)
            )
            .shadow(
                color: Color.black.opacity(0.2),
                radius: LectraElevation.libraryCardRadius,
                x: 0,
                y: LectraElevation.libraryCardYOffset
            )
            .clipped()

            Button {
                onFavoriteToggle?()
            } label: {
                Image(systemName: document.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(document.isFavorite ? Color.yellow : Color.gray.opacity(0.8))
                    .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: metrics.cardWidth, height: metrics.pdfPreviewHeight)
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
            } else {
                badge(title: title, color: color)
            }
        }
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
            return Color(hex: 0x2E8DFF)
        case .queuedUpload:
            return Color(hex: 0xD0A13A)
        case .synced:
            return LectraColor.success
        case .failed:
            return LectraColor.accent
        }
    }

    private func badge(title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: size.fontSize, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, size.horizontalPadding)
            .frame(height: size.height)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
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
                colors: [Color(hex: 0xECECEC), Color(hex: 0xDADADA)],
                startPoint: .top,
                endPoint: .bottom
            )
            ProgressView()
                .tint(Color.gray.opacity(0.8))
        }
    }
}
