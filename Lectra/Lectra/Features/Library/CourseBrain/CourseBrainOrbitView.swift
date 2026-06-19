import SwiftUI

// MARK: - Orbit View

/// **Orbit** — A premium, actionable course content dashboard.
///
/// Instead of an abstract graph, Orbit organizes your synced content by **course**
/// and **time**, making it instantly clear what needs attention. Each item is directly
/// tappable to open its URL. Items with upcoming due dates pulse with urgency.
///
/// Layout: Course sections → horizontally‑scrollable item cards → type‑icon + title + due badge.
struct CourseBrainOrbitView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let allNodes: [CourseBrainNode]
    let courseSummaries: [CourseBrainCourseSummary]
    @Binding var selectedNodeID: String?
    let highlightedNodeIDs: Set<String>
    let searchText: String
    let onNodeTap: (String) -> Void
    let onNodeOpen: (String) -> Void
    /// Called when user taps the Canvascope import action on a file/PDF item.
    let onImportPDF: (URL, String) -> Void

    // MARK: - State

    @State private var expandedCourseIDs: Set<Int> = []

    // MARK: - Derived Data

    private var courseGroups: [OrbitCourseGroup] {
        buildCourseGroups()
    }

    private var urgentItems: [CourseBrainNode] {
        Self.dueSoonNodes(from: allNodes)
    }

    private var filteredNodes: [CourseBrainNode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return allNodes }
        return allNodes.filter { $0.searchableText.lowercased().contains(query) }
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                // ─── Urgent Strip ───
                if !urgentItems.isEmpty && searchText.isEmpty {
                    urgentSection
                }

                // ─── Course Groups ───
                ForEach(courseGroups) { group in
                    courseSection(group)
                }

                Spacer(minLength: 60)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .background {
            LectraColor.background
            LectraGradient.appBackdrop.opacity(0.58)
        }
    }

    static func dueSoonNodes(from nodes: [CourseBrainNode], now: Date = Date()) -> [CourseBrainNode] {
        let oneWeekFromNow = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now

        return nodes
            .filter { node in
                guard let due = node.metadata.dueAt else { return false }
                if node.metadata.headlineSubmissionStatus?.isCompletionState == true {
                    return false
                }
                return due > now && due <= oneWeekFromNow
            }
            .sorted { lhs, rhs in
                let lhsRank = lhs.metadata.headlineSubmissionStatus?.attentionSortRank ?? CourseBrainSubmissionStatus.unknown.attentionSortRank
                let rhsRank = rhs.metadata.headlineSubmissionStatus?.attentionSortRank ?? CourseBrainSubmissionStatus.unknown.attentionSortRank
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }

                let lhsDate = lhs.metadata.dueAt ?? .distantFuture
                let rhsDate = rhs.metadata.dueAt ?? .distantFuture
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    // MARK: - Urgent Section

    private var urgentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .foregroundColor(LectraColor.accent)
                    .font(LectraTypography.headline)
                Text("Due Soon")
                    .font(LectraTypography.titleSmall)
                    .foregroundColor(LectraColor.textPrimary)
                Text("\(urgentItems.count)")
                    .font(LectraTypography.caption)
                    .foregroundColor(LectraColor.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(LectraColor.surfaceFloating.opacity(0.88))
                            .overlay {
                                Capsule()
                                    .fill(LectraColor.accent.opacity(0.12))
                            }
                    )
                    .clipShape(Capsule())
            }
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(urgentItems) { node in
                        urgentCard(node)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }

            Divider()
                .background(LectraColor.edgeStroke)
                .padding(.top, 8)
        }
        .padding(.bottom, 8)
    }

    private func urgentCard(_ node: CourseBrainNode) -> some View {
        Button {
            onNodeOpen(node.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    typeIcon(node.type)
                        .font(.system(size: 13, weight: .semibold))
                    if let courseName = node.metadata.courseName {
                        Text(abbreviate(courseName, max: 20))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(LectraColor.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                Text(node.title)
                    .font(LectraTypography.bodyEmphasis)
                    .foregroundColor(LectraColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let submissionStatus = node.metadata.headlineSubmissionStatus {
                    submissionBadge(submissionStatus)
                }

                if let due = node.metadata.dueAt {
                    dueBadge(due)
                }
            }
            .padding(16)
            .frame(width: 220, alignment: .leading)
            .background(orbitCardBackground(accent: urgencyAccent(for: node.metadata.dueAt)))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(LectraColor.edgeStroke, lineWidth: 1)
            )
            .lectraShadow(LectraElevation.medium())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Course Sections

    private func courseSection(_ group: OrbitCourseGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // ─── Course Header ───
            Button {
                LectraHaptics.selection()
                if reduceMotion {
                    if expandedCourseIDs.contains(group.courseId) {
                        expandedCourseIDs.remove(group.courseId)
                    } else {
                        expandedCourseIDs.insert(group.courseId)
                    }
                } else {
                    withAnimation(LectraMotion.expand) {
                        if expandedCourseIDs.contains(group.courseId) {
                            expandedCourseIDs.remove(group.courseId)
                        } else {
                            expandedCourseIDs.insert(group.courseId)
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(group.accentColor)
                        .frame(width: 4, height: 24)

                    Text(group.courseName)
                        .font(LectraTypography.headline)
                        .foregroundColor(LectraColor.textPrimary)

                    Text("\(group.items.count)")
                        .font(LectraTypography.caption)
                        .foregroundColor(LectraColor.textTertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(LectraColor.surfaceFloating.opacity(0.88))
                        .clipShape(Capsule())

                    Spacer()

                    Image(systemName: expandedCourseIDs.contains(group.courseId) ? "chevron.up" : "chevron.down")
                        .font(LectraTypography.caption)
                        .foregroundColor(LectraColor.textTertiary)
                }
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            // ─── Items ───
            if expandedCourseIDs.contains(group.courseId) || !searchText.isEmpty {
                LazyVStack(spacing: 2) {
                    ForEach(group.items) { node in
                        itemRow(node, accent: group.accentColor)
                    }
                }
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                // Collapsed preview — show horizontally scrolling pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(group.items.prefix(12)) { node in
                            compactPill(node, accent: group.accentColor)
                        }
                        if group.items.count > 12 {
                            Text("+\(group.items.count - 12) more")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(LectraColor.textTertiary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(LectraColor.surfaceFloating.opacity(0.72))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
                .padding(.bottom, 10)
            }

            Divider()
                .background(LectraColor.edgeStroke.opacity(0.7))
        }
    }

    // MARK: - Item Row (Expanded)

    private func itemRow(_ node: CourseBrainNode, accent: Color) -> some View {
        Button {
            onNodeTap(node.id)
        } label: {
            HStack(spacing: 12) {
                // Type icon
                typeIcon(node.type)
                    .font(LectraTypography.body)
                    .frame(width: 28)

                // Title + module
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.title)
                        .font(LectraTypography.body)
                        .foregroundColor(node.id == selectedNodeID ? LectraColor.textPrimary : LectraColor.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let module = node.metadata.moduleName {
                        Text(module)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(LectraColor.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Due date or action indicator
                if let submissionStatus = node.metadata.headlineSubmissionStatus {
                    submissionBadge(submissionStatus)
                }

                if let due = node.metadata.dueAt {
                    dueBadge(due)
                }

                // Action buttons
                if let url = node.resourceURL {
                    if isPDFLike(node) {
                        Button {
                            LectraHaptics.tap()
                            onImportPDF(url, node.title)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.doc.fill")
                                    .font(LectraTypography.footnoteBold)
                                Text("Open")
                                    .font(LectraTypography.caption)
                            }
                            .foregroundColor(LectraColor.textPrimary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: LectraSizing.minHitTarget)
                            .background(
                                Capsule()
                                    .fill(LectraColor.surfaceFloating.opacity(0.90))
                                    .overlay {
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [accent.opacity(0.42), LectraColor.accent.opacity(0.18)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    }
                                    .overlay {
                                        Capsule()
                                            .stroke(LectraColor.edgeStroke, lineWidth: 1)
                                    }
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        // External link button
                        Button {
                            LectraHaptics.tap()
                            onNodeOpen(node.id)
                        } label: {
                            Image(systemName: "arrow.up.right")
                                .font(LectraTypography.caption)
                                .foregroundColor(LectraColor.textSecondary)
                                .frame(width: LectraSizing.minHitTarget, height: LectraSizing.minHitTarget)
                                .background(
                                    Capsule()
                                        .fill(LectraColor.surfaceFloating.opacity(0.90))
                                        .overlay {
                                            Capsule()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [accent.opacity(0.16), LectraColor.accentCool.opacity(0.06)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                        }
                                        .overlay {
                                            Capsule()
                                                .stroke(LectraColor.edgeStroke, lineWidth: 1)
                                        }
                                )
                                .clipShape(Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(orbitRowBackground(accent: accent, isSelected: node.id == selectedNodeID, isHighlighted: highlightedNodeIDs.contains(node.id)))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(node.id == selectedNodeID ? accent.opacity(0.45) : LectraColor.edgeStroke.opacity(0.65), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Compact Pill (Collapsed)

    private func compactPill(_ node: CourseBrainNode, accent: Color) -> some View {
        Button {
            onNodeTap(node.id)
        } label: {
            HStack(spacing: 6) {
                typeIcon(node.type)
                    .font(LectraTypography.footnote)
                Text(abbreviate(node.title, max: 24))
                    .font(LectraTypography.captionMedium)
                    .foregroundColor(LectraColor.textSecondary)
                    .lineLimit(1)

                if let submissionStatus = node.metadata.headlineSubmissionStatus {
                    Text(submissionStatus.displayTitle)
                        .font(LectraTypography.footnoteBold)
                        .foregroundColor(submissionBadgeForegroundColor(for: submissionStatus))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(submissionBadgeBackgroundColor(for: submissionStatus))
                        .clipShape(Capsule())
                } else if node.metadata.dueAt != nil {
                    Circle()
                        .fill(LectraColor.accentDestructive)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(LectraColor.surfaceFloating.opacity(0.82))
            )
            .overlay(
                Capsule()
                    .stroke(accent.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Due Date Badge

    private func dueBadge(_ date: Date) -> some View {
        let now = Date()
        let isPast = date < now
        let isToday = Calendar.current.isDateInToday(date)
        let isTomorrow = Calendar.current.isDateInTomorrow(date)
        let daysUntil = Calendar.current.dateComponents([.day], from: now, to: date).day ?? 0

        let text: String
        let color: Color
        if isPast {
            text = "Past due"
            color = LectraColor.accentDestructive
        } else if isToday {
            text = "Today"
            color = LectraColor.accentDestructive
        } else if isTomorrow {
            text = "Tomorrow"
            color = LectraColor.warning
        } else if daysUntil <= 7 {
            text = "\(daysUntil)d left"
            color = LectraColor.warning
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            text = formatter.string(from: date)
            color = LectraColor.textTertiary
        }

        return Text(text)
            .font(LectraTypography.footnoteBold)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }

    private func submissionBadge(_ status: CourseBrainSubmissionStatus) -> some View {
        Text(status.displayTitle)
            .font(LectraTypography.footnoteBold)
            .foregroundColor(submissionBadgeForegroundColor(for: status))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(submissionBadgeBackgroundColor(for: status))
            .clipShape(Capsule())
    }

    private func submissionBadgeForegroundColor(for status: CourseBrainSubmissionStatus) -> Color {
        switch status {
        case .submitted:
            return Color(hex: 0xB7E8C5)
        case .late:
            return Color(hex: 0xFFE0A3)
        case .missing:
            return Color(hex: 0xFFC0BA)
        case .excused:
            return Color(hex: 0xF2D2C8)
        case .notSubmitted:
            return LectraColor.textSecondary
        case .unknown:
            return LectraColor.textTertiary
        }
    }

    private func submissionBadgeBackgroundColor(for status: CourseBrainSubmissionStatus) -> Color {
        switch status {
        case .submitted:
            return Color(hex: 0x183A28)
        case .late:
            return Color(hex: 0x5A3414)
        case .missing:
            return Color(hex: 0x5A211D)
        case .excused:
            return Color(hex: 0x3A2824)
        case .notSubmitted:
            return LectraColor.surfaceFloating.opacity(0.86)
        case .unknown:
            return LectraColor.surfaceFloating.opacity(0.66)
        }
    }

    private func orbitCardBackground(accent: Color, cornerRadius: CGFloat = LectraRadius.card) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LectraColor.surfaceElevated.opacity(0.88))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.16), LectraColor.accentCool.opacity(0.06), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private func orbitRowBackground(accent: Color, isSelected: Bool, isHighlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: LectraRadius.control, style: .continuous)
            .fill(
                isSelected
                    ? accent.opacity(0.18)
                    : LectraColor.surfaceFloating.opacity(isHighlighted ? 0.86 : 0.58)
            )
    }

    private func urgencyAccent(for dueDate: Date?) -> Color {
        guard let dueDate else { return LectraColor.accentCool }
        let hours = Calendar.current.dateComponents([.hour], from: Date(), to: dueDate).hour ?? 999
        if hours < 24 { return LectraColor.accentDestructive }
        if hours < 72 { return LectraColor.warning }
        return LectraColor.accentCool
    }

    // MARK: - Helpers

    private func typeIcon(_ type: CourseBrainNodeType) -> some View {
        let (icon, color): (String, Color) = {
            switch type {
            case .topic:     return ("folder.fill", Color(hex: 0xD95E53))
            case .assignment: return ("doc.text.fill", LectraColor.warning)
            case .lecture:   return ("book.fill", Color(hex: 0xB56A55))
            case .note:      return ("note.text", Color(hex: 0xAEB878))
            case .file:      return ("doc.fill", LectraColor.paperMuted)
            case .concept:   return ("lightbulb.fill", Color(hex: 0xD9A18D))
            }
        }()

        return Image(systemName: icon)
            .foregroundColor(color)
    }

    private func urgencyGradient(for dueDate: Date?) -> LinearGradient {
        guard let due = dueDate else {
            return LectraGlass.urgentCardDefault
        }

        let hours = Calendar.current.dateComponents([.hour], from: Date(), to: due).hour ?? 999
        if hours < 24 {
            return LectraGlass.urgentCardCritical
        } else if hours < 72 {
            return LectraGlass.urgentCardWarning
        }
        return LectraGlass.urgentCardDefault
    }

    private func abbreviate(_ text: String, max: Int) -> String {
        text.count <= max ? text : String(text.prefix(max - 1)) + "…"
    }

    /// Returns true if a node looks like a PDF or downloadable file.
    private func isPDFLike(_ node: CourseBrainNode) -> Bool {
        if node.type == .file { return true }
        let titleLower = node.title.lowercased()
        if titleLower.hasSuffix(".pdf") { return true }
        if let urlStr = node.resourceURL?.absoluteString.lowercased() {
            if urlStr.contains("/files/") || urlStr.hasSuffix(".pdf") { return true }
        }
        return false
    }

    // MARK: - Data Building

    private let coursePalette: [Color] = [
        LectraColor.accent,
        LectraColor.accentSoft,
        LectraColor.warning,
        Color(hex: 0xD9A18D),
        Color(hex: 0xB56A55),
        Color(hex: 0xAEB878),
        LectraColor.paperMuted,
        Color(hex: 0x8E5750),
    ]

    private func buildCourseGroups() -> [OrbitCourseGroup] {
        let nodes = filteredNodes.filter { $0.type != .concept } // hide derived concepts

        // Group by courseId
        var grouped: [Int: (name: String, items: [CourseBrainNode])] = [:]
        for node in nodes {
            let courseId = node.courseId ?? -1
            let name = node.metadata.courseName ?? "Other"
            grouped[courseId, default: (name: name, items: [])].items.append(node)
        }

        // Sort groups by most items first
        let sorted = grouped.sorted { $0.value.items.count > $1.value.items.count }

        return sorted.enumerated().map { (index, entry) in
            let items = entry.value.items.sorted { lhs, rhs in
                // Priority: type weight → due date → title
                let lhsWeight = typeWeight(lhs.type)
                let rhsWeight = typeWeight(rhs.type)
                if lhsWeight != rhsWeight { return lhsWeight < rhsWeight }
                let lhsSubmissionRank = lhs.metadata.headlineSubmissionStatus?.attentionSortRank ?? CourseBrainSubmissionStatus.unknown.attentionSortRank
                let rhsSubmissionRank = rhs.metadata.headlineSubmissionStatus?.attentionSortRank ?? CourseBrainSubmissionStatus.unknown.attentionSortRank
                if lhsSubmissionRank != rhsSubmissionRank { return lhsSubmissionRank < rhsSubmissionRank }
                let lhsDate = lhs.metadata.dueAt ?? .distantFuture
                let rhsDate = rhs.metadata.dueAt ?? .distantFuture
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

            return OrbitCourseGroup(
                courseId: entry.key,
                courseName: entry.value.name,
                items: items,
                accentColor: coursePalette[index % coursePalette.count]
            )
        }
    }

    private func typeWeight(_ type: CourseBrainNodeType) -> Int {
        switch type {
        case .assignment: return 0 // show first
        case .lecture:    return 1
        case .note:       return 2
        case .file:       return 3
        case .topic:      return 4
        case .concept:    return 5
        }
    }
}

// MARK: - Data Types

private struct OrbitCourseGroup: Identifiable {
    let courseId: Int
    let courseName: String
    let items: [CourseBrainNode]
    let accentColor: Color

    var id: Int { courseId }
}
