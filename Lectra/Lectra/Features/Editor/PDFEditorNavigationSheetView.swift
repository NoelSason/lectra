import SwiftUI
import PDFKit

struct PDFEditorNavigationSheetView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case pages
        case outline

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pages:
                return "Pages"
            case .outline:
                return "Outline"
            }
        }
    }

    let pdfURL: URL
    let outlineItems: [DocumentOutlineDestination]
    let currentPageIndex: Int
    let initialTab: Tab
    let onSelectPage: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: Tab
    @State private var pdfDocument: PDFDocument?

    init(
        pdfURL: URL,
        outlineItems: [DocumentOutlineDestination],
        currentPageIndex: Int,
        initialTab: Tab = .pages,
        onSelectPage: @escaping (Int) -> Void
    ) {
        self.pdfURL = pdfURL
        self.outlineItems = outlineItems
        self.currentPageIndex = currentPageIndex
        self.initialTab = initialTab
        self.onSelectPage = onSelectPage

        let resolvedInitialTab: Tab = outlineItems.isEmpty && initialTab == .outline ? .pages : initialTab
        _selectedTab = State(initialValue: resolvedInitialTab)
        _pdfDocument = State(initialValue: PDFDocument(url: pdfURL))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: LectraSpacing.md) {
                if !outlineItems.isEmpty {
                    Picker("Navigation", selection: $selectedTab) {
                        ForEach(Tab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                }

                Group {
                    if selectedTab == .outline, !outlineItems.isEmpty {
                        outlineList
                    } else {
                        pageGrid
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(
                ZStack {
                    LectraColor.background.ignoresSafeArea()
                    LectraGradient.appBackdrop.opacity(0.9).ignoresSafeArea()
                }
            )
            .navigationTitle("Navigate PDF")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        LectraHaptics.selection()
                        dismiss()
                    }
                    .foregroundColor(LectraColor.accentSoft)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .onChange(of: selectedTab) { _, _ in
            LectraHaptics.selection()
        }
    }

    private var pageGrid: some View {
        ScrollView {
            if let pdfDocument, pdfDocument.pageCount > 0 {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 148, maximum: 220), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(0..<pdfDocument.pageCount, id: \.self) { index in
                        PDFPageThumbnailButton(
                            page: pdfDocument.page(at: index),
                            pageIndex: index,
                            isSelected: index == currentPageIndex
                        ) {
                            onSelectPage(index)
                            dismiss()
                        }
                    }
                }
                .padding(20)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.richtext")
                        .font(LectraTypography.displaySmall)
                        .foregroundColor(.white.opacity(0.7))
                    Text("Page thumbnails aren’t available right now.")
                        .font(LectraTypography.bodyEmphasis)
                        .foregroundColor(.white.opacity(0.78))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            }
        }
    }

    private var outlineList: some View {
        List(outlineItems) { item in
            Button {
                LectraHaptics.selection()
                onSelectPage(item.pageIndex)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Text(item.title)
                        .font(item.pageIndex == currentPageIndex ? LectraTypography.bodyEmphasis : LectraTypography.body)
                        .foregroundColor(.white)
                        .padding(.leading, CGFloat(item.depth) * 12)
                    Spacer(minLength: 0)
                    Text("P\(item.pageIndex + 1)")
                        .font(LectraTypography.footnote)
                        .foregroundColor(Color.white.opacity(0.56))
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }
}

private struct PDFPageThumbnailButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let page: PDFPage?
    let pageIndex: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var thumbnail: UIImage?

    private let thumbnailSize = CGSize(width: 220, height: 300)

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous)
                        .fill(Color.white.opacity(LectraOpacity.subtle))

                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous))
                            .padding(10)
                    } else {
                        ProgressView()
                            .tint(.white)
                    }
                }
                .aspectRatio(0.72, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous)
                        .stroke(
                            isSelected ? LectraColor.accentCool : Color.white.opacity(LectraOpacity.medium),
                            lineWidth: isSelected ? 2 : 1
                        )
                )

                HStack {
                    Text("Page \(pageIndex + 1)")
                        .font(LectraTypography.bodyEmphasis)
                        .foregroundColor(.white)
                    Spacer(minLength: 0)
                    if isSelected {
                        LectraStatusBadge(title: "Current", color: LectraColor.accentCool)
                    }
                }
            }
            .padding(12)
            .lectraCard(cornerRadius: LectraRadius.panel)
            .scaleEffect(isSelected && !reduceMotion ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
        .task(id: pageIndex) {
            guard thumbnail == nil else { return }
            thumbnail = page?.thumbnail(of: thumbnailSize, for: .mediaBox)
        }
    }
}
