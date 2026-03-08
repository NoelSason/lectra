//
//  DocumentCardView.swift
//  Lectra
//
//  Goodnotes-style document card for library grids.
//

import SwiftUI
import PDFKit

struct DocumentCardView: View {
    @ObservedObject var document: LocalDocument
    let subtitle: String
    var onOptionsTap: (() -> Void)? = nil
    var onFavoriteToggle: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 178)
                    .overlay {
                        cardContents
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)

                Button {
                    onFavoriteToggle?()
                } label: {
                    Image(systemName: document.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(document.isFavorite ? Color.yellow : Color.gray.opacity(0.8))
                        .padding(12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 4) {
                Text(document.title)
                    .font(.headline)
                    .foregroundColor(Color.white.opacity(0.95))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let onOptionsTap {
                    Button(action: onOptionsTap) {
                        Image(systemName: "ellipsis.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.8))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 10, y: -10)
                }
            }
            .padding(.top, 4)

            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var cardContents: some View {
        if let url = document.localPDFURL,
           let pdfDoc = PDFDocument(url: url),
           let page = pdfDoc.page(at: 0) {
            PDFThumbnailRepresentable(page: page)
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
}

// MARK: - PDF Thumbnail (UIKit bridge)

struct PDFThumbnailRepresentable: UIViewRepresentable {
    let page: PDFPage

    func makeUIView(context: Context) -> UIImageView {
        let imageView = NonIntrinsicImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = .white
        imageView.clipsToBounds = true
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        let bounds = page.bounds(for: .mediaBox)
        let width = max(imageView.bounds.width, 220)
        let height = max(imageView.bounds.height, 220)
        let targetWidth = max(width, height * bounds.width / max(bounds.height, 1))
        let size = CGSize(width: targetWidth, height: targetWidth * bounds.height / max(bounds.width, 1))
        let thumbnail = page.thumbnail(of: size, for: .mediaBox)
        imageView.image = thumbnail
    }
}

private final class NonIntrinsicImageView: UIImageView {
    override var intrinsicContentSize: CGSize { .zero }
}
