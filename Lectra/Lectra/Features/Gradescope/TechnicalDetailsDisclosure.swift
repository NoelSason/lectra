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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let presentation: TechnicalDetailsPresentation
    var accessibilityID: String

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: LectraSpacing.sm) {
            Text(presentation.summary)
                .font(LectraTypography.captionMedium)
                .foregroundColor(LectraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: LectraSpacing.sm) {
                    Button("Copy details") {
                        LectraHaptics.selection()
                        UIPasteboard.general.string = presentation.details
                    }
                    .font(LectraTypography.caption)
                    .foregroundColor(LectraColor.accentSoft)
                    .accessibilityIdentifier("\(accessibilityID).copy")

                    Text(presentation.details)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(LectraColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("\(accessibilityID).body")
                }
                .padding(.top, LectraSpacing.xs)
            } label: {
                Label("Technical details", systemImage: "wrench.and.screwdriver")
                    .font(LectraTypography.caption)
                    .foregroundColor(LectraColor.textSecondary)
            }
            .tint(LectraColor.accentSoft)
            .animation(reduceMotion ? nil : LectraMotion.quick, value: isExpanded)
            .accessibilityIdentifier("\(accessibilityID).disclosure")
            .accessibilityHint("Shows diagnostic information for support.")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        }
        .padding(LectraSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                .fill(LectraColor.surfaceFloating.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                        .stroke(LectraColor.edgeStroke, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityID)
    }
}
