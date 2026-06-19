//
//  IntelligenceSettingsView.swift
//  Lectra
//
//  Settings surface explaining Lectra's on-device intelligence: live
//  availability, what runs privately on the iPad, and what unlocks with
//  Private Cloud Compute on a future OS.
//

import SwiftUI

struct IntelligenceSettingsView: View {
    private var status: LectraIntelligenceStatus { LectraIntelligence.status }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header
                statusCard
                capabilitiesCard
                privacyCard
            }
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Intelligence")
                .font(LectraTypography.displaySmall)
                .foregroundColor(LectraColor.textPrimary)
            Text("Summaries, flashcards, quizzes, and answers — generated on your iPad with Apple Foundation Models.")
                .font(LectraTypography.body)
                .foregroundColor(LectraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: LectraRadius.card, style: .continuous)
                    .fill((status.isReady ? LectraColor.success : LectraColor.warning).opacity(0.16))
                    .frame(width: 56, height: 56)
                Image(systemName: status.systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(status.isReady ? LectraColor.success : LectraColor.warning)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(status.headline)
                    .font(LectraTypography.titleSmall)
                    .foregroundColor(LectraColor.textPrimary)
                Text(status.message)
                    .font(LectraTypography.captionMedium)
                    .foregroundColor(LectraColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(panelBackground)
    }

    private var capabilitiesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WHAT YOU CAN DO")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundColor(LectraColor.accentSoft)

            capabilityRow(icon: "text.alignleft", title: "Summarize", detail: "Condense a page or a whole document into study-ready notes.")
            divider
            capabilityRow(icon: "bubble.left.and.text.bubble.right", title: "Ask this document", detail: "Get answers grounded only in what the document says.")
            divider
            capabilityRow(icon: "rectangle.on.rectangle.angled", title: "Flashcards", detail: "Turn material into a flip-through deck in seconds.")
            divider
            capabilityRow(icon: "checklist", title: "Practice quiz", detail: "Generate multiple-choice questions with explanations.")
        }
        .padding(20)
        .background(panelBackground)
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundColor(LectraColor.success)
                Text("Private by design")
                    .font(LectraTypography.headlineMedium)
                    .foregroundColor(LectraColor.textPrimary)
            }
            Text("Everything runs on-device — your documents never leave your iPad. A future update will add Private Cloud Compute for longer documents and deeper reasoning, keeping the same privacy guarantees.")
                .font(LectraTypography.captionMedium)
                .foregroundColor(LectraColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelBackground)
    }

    private func capabilityRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(LectraColor.accentSoft)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: LectraRadius.button, style: .continuous)
                        .fill(LectraColor.accent.opacity(0.12))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LectraTypography.bodyEmphasis)
                    .foregroundColor(LectraColor.textPrimary)
                Text(detail)
                    .font(LectraTypography.captionMedium)
                    .foregroundColor(LectraColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(LectraColor.edgeStroke)
            .frame(height: 1)
            .padding(.leading, 48)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
            .fill(LectraColor.surfaceElevated.opacity(0.90))
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                    .fill(LectraGradient.spotlight.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: LectraRadius.panel, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
            .lectraShadow(LectraElevation.low())
    }
}
