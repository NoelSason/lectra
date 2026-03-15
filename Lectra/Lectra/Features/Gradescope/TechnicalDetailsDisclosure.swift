import SwiftUI
import UIKit

struct TechnicalDetailsPresentation: Equatable {
    let summary: String
    let details: String

    static func make(
        summary: String,
        details: String?,
        excluding duplicateDetails: String? = nil
    ) -> TechnicalDetailsPresentation? {
        let normalizedDetails = normalized(details)
        guard let normalizedDetails, !normalizedDetails.isEmpty else { return nil }

        if let duplicate = normalized(duplicateDetails), duplicate == normalizedDetails {
            return nil
        }

        let normalizedSummary = normalized(summary)
        let resolvedSummary =
            (normalizedSummary?.isEmpty == false)
            ? normalizedSummary!
            : "Technical details are available for support."
        return TechnicalDetailsPresentation(summary: resolvedSummary, details: normalizedDetails)
    }

    private static func normalized(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n")
    }
}

struct TechnicalDetailsDisclosure: View {
    let presentation: TechnicalDetailsPresentation
    var accessibilityID: String

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(presentation.summary)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Button("Copy details") {
                        UIPasteboard.general.string = presentation.details
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(LectraColor.accent)
                    .accessibilityIdentifier("\(accessibilityID).copy")

                    Text(presentation.details)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("\(accessibilityID).body")
                }
                .padding(.top, 4)
            } label: {
                Label("Technical details", systemImage: "wrench.and.screwdriver")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
            }
            .tint(LectraColor.accent)
            .accessibilityIdentifier("\(accessibilityID).disclosure")
            .accessibilityHint("Shows diagnostic information for support.")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityID)
    }
}
