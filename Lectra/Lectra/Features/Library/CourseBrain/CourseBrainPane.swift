import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CourseBrainPane: View {
    let documents: [LocalDocument]
    var importedDocumentIDForResourceURL: ((URL) -> UUID?)? = nil
    var onImportPDF: ((URL, String) -> Void)?
    var onOpenDocument: ((UUID) -> Void)?

    @StateObject private var viewModel = CourseBrainViewModel()
    @Environment(\.openURL) private var openURL
    @State private var showsCompactDetail = false

    private let compactBreakpoint: CGFloat = 1_040

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < compactBreakpoint
            let queueWidth = min(max(proxy.size.width * 0.38, 320), 430)

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 14)

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)

                if isCompact {
                    queuePane(isCompact: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: 0) {
                        queuePane(isCompact: false)
                            .frame(width: queueWidth)
                            .frame(maxHeight: .infinity)

                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .frame(width: 1)

                        detailPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .background(Color.black)
        }
        .onAppear {
            viewModel.load(documents: documents)
        }
        .onChange(of: documents.map { "\($0.id.uuidString)-\($0.updatedAt.timeIntervalSince1970)" }) { _, _ in
            viewModel.updateLocalDocuments(documents)
        }
        .sheet(isPresented: $showsCompactDetail) {
            NavigationStack {
                detailPane
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showsCompactDetail = false
                            }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text("Course Brain")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.white)

                if let syncedAt = viewModel.headerLastSyncedAt() {
                    Text("Last synced \(syncedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.74))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)
            }

            CourseBrainSearchBar(
                text: $viewModel.searchText,
                placeholder: "Search recent assignments",
                isEditable: true
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    courseFilterChip(
                        title: "All Courses",
                        count: nil,
                        isSelected: viewModel.selectedCourseID == nil
                    ) {
                        viewModel.setCourseFilter(nil)
                    }

                    ForEach(viewModel.courseFilters) { course in
                        courseFilterChip(
                            title: course.name,
                            count: course.count,
                            isSelected: viewModel.selectedCourseID == course.id
                        ) {
                            viewModel.setCourseFilter(course.id)
                        }
                    }
                }
            }
        }
    }

    private func queuePane(isCompact: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            if viewModel.isLoading {
                ProgressView("Loading Course Brain")
                    .tint(Color(hex: 0xE84D4D))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.sections.isEmpty {
                emptyQueueState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(viewModel.sections) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(section.bucket.rawValue)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)

                                VStack(spacing: 8) {
                                    ForEach(section.items) { assignment in
                                        assignmentRow(assignment, isCompact: isCompact)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }

            if let message = viewModel.bannerMessage {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(hex: 0x53242C).opacity(0.96))
                    .clipShape(Capsule())
                    .padding(.leading, 16)
                    .padding(.top, 14)
            }
        }
        .background(Color(hex: 0x0A0A0B))
    }

    private func assignmentRow(_ assignment: CourseBrainAssignmentSummary, isCompact: Bool) -> some View {
        let isSelected = viewModel.selectedAssignmentDetail?.assignment.id == assignment.id

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(assignment.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        if let submissionStatus = assignment.mission.headlineSubmissionStatus {
                            submissionBadge(submissionStatus)
                        }

                        Text(relativeDateLabel(for: assignment.anchorDate))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: 0xFFCA8A))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(hex: 0x3A2312))
                            .clipShape(Capsule())
                    }
                }

                Text(assignment.courseName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.72))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(assignment.anchorDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.78))

                    if let moduleName = assignment.moduleName {
                        Text(moduleName)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.56))
                            .lineLimit(1)
                    }
                }
            }

            if let url = assignment.url {
                Button {
                    openResourceURL(url, preferCanvasApp: true)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? Color(hex: 0x241417) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? Color(hex: 0xE84D4D).opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectAssignment(assignment.id)
            if isCompact {
                showsCompactDetail = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(assignment.title). \(assignment.courseName). \(relativeDateLabel(for: assignment.anchorDate)).")
        .accessibilityHint(isCompact ? "Opens assignment details in a sheet." : "Opens assignment details.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction {
            viewModel.selectAssignment(assignment.id)
            if isCompact {
                showsCompactDetail = true
            }
        }
    }

    private var emptyQueueState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "checklist.checked")
                .font(.system(size: 34, weight: .regular))
                .foregroundColor(Color.white.opacity(0.84))

            Text("No recent assignments")
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(.white)

            Text("Course Brain now only shows assignments with dates between the past 7 days and the next 30 days. Undated assignments stay hidden.")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color.white.opacity(0.68))

            if let syncedAt = viewModel.headerLastSyncedAt() {
                Text("Latest snapshot: \(syncedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.62))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
    }

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let detail = viewModel.selectedAssignmentDetail {
                    detailHeader(detail)
                    quickActions(detail)
                    dateSummary(detail)
                    instructionsSection(detail)
                    resourcesSection(detail)
                    documentsSection(detail)
                    if !detail.evidence.isEmpty {
                        evidenceSection(detail)
                    }
                } else if viewModel.isLoading {
                    ProgressView("Loading")
                        .tint(Color(hex: 0xE84D4D))
                        .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Assignment Details")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)

                        Text("Select a recent assignment to inspect instructions, supporting resources, related PDFs, and sync freshness.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.68))
                    }
                    .padding(.top, 8)
                }
            }
            .padding(18)
        }
        .background(Color(hex: 0x111114))
    }

    private func detailHeader(_ detail: CourseBrainAssignmentDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(detail.assignment.title)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white)

            HStack(spacing: 8) {
                Text(detail.assignment.courseName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: 0x4A222A))
                    .clipShape(Capsule())

                if let moduleName = detail.assignment.moduleName {
                    Text(moduleName)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.76))
                        .lineLimit(1)
                }

                if let submissionStatus = detail.assignment.mission.headlineSubmissionStatus {
                    submissionBadge(submissionStatus)
                }
            }

            if let syncedAt = detail.lastSyncedAt {
                Text("Last synced \(syncedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.64))
            }
        }
    }

    private func quickActions(_ detail: CourseBrainAssignmentDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Quick Actions")

            if let url = detail.assignment.url {
                HStack(spacing: 8) {
                    Button {
                        openResourceURL(url, preferCanvasApp: true)
                    } label: {
                        Label(isCanvasURL(url) ? "Open in Canvas App" : "Open Assignment", systemImage: "arrow.up.right.square")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(hex: 0x4A222A))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isCanvasURL(url) ? "Open in Canvas app" : "Open assignment")

                    Button {
                        openResourceURL(url, preferCanvasApp: false)
                    } label: {
                        Label("Open Web Link", systemImage: "link")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.88))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open assignment web link")
                }
            } else {
                Text("No direct assignment URL is available in the current snapshot.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.62))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func dateSummary(_ detail: CourseBrainAssignmentDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Dates")

            detailRow(label: "Anchor", value: detail.assignment.anchorDate.formatted(date: .abbreviated, time: .shortened))

            if let submissionStatus = detail.assignment.mission.headlineSubmissionStatus {
                detailRow(label: "Submission", value: submissionStatus.displayTitle)
            }

            if let submittedAt = detail.assignment.mission.submissionSummary?.submittedAt {
                detailRow(label: "Submitted", value: submittedAt.formatted(date: .abbreviated, time: .shortened))
            }

            if let dueAt = detail.assignment.dueAt {
                detailRow(label: "Due", value: dueAt.formatted(date: .abbreviated, time: .shortened))
            }

            if let unlockAt = detail.assignment.unlockAt {
                detailRow(label: "Unlock", value: unlockAt.formatted(date: .abbreviated, time: .shortened))
            }

            if let lockAt = detail.assignment.lockAt {
                detailRow(label: "Lock", value: lockAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func instructionsSection(_ detail: CourseBrainAssignmentDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Instructions")

            if let instructions = detail.assignment.instructions,
               !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(instructions)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.82))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No assignment instructions were found in the current snapshot.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.62))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func resourcesSection(_ detail: CourseBrainAssignmentDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Related Course Resources")

            if detail.relatedResources.isEmpty {
                Text("No related pages, lectures, quizzes, files, or discussions matched this assignment strongly enough.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.62))
            } else {
                ForEach(detail.relatedResources) { resource in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(resource.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(2)

                                if let subtitle = resource.subtitle {
                                    Text(subtitle)
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(Color.white.opacity(0.64))
                                }

                                if resource.headlineSubmissionStatus != nil || resource.date != nil {
                                    HStack(spacing: 8) {
                                        if let submissionStatus = resource.headlineSubmissionStatus {
                                            submissionBadge(submissionStatus)
                                        }

                                        if let date = resource.date {
                                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                                .font(.system(size: 11, weight: .regular))
                                                .foregroundColor(Color.white.opacity(0.5))
                                        }
                                    }
                                }
                            }

                            Spacer(minLength: 0)

                            if let url = resource.url {
                                Button {
                                    openResourceURL(url, preferCanvasApp: true)
                                } label: {
                                    Text("Open")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(Color.white.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open \(resource.title)")
                            }
                        }

                        if resource.kind == .file,
                           let url = resource.url {
                            if let documentID = importedDocumentIDForResourceURL?(url),
                               let onOpenDocument {
                                Button {
                                    onOpenDocument(documentID)
                                } label: {
                                    Label("View PDF in Lectra", systemImage: "book.pages")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(LectraColor.success)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("View \(resource.title) in Lectra")
                            } else if let onImportPDF {
                                Button {
                                    onImportPDF(url, resource.title)
                                } label: {
                                    Label("Import PDF into Lectra", systemImage: "square.and.arrow.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Color(hex: 0xFFCA8A))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Import \(resource.title) into Lectra")
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func documentsSection(_ detail: CourseBrainAssignmentDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Related Course PDFs")

            if detail.relatedDocuments.isEmpty {
                Text("No synced PDFs are attached to this course yet.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.62))
            } else {
                ForEach(detail.relatedDocuments) { document in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(document.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(2)

                            Text("Updated \(document.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(Color.white.opacity(0.62))
                        }

                        Spacer(minLength: 0)

                        Button {
                            onOpenDocument?(document.id)
                        } label: {
                            Text("Open")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(onOpenDocument == nil)
                        .accessibilityLabel("Open \(document.title)")
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func evidenceSection(_ detail: CourseBrainAssignmentDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Linked Note Evidence")

            ForEach(detail.evidence) { evidence in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(evidence.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)

                        if let excerpt = evidence.excerpt {
                            Text(excerpt)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(Color.white.opacity(0.72))
                                .lineLimit(4)
                        }
                    }

                    Spacer(minLength: 0)

                    if let documentId = evidence.documentId {
                        Button {
                            onOpenDocument?(documentId)
                        } label: {
                            Text("Open")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(onOpenDocument == nil)
                        .accessibilityLabel("Open \(evidence.title)")
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.68))

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white)
        }
    }

    private func submissionBadge(_ status: CourseBrainSubmissionStatus) -> some View {
        Text(status.displayTitle)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(submissionBadgeForegroundColor(for: status))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(submissionBadgeBackgroundColor(for: status))
            .clipShape(Capsule())
    }

    private func submissionBadgeForegroundColor(for status: CourseBrainSubmissionStatus) -> Color {
        switch status {
        case .submitted:
            return Color(hex: 0xC4F7D2)
        case .late:
            return Color(hex: 0xFFE2B3)
        case .missing:
            return Color(hex: 0xFFB5BA)
        case .excused:
            return Color(hex: 0xD2D8FF)
        case .notSubmitted:
            return Color.white.opacity(0.82)
        case .unknown:
            return Color.white.opacity(0.78)
        }
    }

    private func submissionBadgeBackgroundColor(for status: CourseBrainSubmissionStatus) -> Color {
        switch status {
        case .submitted:
            return Color(hex: 0x1D4D2B)
        case .late:
            return Color(hex: 0x5A3414)
        case .missing:
            return Color(hex: 0x5A1F27)
        case .excused:
            return Color(hex: 0x2E355F)
        case .notSubmitted:
            return Color.white.opacity(0.08)
        case .unknown:
            return Color.white.opacity(0.06)
        }
    }

    private func courseFilterChip(
        title: String,
        count: Int?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                if let count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(isSelected ? 0.16 : 0.08))
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(isSelected ? .white : Color.white.opacity(0.78))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color(hex: 0x4A222A) : Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Filters the assignment list.")
    }

    private func relativeDateLabel(for date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func openResourceURL(_ url: URL, preferCanvasApp: Bool) {
        guard preferCanvasApp, isCanvasURL(url) else {
            openURL(url)
            return
        }

#if canImport(UIKit)
        let deepLinks = canvasDeepLinkCandidates(for: url)
        if !deepLinks.isEmpty {
            openCanvasDeepLinkCandidates(deepLinks, fallbackURL: url)
            return
        }

        UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { openedByUniversalLink in
            if !openedByUniversalLink {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
#else
        openURL(url)
#endif
    }

    private func isCanvasURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()

        if host.contains("instructure.com")
            || host.contains("canvaslms.com")
            || host == "canvas.com"
            || host.hasPrefix("canvas.")
            || host.contains(".canvas.") {
            return true
        }

        if path.contains("/courses/")
            && (path.contains("/assignments/")
                || path.contains("/discussion_topics/")
                || path.contains("/quizzes/")
                || path.contains("/files/")
                || path.contains("/pages/")
                || path.contains("/modules/")) {
            return true
        }

        return false
    }

    private func installedCanvasSchemes() -> [String] {
#if canImport(UIKit)
        let schemeCandidates = ["canvas-courses", "canvas-student"]
        var installed: [String] = []
        for scheme in schemeCandidates {
            guard let probeURL = URL(string: "\(scheme)://") else { continue }
            if UIApplication.shared.canOpenURL(probeURL) {
                installed.append(scheme)
            }
        }
        return installed
#else
        return []
#endif
    }

    private func canvasDeepLinkURL(for webURL: URL, scheme: String) -> URL? {
        guard var components = URLComponents(url: webURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = scheme
        return components.url
    }

    private func canvasDeepLinkCandidates(for webURL: URL) -> [URL] {
        installedCanvasSchemes().compactMap { scheme in
            canvasDeepLinkURL(for: webURL, scheme: scheme)
        }
    }

    private func openCanvasDeepLinkCandidates(_ candidates: [URL], fallbackURL: URL, index: Int = 0) {
#if canImport(UIKit)
        guard index < candidates.count else {
            UIApplication.shared.open(fallbackURL, options: [.universalLinksOnly: true]) { openedByUniversalLink in
                if !openedByUniversalLink {
                    UIApplication.shared.open(fallbackURL, options: [:], completionHandler: nil)
                }
            }
            return
        }

        UIApplication.shared.open(candidates[index], options: [:]) { success in
            if !success {
                openCanvasDeepLinkCandidates(candidates, fallbackURL: fallbackURL, index: index + 1)
            }
        }
#endif
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

private struct CourseBrainSearchBar: View {
    @Binding var text: String
    let placeholder: String
    let isEditable: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.58))

            if isEditable {
                TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Color.white.opacity(0.42)))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white)
            } else {
                Text(text.isEmpty ? placeholder : text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(text.isEmpty ? Color.white.opacity(0.42) : .white)
            }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}
