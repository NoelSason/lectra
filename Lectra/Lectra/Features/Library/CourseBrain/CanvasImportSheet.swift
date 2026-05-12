import SwiftUI

struct CanvasImportSheet: View {
    let availableCourses: [CourseTwin]
    @ObservedObject var service: CanvasImportService
    let onImport: ([CourseTwin]) -> Void
    let onDismiss: () -> Void

    @State private var selectedCourseIDs: Set<Int> = []
    @State private var livePDFCounts: [Int: Int] = [:]

    var body: some View {
        NavigationStack {
            content
                .background(LectraColor.surfaceOverlay)
                .navigationTitle("Import from Canvas")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .toolbarBackground(LectraColor.surfaceOverlay, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(service.isRunning)
        .task(id: availableCourseIDsKey) {
            await refreshLivePDFCounts()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch service.phase {
        case .idle:
            selectionList
        case .running:
            progressBody
        case let .finished(imported, skipped, failed):
            summaryBody(imported: imported, skipped: skipped, failed: failed, cancelled: false)
        case let .cancelled(imported, skipped, failed):
            summaryBody(imported: imported, skipped: skipped, failed: failed, cancelled: true)
        case let .failed(message):
            failureBody(message)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(service.isRunning ? "Hide" : "Cancel") {
                onDismiss()
            }
            .foregroundColor(.white)
        }
    }

    // MARK: - Selection

    private var selectionList: some View {
        VStack(spacing: 0) {
            if availableCourses.isEmpty {
                emptyState
            } else {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(availableCourses) { course in
                            courseRow(course)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 110)
                }
            }

            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pick courses to back up")
                .font(LectraTypography.title)
                .foregroundColor(.white)
            Text("Lectra downloads every PDF from each selected course's assignments and Files tab into Imported From Canvas.")
                .font(LectraTypography.body)
                .foregroundColor(LectraColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func courseRow(_ course: CourseTwin) -> some View {
        let isSelected = selectedCourseIDs.contains(course.courseId)
        return Button {
            LectraHaptics.selection()
            if isSelected {
                selectedCourseIDs.remove(course.courseId)
            } else {
                selectedCourseIDs.insert(course.courseId)
            }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isSelected ? LectraColor.canvasTint : Color.white.opacity(0.3))

                VStack(alignment: .leading, spacing: 4) {
                    Text(courseDisplayName(course))
                        .font(LectraTypography.bodyEmphasis)
                        .foregroundColor(.white)
                        .lineLimit(2)

                    Text(courseSubtitle(course))
                        .font(LectraTypography.captionMedium)
                        .foregroundColor(LectraColor.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? LectraColor.surfaceCard.opacity(0.45) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? LectraColor.canvasTint.opacity(0.55) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            HStack(spacing: 12) {
                Text(footerSelectionLabel)
                    .font(LectraTypography.captionMedium)
                    .foregroundColor(LectraColor.textSecondary)

                Spacer(minLength: 0)

                Button {
                    LectraHaptics.tap()
                    let selectedCourses = availableCourses.filter { selectedCourseIDs.contains($0.courseId) }
                    onImport(selectedCourses)
                } label: {
                    Text(selectedCourseIDs.isEmpty ? "Import" : "Import \(selectedCourseIDs.count) Course\(selectedCourseIDs.count == 1 ? "" : "s")")
                        .font(LectraTypography.bodyEmphasis)
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedCourseIDs.isEmpty ? Color.white.opacity(0.08) : LectraColor.canvasTint)
                        )
                }
                .buttonStyle(.plain)
                .disabled(selectedCourseIDs.isEmpty)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(LectraColor.surfaceOverlay)
        }
    }

    private var footerSelectionLabel: String {
        if availableCourses.isEmpty {
            return ""
        }
        if selectedCourseIDs.isEmpty {
            return "\(availableCourses.count) course\(availableCourses.count == 1 ? "" : "s") available"
        }
        return "\(selectedCourseIDs.count) of \(availableCourses.count) selected"
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 44, weight: .regular))
                .foregroundColor(.white.opacity(0.7))
            Text("No synced courses yet")
                .font(LectraTypography.title)
                .foregroundColor(.white)
            Text("Open the Canvascope extension in Safari to scan a course, then come back here.")
                .font(LectraTypography.body)
                .foregroundColor(LectraColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Progress

    private var progressBody: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progressFraction)
                    .stroke(LectraColor.canvasTint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.25), value: progressFraction)

                VStack(spacing: 2) {
                    Text(progressCounterText)
                        .font(LectraTypography.title)
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                    Text("PDFs")
                        .font(LectraTypography.captionMedium)
                        .foregroundColor(LectraColor.textSecondary)
                }
            }
            .frame(width: 160, height: 160)

            VStack(spacing: 6) {
                if service.progress.total == 0 {
                    Text("Scanning Canvas")
                        .font(LectraTypography.bodyEmphasis)
                        .foregroundColor(.white)
                    Text("Counting PDFs before downloads start.")
                        .font(LectraTypography.captionMedium)
                        .foregroundColor(LectraColor.textSecondary)
                        .multilineTextAlignment(.center)
                } else if let course = service.progress.currentCourseName {
                    Text(course)
                        .font(LectraTypography.bodyEmphasis)
                        .foregroundColor(.white)
                }
                if let title = service.progress.currentTitle {
                    Text(title)
                        .font(LectraTypography.captionMedium)
                        .foregroundColor(LectraColor.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                LectraHaptics.warning()
                service.cancel()
            } label: {
                Text("Stop importing")
                    .font(LectraTypography.bodyEmphasis)
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var progressFraction: Double {
        guard service.progress.total > 0 else { return 0 }
        return Double(service.progress.completed) / Double(service.progress.total)
    }

    private var progressCounterText: String {
        guard service.progress.total > 0 else { return "Scanning" }
        return "\(service.progress.completed)/\(service.progress.total)"
    }

    // MARK: - Summary

    private func summaryBody(imported: Int, skipped: Int, failed: Int, cancelled: Bool) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: cancelled ? "stop.circle" : (failed > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"))
                .font(.system(size: 56, weight: .semibold))
                .foregroundColor(cancelled ? LectraColor.warning : (failed > 0 ? LectraColor.warning : LectraColor.success))

            Text(cancelled ? "Stopped" : "Import complete")
                .font(LectraTypography.title)
                .foregroundColor(.white)

            VStack(spacing: 6) {
                summaryRow(label: "Imported", value: imported, color: LectraColor.success)
                if skipped > 0 {
                    summaryRow(label: "Already in Lectra", value: skipped, color: LectraColor.textSecondary)
                }
                if failed > 0 {
                    summaryRow(label: "Failed", value: failed, color: LectraColor.warning)
                }
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Text("Done")
                    .font(LectraTypography.bodyEmphasis)
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LectraColor.canvasTint)
                    )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private func summaryRow(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(LectraTypography.body)
                .foregroundColor(LectraColor.textSecondary)
            Text("\(value)")
                .font(LectraTypography.bodyEmphasis)
                .foregroundColor(color)
        }
    }

    private func failureBody(_ message: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundColor(LectraColor.warning)
            Text("Import couldn't start")
                .font(LectraTypography.title)
                .foregroundColor(.white)
            Text(message)
                .font(LectraTypography.body)
                .foregroundColor(LectraColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                onDismiss()
            } label: {
                Text("Close")
                    .font(LectraTypography.bodyEmphasis)
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func courseDisplayName(_ course: CourseTwin) -> String {
        let name = course.metadata.courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        if let code = course.metadata.courseCode?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
            return code
        }
        return "Course \(course.courseId)"
    }

    private func courseSubtitle(_ course: CourseTwin) -> String {
        var pieces: [String] = []
        if let code = course.metadata.courseCode?.trimmingCharacters(in: .whitespacesAndNewlines),
           !code.isEmpty,
           code.localizedCaseInsensitiveCompare(course.metadata.courseName) != .orderedSame {
            pieces.append(code)
        }
        if let term = course.metadata.termName?.trimmingCharacters(in: .whitespacesAndNewlines), !term.isEmpty {
            pieces.append(term)
        }
        if let pdfCount = livePDFCounts[course.courseId] {
            pieces.append("\(pdfCount) PDF\(pdfCount == 1 ? "" : "s")")
        } else {
            let snapshotCount = countPDFResources(in: course)
            if snapshotCount > 0 {
                pieces.append("\(snapshotCount) PDF\(snapshotCount == 1 ? "" : "s")")
            } else {
                pieces.append("Checking PDFs")
            }
        }
        return pieces.joined(separator: " • ")
    }

    private var availableCourseIDsKey: String {
        availableCourses.map { String($0.courseId) }.joined(separator: ",")
    }

    @MainActor
    private func refreshLivePDFCounts() async {
        guard !availableCourses.isEmpty else {
            livePDFCounts = [:]
            return
        }

        let validIDs = Set(availableCourses.map(\.courseId))
        livePDFCounts = livePDFCounts.filter { validIDs.contains($0.key) }

        let cookies = await CanvasCookieStore.loadMergedSession().map(\.cookie)
        for course in availableCourses {
            if Task.isCancelled { return }
            if livePDFCounts[course.courseId] != nil { continue }
            guard let host = inferredCanvasHost(for: course) else { continue }

            let api = await CanvasFilesAPI.fetchAll(host: host, courseId: course.courseId, cookies: cookies)
            if Task.isCancelled { return }
            guard !api.files.isEmpty || !api.folders.isEmpty || api.source == .webView else { continue }
            livePDFCounts[course.courseId] = countPDFs(in: api.files)
        }
    }

    private func inferredCanvasHost(for course: CourseTwin) -> String? {
        if let host = course.metadata.platformDomain?.trimmingCharacters(in: .whitespacesAndNewlines),
           !host.isEmpty {
            return host.lowercased()
        }
        if let host = course.resources.compactMap({ $0.url?.host }).first {
            return host.lowercased()
        }
        if let host = course.modules.flatMap(\.items).compactMap({ $0.url?.host }).first {
            return host.lowercased()
        }
        return nil
    }

    private func countPDFs(in files: [CanvasAPIFile]) -> Int {
        files.reduce(into: 0) { count, file in
            guard !file.isUnavailable else { return }
            let title = file.resolvedDisplayName
            let isPDF =
                (file.contentType ?? "").lowercased().contains("pdf")
                || (file.mimeClass ?? "").lowercased() == "pdf"
                || title.lowercased().hasSuffix(".pdf")
                || (file.filename ?? "").lowercased().hasSuffix(".pdf")
            if isPDF {
                count += 1
            }
        }
    }

    private func countPDFResources(in course: CourseTwin) -> Int {
        var seen = Set<String>()
        for resource in course.resources {
            guard resource.kind == .assignment || resource.kind == .file else { continue }
            guard let url = resource.url else { continue }
            guard looksLikePDF(url: url, title: resource.title, contentType: resource.contentType) else { continue }
            seen.insert(url.absoluteString.lowercased())
        }
        for module in course.modules {
            for item in module.items where item.type.lowercased().contains("file") {
                guard let url = item.url else { continue }
                guard looksLikePDF(url: url, title: item.title, contentType: nil) else { continue }
                seen.insert(url.absoluteString.lowercased())
            }
        }
        return seen.count
    }

    private func looksLikePDF(url: URL, title: String?, contentType: String?) -> Bool {
        let path = url.path.lowercased()
        let lowerTitle = (title ?? "").lowercased()
        let lowerCT = (contentType ?? "").lowercased()

        if path.contains("/files/folder") { return false }
        if path.hasSuffix(".pdf") || lowerTitle.hasSuffix(".pdf") { return true }
        if lowerCT.contains("pdf") { return true }

        let nonPDFExtensions = [
            ".doc", ".docx", ".ppt", ".pptx", ".xls", ".xlsx",
            ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".heic", ".webp", ".svg",
            ".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm",
            ".mp3", ".wav", ".m4a", ".aac", ".flac",
            ".zip", ".rar", ".7z", ".tar", ".gz", ".tgz",
            ".html", ".htm", ".txt", ".csv", ".rtf",
            ".py", ".ipynb", ".java", ".c", ".cpp", ".h", ".swift", ".js", ".ts",
            ".json", ".xml", ".yaml", ".yml"
        ]
        for ext in nonPDFExtensions {
            if path.hasSuffix(ext) || lowerTitle.hasSuffix(ext) { return false }
        }
        if lowerCT.hasPrefix("image/")
            || lowerCT.hasPrefix("video/")
            || lowerCT.hasPrefix("audio/")
            || lowerCT.hasPrefix("text/html")
            || lowerCT.contains("zip")
            || lowerCT.contains("word")
            || lowerCT.contains("excel")
            || lowerCT.contains("powerpoint")
            || lowerCT.contains("presentation")
            || lowerCT.contains("spreadsheet")
            || lowerCT.contains("sheet") {
            return false
        }

        if path.range(of: #"/files/\d+"#, options: .regularExpression) != nil { return true }
        if (url.query?.lowercased() ?? "").contains("download_frd") { return true }
        return false
    }
}
