//
//  PackagesPanelView.swift
//  Lectra
//
//  Manage Python packages for the notebook kernel. Shows the wheels that ship
//  with Lectra plus anything installed from PyPI (cached for offline reuse), and
//  lets the user install or remove extra packages via micropip.
//

import SwiftUI

struct PackagesPanelView: View {
    @ObservedObject var runtime: PyodideRuntime
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var installed: [String] = []
    @State private var working = false
    @State private var notice: String?

    /// Packages bundled in the app and always available offline.
    private let bundled = ["numpy", "pandas", "matplotlib", "pillow",
                           "python-dateutil", "pytz"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LectraSpacing.lg) {
                    installField
                    section(title: "Installed from PyPI",
                            empty: "Nothing yet. Add a package above, or just import it in a cell.",
                            items: installed, removable: true)
                    section(title: "Built in", empty: "", items: bundled, removable: false)
                }
                .padding(LectraSpacing.lg)
            }
            .background(LectraGradient.appBackdrop.ignoresSafeArea())
            .navigationTitle("Packages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(LectraColor.accentSoft)
                }
            }
            .toolbarBackground(LectraColor.surfaceOverlay, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task { await refresh() }
        .alert("Packages", isPresented: noticePresented) {
            Button("OK", role: .cancel) {}
        } message: { Text(notice ?? "") }
    }

    private var noticePresented: Binding<Bool> {
        Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
    }

    private var installField: some View {
        HStack(spacing: LectraSpacing.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(LectraColor.textTertiary)
            TextField("Package name (e.g. seaborn)", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(LectraColor.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.go)
                .onSubmit(install)
            if working {
                ProgressView().controlSize(.mini).tint(LectraColor.accentSoft)
            } else {
                Button("Install", action: install)
                    .font(LectraTypography.footnoteBold)
                    .foregroundStyle(canInstall ? LectraColor.accentSoft : LectraColor.textTertiary)
                    .disabled(!canInstall)
            }
        }
        .padding(.horizontal, LectraSpacing.md)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                .fill(LectraColor.surfaceFloating.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: LectraRadius.input, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)))
    }

    private var canInstall: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty && !working
    }

    private func section(title: String, empty: String, items: [String], removable: Bool) -> some View {
        VStack(alignment: .leading, spacing: LectraSpacing.sm) {
            Text(title.uppercased())
                .font(LectraTypography.footnoteBold)
                .foregroundStyle(LectraColor.textTertiary)
            if items.isEmpty {
                if !empty.isEmpty {
                    Text(empty)
                        .font(LectraTypography.footnote)
                        .foregroundStyle(LectraColor.textTertiary)
                }
            } else {
                ForEach(items, id: \.self) { name in
                    HStack {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(LectraColor.accentSoft.opacity(0.8))
                        Text(name).foregroundStyle(LectraColor.textPrimary)
                        Spacer()
                        if removable {
                            Button {
                                Task { await remove(name) }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 13))
                                    .foregroundStyle(LectraColor.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, LectraSpacing.md)
                    .frame(minHeight: 40)
                    .background(RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
                        .fill(LectraColor.surfaceFloating.opacity(0.4)))
                }
            }
        }
    }

    // MARK: Actions

    private func install() {
        let name = query.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !working else { return }
        working = true
        Task {
            let res = await runtime.install(name)
            working = false
            if res.success {
                query = ""
                notice = "Installed “\(name)”."
                await refresh()
            } else {
                notice = res.error ?? "Couldn’t install “\(name)”."
            }
        }
    }

    private func remove(_ name: String) async {
        await PackageCache.shared.remove(name: name)
        await refresh()
        notice = "Removed “\(name)” from your packages. It stays available until the kernel restarts."
    }

    private func refresh() async {
        installed = await PackageCache.shared.names()
    }
}
