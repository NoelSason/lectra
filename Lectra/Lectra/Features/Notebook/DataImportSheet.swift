//
//  DataImportSheet.swift
//  Lectra
//
//  Asks how a picked CSV/TSV/table file should land in the notebook: loaded
//  straight into a pandas DataFrame, or just dropped into the working directory
//  for the user to read however they like. The delimiter is pre-filled from the
//  file type and editable for unusual files.
//

import SwiftUI

struct DataImportSheet: View {
    let fileName: String
    @State var delimiter: String
    let onImport: (_ asDataFrame: Bool, _ delimiter: String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LectraSpacing.lg) {
                    Text(fileName)
                        .font(LectraTypography.bodyEmphasis)
                        .foregroundStyle(LectraColor.textPrimary)

                    VStack(alignment: .leading, spacing: LectraSpacing.sm) {
                        Text("DELIMITER")
                            .font(LectraTypography.footnoteBold)
                            .foregroundStyle(LectraColor.textTertiary)
                        HStack(spacing: LectraSpacing.sm) {
                            delimiterChip(",", label: "Comma")
                            delimiterChip("\t", label: "Tab")
                            delimiterChip(";", label: "Semicolon")
                        }
                    }

                    primary(title: "Load as DataFrame",
                            subtitle: "Inserts a cell that reads the file into pandas.",
                            icon: "tablecells") {
                        finish(asDataFrame: true)
                    }
                    secondary(title: "Just add the file",
                              subtitle: "Drops it into the working directory; read it yourself.",
                              icon: "doc") {
                        finish(asDataFrame: false)
                    }
                }
                .padding(LectraSpacing.lg)
            }
            .background(LectraGradient.appBackdrop.ignoresSafeArea())
            .navigationTitle("Import data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(LectraColor.textSecondary)
                }
            }
            .toolbarBackground(LectraColor.surfaceOverlay, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private func finish(asDataFrame: Bool) {
        onImport(asDataFrame, delimiter)
        dismiss()
    }

    private func delimiterChip(_ value: String, label: String) -> some View {
        Button {
            delimiter = value
        } label: {
            Text(label)
                .font(LectraTypography.footnoteBold)
                .foregroundStyle(delimiter == value ? LectraColor.textPrimary : LectraColor.textSecondary)
                .padding(.horizontal, LectraSpacing.md)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                    .fill(delimiter == value ? LectraColor.accent.opacity(0.3) : LectraColor.surfaceFloating.opacity(0.5))
                    .overlay(RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                        .stroke(delimiter == value ? LectraColor.accent.opacity(0.6) : LectraColor.edgeStroke, lineWidth: 1)))
        }
        .buttonStyle(.plain)
    }

    private func primary(title: String, subtitle: String, icon: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            row(title: title, subtitle: subtitle, icon: icon, filled: true)
        }
        .buttonStyle(.plain)
    }

    private func secondary(title: String, subtitle: String, icon: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            row(title: title, subtitle: subtitle, icon: icon, filled: false)
        }
        .buttonStyle(.plain)
    }

    private func row(title: String, subtitle: String, icon: String, filled: Bool) -> some View {
        HStack(spacing: LectraSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(filled ? LectraColor.accentSoft : LectraColor.textSecondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LectraTypography.bodyEmphasis).foregroundStyle(LectraColor.textPrimary)
                Text(subtitle).font(LectraTypography.footnote).foregroundStyle(LectraColor.textTertiary)
            }
            Spacer()
        }
        .padding(LectraSpacing.md)
        .background(RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
            .fill(LectraColor.surfaceFloating.opacity(filled ? 0.7 : 0.4))
            .overlay(RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                .stroke(filled ? LectraColor.accent.opacity(0.4) : LectraColor.edgeStroke, lineWidth: 1)))
    }
}
