//
//  DocumentCardView.swift
//  Lectra
//
//  A distinctive "drafting stack" document card for the vault grid.
//

import SwiftUI
import PDFKit

struct DocumentCardView: View {
    @ObservedObject var document: LocalDocument
    var onOptionsTap: (() -> Void)? = nil

    private var statusCaption: String {
        switch document.status {
        case .pendingAnnotation:
            return "Ready to annotate"
        case .annotated:
            return "Annotated"
        case .archived:
            return "Archived"
        case .local:
            return "On this iPad"
        case .downloading:
            return "Downloading"
        case .error:
            return "Needs retry"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .offset(y: 10)

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LectraGradient.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(LectraColor.edgeStroke, lineWidth: 1)
                    )

                VStack(spacing: 0) {
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(hex: 0x0E1628))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )

                        if let url = document.localPDFURL,
                           let pdfDoc = PDFDocument(url: url),
                           let page = pdfDoc.page(at: 0) {
                            PDFThumbnailRepresentable(page: page)
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                                .padding(6)
                                .transition(.opacity)
                        } else {
                            VStack(spacing: LectraSpacing.sm) {
                                Image(systemName: "doc.text.viewfinder")
                                    .font(.system(size: 34, weight: .medium))
                                    .foregroundColor(LectraColor.textTertiary)

                                if document.status == .downloading {
                                    ProgressView()
                                        .tint(LectraColor.accentCool)
                                }
                            }
                            .transition(.opacity)
                        }

                        StatusBadge(status: document.status)
                            .id(document.status)
                            .padding(10)
                            .transition(LectraMotion.statusTransition)
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(3 / 4, contentMode: .fit)

                    HStack(alignment: .top, spacing: LectraSpacing.sm) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(document.title)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(LectraColor.textPrimary)
                                .lineLimit(2)
                                .truncationMode(.tail)
                                .multilineTextAlignment(.leading)

                            Text(statusCaption)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(LectraColor.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer(minLength: 0)

                        if let onOptionsTap {
                            Button(action: onOptionsTap) {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Color.white.opacity(0.9))
                                    .frame(width: 30, height: 30)
                                    .background(Color.white.opacity(0.12))
                                    .clipShape(Circle())
                                    .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("File options")
                        }
                    }
                    .padding(12)
                }
            }
            .animation(LectraMotion.quick, value: document.localPDFURL != nil)
            .animation(LectraMotion.quick, value: document.status)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: DocumentStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.94))
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .pendingAnnotation: return "NEW"
        case .annotated:         return "DONE"
        case .archived:          return "ARCHIVE"
        case .local:             return "LOCAL"
        case .downloading:       return "LOAD"
        case .error:             return "ERROR"
        }
    }

    private var icon: String {
        switch status {
        case .pendingAnnotation: return "sparkles"
        case .annotated:         return "checkmark"
        case .archived:          return "archivebox"
        case .local:             return "ipad.and.arrow.down"
        case .downloading:       return "arrow.down.circle"
        case .error:             return "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch status {
        case .pendingAnnotation: return LectraColor.accent
        case .annotated:         return LectraColor.success
        case .archived:          return LectraColor.textTertiary
        case .local:             return LectraColor.accentCool
        case .downloading:       return LectraColor.warning
        case .error:             return Color(hex: 0xD53A48)
        }
    }
}

// MARK: - PDF Thumbnail (UIKit bridge)

struct PDFThumbnailRepresentable: UIViewRepresentable {
    let page: PDFPage

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .white
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        let bounds = page.bounds(for: .mediaBox)
        let size = CGSize(width: 360, height: 360 * bounds.height / bounds.width)
        let thumbnail = page.thumbnail(of: size, for: .mediaBox)
        imageView.image = thumbnail
    }
}
