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
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )

                Image(systemName: "star")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.gray.opacity(0.65))
                    .padding(8)
            }

            HStack(alignment: .top, spacing: 4) {
                Text(document.title)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(.white)
                    .lineLimit(2)

                if let onOptionsTap {
                    Button(action: onOptionsTap) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: 0xE84D4D))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(subtitle)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Color.white.opacity(0.58))
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
