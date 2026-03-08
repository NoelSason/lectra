import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private extension CGSize {
    var midX: CGFloat { width / 2 }
    var midY: CGFloat { height / 2 }
}

struct CourseBrainPane: View {
    let documents: [LocalDocument]
    /// Called when user wants to download a PDF from a URL and import it into Lectra.
    var onImportPDF: ((URL, String) -> Void)?

    @StateObject private var viewModel = CourseBrainViewModel()
    @Environment(\.openURL) private var openURL
    @State private var isLeftPanelVisible = true
    @State private var isRightPanelVisible = true
    @State private var isCoursePickerPresented = false
    @State private var coursePickerSearchText = ""

    var body: some View {
        GeometryReader { proxy in
            let layout = panelLayout(for: proxy.size.width)
            let showsLeftPanel = isLeftPanelVisible || !layout.isCompact
            let showsRightPanel = isRightPanelVisible || !layout.isCompact

            VStack(alignment: .leading, spacing: 0) {
                header(isCompact: layout.isCompact)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)

                HStack(spacing: 0) {
                    if showsLeftPanel {
                        leftPanel
                            .frame(width: layout.leftPanelWidth)

                        Rectangle()
                            .fill(Color.white.opacity(0.04))
                            .frame(width: 1)
                    }

                    centerPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showsRightPanel {
                        Rectangle()
                            .fill(Color.white.opacity(0.04))
                            .frame(width: 1)

                        rightPanel
                            .frame(width: layout.rightPanelWidth)
                    }
                }
            }
            .background(Color.black)
        }
        .onAppear {
            viewModel.load(documents: documents)
        }
        .onChange(of: documents.map(\.id)) { _, _ in
            viewModel.updateLocalDocuments(documents)
        }
    }

    private func header(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Text("Course Brain")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.96))

                Spacer(minLength: 0)

                if isCompact {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLeftPanelVisible.toggle()
                        }
                    } label: {
                        Image(systemName: isLeftPanelVisible ? "sidebar.left" : "sidebar.left.hide")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 38, height: 34)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRightPanelVisible.toggle()
                        }
                    } label: {
                        Image(systemName: isRightPanelVisible ? "sidebar.right" : "sidebar.right.hide")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 38, height: 34)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Picker("Mode", selection: $viewModel.displayMode) {
                    ForEach(CourseBrainDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: isCompact ? 210 : 220)
            }

            HStack(spacing: 12) {
                CourseBrainSearchBar(
                    text: $viewModel.searchText,
                    placeholder: "Search topic, concept, or assignment",
                    isEditable: true
                )

                if let graph = viewModel.graph, graph.isCapped {
                    Text("Showing \(graph.nodes.count)/\(graph.fullNodeCount) nodes")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(hex: 0x251E21))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func panelLayout(for totalWidth: CGFloat) -> CourseBrainPanelLayout {
        let compact = totalWidth < 1_180

        if compact {
            let left = min(max(totalWidth * 0.23, 192), 232)
            let right = min(max(totalWidth * 0.30, 248), 300)
            return CourseBrainPanelLayout(isCompact: true, leftPanelWidth: left, rightPanelWidth: right)
        }

        let left = min(max(totalWidth * 0.20, 220), 252)
        let right = min(max(totalWidth * 0.28, 286), 328)
        return CourseBrainPanelLayout(isCompact: false, leftPanelWidth: left, rightPanelWidth: right)
    }

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Filters")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .padding(.top, 12)
                .padding(.horizontal, 14)

            classPickerButton
                .padding(.horizontal, 12)

            VStack(spacing: 6) {
                ForEach(CourseBrainLeftSection.allCases) { section in
                    Button {
                        viewModel.leftSection = section
                        if section == .timeline {
                            viewModel.displayMode = .timeline
                        } else if viewModel.displayMode == .timeline {
                            viewModel.displayMode = .graph
                        }
                    } label: {
                        HStack {
                            Text(section.rawValue)
                                .font(.system(size: 16, weight: .medium))
                            Spacer(minLength: 0)
                        }
                        .foregroundColor(.white.opacity(viewModel.leftSection == section ? 0.96 : 0.74))
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(viewModel.leftSection == section ? Color(hex: 0x4A222A) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)

            if viewModel.leftSection != .timeline {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.nodesForLeftSection(viewModel.leftSection)) { node in
                            Button {
                                viewModel.selectNode(node.id)
                                viewModel.displayMode = .graph
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text(node.title)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.white)
                                            .lineLimit(2)

                                        if node.type == .topic {
                                            topicCountBadge(topicID: node.id)
                                        }
                                    }

                                    if let courseName = node.metadata.courseName {
                                        Text(courseName)
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(.white.opacity(0.64))
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(viewModel.selectedNodeID == node.id ? Color.white.opacity(0.14) : Color.white.opacity(0.04))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }

            Spacer(minLength: 0)
        }
        .background(Color(hex: 0x0E0E10))
    }

    private var classPickerButton: some View {
        Button {
            isCoursePickerPresented = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "graduationcap")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.88))

                Text(selectedCourseTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let courseFilter = viewModel.courseFilter {
                    Text(courseCountText(for: courseFilter))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.72))
                        .lineLimit(1)
                }

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.72))
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isCoursePickerPresented, arrowEdge: .top) {
            coursePickerPopover
        }
    }

    private var coursePickerPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose Class")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            CourseBrainSearchBar(
                text: $coursePickerSearchText,
                placeholder: "Search classes",
                isEditable: true
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    Button {
                        applyCourseFilter(nil)
                    } label: {
                        coursePickerRow(
                            title: "All Courses",
                            subtitle: "\(viewModel.courseSummaries.map(\.count).reduce(0, +)) items",
                            isSelected: viewModel.courseFilter == nil
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(filteredCourseSummaries) { course in
                        Button {
                            applyCourseFilter(course.id)
                        } label: {
                            coursePickerRow(
                                title: course.name,
                                subtitle: "\(course.count) items",
                                isSelected: viewModel.courseFilter == course.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 360, height: 420)
        .background(Color(hex: 0x121317))
    }

    private func coursePickerRow(title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(subtitle)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(Color.white.opacity(0.62))
                .lineLimit(1)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: 0xE84D4D))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.04))
        )
    }

    private func applyCourseFilter(_ courseId: Int?) {
        viewModel.setCourseFilter(courseId)
        coursePickerSearchText = ""
        isCoursePickerPresented = false
    }

    private var filteredCourseSummaries: [CourseBrainCourseSummary] {
        let query = normalizeCourseQuery(coursePickerSearchText)
        let sorted = viewModel.courseSummaries.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { course in
            normalizeCourseQuery(course.name).contains(query)
        }
    }

    private var selectedCourseTitle: String {
        guard let selectedId = viewModel.courseFilter else { return "All Courses" }
        return viewModel.courseSummaries.first(where: { $0.id == selectedId })?.name ?? "Course \(selectedId)"
    }

    private func courseCountText(for courseId: Int) -> String {
        guard let course = viewModel.courseSummaries.first(where: { $0.id == courseId }) else {
            return ""
        }
        return "\(course.count)"
    }

    private func normalizeCourseQuery(_ raw: String) -> String {
        raw
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func courseChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color(hex: 0x4A222A) : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private var centerPanel: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.isLoading {
                ProgressView("Loading Course Brain")
                    .tint(Color(hex: 0xE84D4D))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.displayMode == .timeline {
                timelinePanel
            } else if !viewModel.allNodes.isEmpty {
                CourseBrainOrbitView(
                    allNodes: viewModel.allNodes,
                    courseSummaries: viewModel.courseSummaries,
                    selectedNodeID: $viewModel.selectedNodeID,
                    highlightedNodeIDs: viewModel.highlightedNodeIDs,
                    searchText: viewModel.searchText,
                    onNodeTap: { nodeID in
                        viewModel.selectNode(nodeID)
                    },
                    onNodeOpen: { nodeID in
                        if let node = viewModel.node(for: nodeID),
                           let url = node.resourceURL {
                            openURL(url)
                        }
                    },
                    onImportPDF: { url, title in
                        onImportPDF?(url, title)
                    }
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.8))
                    Text("No Course Brain data yet")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Import course content or notes to start building your topic graph.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let message = viewModel.bannerMessage {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(hex: 0x53242C).opacity(0.94))
                    .clipShape(Capsule())
                    .padding(.leading, 16)
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color(hex: 0x0A0A0B))
        .clipped()
    }

    private var timelinePanel: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.timelineBuckets) { bucket in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button {
                                viewModel.toggleTimelineBucket(bucket.id)
                            } label: {
                                Image(systemName: viewModel.collapsedTimelineBuckets.contains(bucket.id) ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.9))
                            }
                            .buttonStyle(.plain)

                            Text(bucket.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)

                            Spacer(minLength: 0)
                        }

                        if !viewModel.collapsedTimelineBuckets.contains(bucket.id) {
                            ForEach(bucket.items) { item in
                                Button {
                                    viewModel.selectTimelineItem(item.id)
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Circle()
                                            .fill(nodeColor(item.type))
                                            .frame(width: 10, height: 10)
                                            .padding(.top, 5)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.white)
                                                .lineLimit(2)
                                            Text(item.type.rawValue.capitalized)
                                                .font(.system(size: 11, weight: .regular))
                                                .foregroundColor(.white.opacity(0.62))
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(viewModel.selectedNodeID == item.id ? Color.white.opacity(0.14) : Color.white.opacity(0.05))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                }
            }
            .padding(16)
        }
    }

    private var rightPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let leaf = viewModel.selectedLeafSummary() {
                    leafDetailWorkspace(for: leaf)
                } else if let selected = viewModel.selectedNode() {
                    Text(selected.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)

                    HStack(spacing: 8) {
                        Text(selected.type.rawValue.capitalized)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(nodeColor(selected.type).opacity(0.8))
                            .clipShape(Capsule())

                        if let courseName = selected.metadata.courseName {
                            Text(courseName)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(Color.white.opacity(0.78))
                                .lineLimit(1)
                        }
                    }

                    if selected.type == .topic {
                        topicWorkspace(for: selected)
                    }

                    if selected.type == .assignment {
                        assignmentWorkspace(for: selected)
                    }

                    if selected.type == .note {
                        manualLinkEditor(for: selected)
                    }

                    if selected.type != .topic {
                        relationshipSection(for: selected)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Node Details")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Select any node in Course Brain to inspect linked topics, concepts, and resources.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.68))
                    }
                    .padding(.top, 8)
                }
            }
            .padding(16)
        }
        .background(Color(hex: 0x111114))
    }

    private func topicWorkspace(for topicNode: CourseBrainNode) -> some View {
        let concepts = viewModel.topicConceptNodes(topicID: topicNode.id)
        let assignments = viewModel.topicLeaves(topicID: topicNode.id, type: .assignment)
        let lectures = viewModel.topicLeaves(topicID: topicNode.id, type: .lecture)
        let files = viewModel.topicLeaves(topicID: topicNode.id, type: .file)

        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Topic Workspace")

            if let description = topicNode.metadata.description {
                Text(description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.75))
            }

            if !concepts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Related Concepts")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.74))

                    WrapFlowLayout(items: concepts.map { $0.title }) { title in
                        Text(title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color(hex: 0x352445))
                            .clipShape(Capsule())
                    }
                }
            }

            if !assignments.isEmpty {
                topicLeafGroup(title: "Assignments", leaves: assignments)
            }
            if !lectures.isEmpty {
                topicLeafGroup(title: "Lectures", leaves: lectures)
            }
            if !files.isEmpty {
                topicLeafGroup(title: "Files", leaves: files)
            }

            if assignments.isEmpty && lectures.isEmpty && files.isEmpty {
                Text("No items in this topic yet.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.62))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func topicLeafGroup(title: String, leaves: [CourseBrainLeafSummary]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.74))

            ForEach(leaves.prefix(12)) { leaf in
                Button {
                    viewModel.selectTopicLeaf(leaf.id)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(nodeColor(leaf.type))
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(leaf.title)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.white)
                                .lineLimit(2)

                            if let dueAt = leaf.dueAt {
                                Text("Due \(dueAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(viewModel.highlightedLeafID == leaf.id ? Color.white.opacity(0.14) : Color.white.opacity(0.05))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func leafDetailWorkspace(for leaf: CourseBrainLeafSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(leaf.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)

            HStack(spacing: 8) {
                Text(leaf.type.rawValue.capitalized)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(nodeColor(leaf.type).opacity(0.85))
                    .clipShape(Capsule())

                if let moduleName = leaf.moduleName {
                    Text(moduleName)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }

            if leaf.type == .assignment {
                assignmentWorkspace(for: leaf)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if let dueAt = leaf.dueAt {
                        detailRow(label: "Due", value: dueAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let unlockAt = leaf.unlockAt {
                        detailRow(label: "Unlock", value: unlockAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let lockAt = leaf.lockAt {
                        detailRow(label: "Lock", value: lockAt.formatted(date: .abbreviated, time: .shortened))
                    }

                    if let url = leaf.url {
                        Button {
                            openResourceURL(url, preferCanvasApp: true)
                        } label: {
                            Label("Open Resource", systemImage: "arrow.up.right.square")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color(hex: 0x4A222A))
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
            }
        }
    }

    private func assignmentWorkspace(for node: CourseBrainNode) -> some View {
        return assignmentWorkspace(
            title: node.title,
            instructions: node.metadata.bestInstructionText,
            dueAt: node.metadata.dueAt,
            unlockAt: node.metadata.unlockAt,
            lockAt: node.metadata.lockAt,
            url: node.resourceURL
        )
    }

    private func assignmentWorkspace(for leaf: CourseBrainLeafSummary) -> some View {
        let backingNode = viewModel.node(for: leaf.id)
        return assignmentWorkspace(
            title: leaf.title,
            instructions: backingNode?.metadata.bestInstructionText ?? leaf.instructionPreview,
            dueAt: leaf.dueAt,
            unlockAt: leaf.unlockAt,
            lockAt: leaf.lockAt,
            url: leaf.url
        )
    }

    private func assignmentWorkspace(
        title: String,
        instructions: String?,
        dueAt: Date?,
        unlockAt: Date?,
        lockAt: Date?,
        url: URL?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Assignment Workspace")

            if let instructions {
                Text(instructions)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.82))
                    .lineLimit(12)
            } else {
                Text("No assignment instructions found in indexed metadata.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.62))
            }

            if let dueAt {
                detailRow(label: "Due", value: dueAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let unlockAt {
                detailRow(label: "Unlock", value: unlockAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let lockAt {
                detailRow(label: "Lock", value: lockAt.formatted(date: .abbreviated, time: .shortened))
            }

            if let url {
                if isCanvasURL(url) {
                    HStack(spacing: 8) {
                        Button {
                            openResourceURL(url, preferCanvasApp: true)
                        } label: {
                            Label("Open in Canvas App", systemImage: "ipad.and.arrow.forward")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color(hex: 0x4A222A))
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            openResourceURL(url, preferCanvasApp: false)
                        } label: {
                            Label("Open Web Link", systemImage: "link")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.88))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button {
                        openResourceURL(url, preferCanvasApp: false)
                    } label: {
                        Label("Open Submission / Assignment", systemImage: "arrow.up.right.square")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color(hex: 0x4A222A))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func manualLinkEditor(for node: CourseBrainNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Link This Note")

            HStack(spacing: 8) {
                Menu {
                    ForEach(viewModel.allNodes.filter { $0.type == .concept }) { target in
                        Button(target.title) {
                            viewModel.createManualLink(from: node.id, to: target.id, relationship: .references)
                        }
                    }
                } label: {
                    linkMenuLabel("Link to Concept", icon: "lightbulb")
                }

                Menu {
                    ForEach(viewModel.allNodes.filter { $0.type == .assignment }) { target in
                        Button(target.title) {
                            viewModel.createManualLink(from: node.id, to: target.id, relationship: .references)
                        }
                    }
                } label: {
                    linkMenuLabel("Link to Assignment", icon: "checklist")
                }
            }

            Menu {
                ForEach(viewModel.allNodes.filter { $0.type == .lecture }) { target in
                    Button(target.title) {
                        viewModel.createManualLink(from: node.id, to: target.id, relationship: .references)
                    }
                }
            } label: {
                linkMenuLabel("Link to Lecture", icon: "book")
            }

            let links = viewModel.manualLinksForSelectedNote()
            if !links.isEmpty {
                ForEach(links, id: \.edge.id) { linked in
                    HStack {
                        Text(linked.target.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(2)

                        Spacer(minLength: 0)

                        Button {
                            viewModel.deleteManualLink(linked.edge)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: 0xE84D4D))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func relationshipSection(for node: CourseBrainNode) -> some View {
        let notes = viewModel.relatedNodes(for: node.id, type: .note)
        let topics = viewModel.relatedNodes(for: node.id, type: .topic)
        let assignments = viewModel.relatedNodes(for: node.id, type: .assignment)
        let lectures = viewModel.relatedNodes(for: node.id, type: .lecture)
        let files = viewModel.relatedNodes(for: node.id, type: .file)
        let concepts = viewModel.relatedNodes(for: node.id, type: .concept)

        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Relationships")

            if !topics.isEmpty {
                relatedGroup(title: "Topics", nodes: topics)
            }
            if !concepts.isEmpty {
                relatedGroup(title: "Concepts", nodes: concepts)
            }
            if !notes.isEmpty {
                relatedGroup(title: "Notes", nodes: notes)
            }
            if !assignments.isEmpty {
                relatedGroup(title: "Assignments", nodes: assignments)
            }
            if !lectures.isEmpty {
                relatedGroup(title: "Lectures", nodes: lectures)
            }
            if !files.isEmpty {
                relatedGroup(title: "Files / Resources", nodes: files)
            }

            if topics.isEmpty && concepts.isEmpty && notes.isEmpty && assignments.isEmpty && lectures.isEmpty && files.isEmpty {
                Text("No linked nodes yet.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.65))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func relatedGroup(title: String, nodes: [CourseBrainNode]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.72))

            ForEach(nodes.prefix(8)) { related in
                Button {
                    viewModel.selectNode(related.id)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(nodeColor(related.type))
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)

                        Text(related.title)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white)
                            .lineLimit(2)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func linkMenuLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.7))
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private func topicCountBadge(topicID: String) -> some View {
        let count = viewModel.topicMemberCount(topicID: topicID)
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.88))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
        }
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

        // Support schools that use custom domains for Canvas.
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
        // Prefer the documented Canvas courses deep-link scheme for direct content routes.
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
                self.openCanvasDeepLinkCandidates(candidates, fallbackURL: fallbackURL, index: index + 1)
            }
        }
#endif
    }

    fileprivate func nodeColor(_ type: CourseBrainNodeType) -> Color {
        switch type {
        case .topic:
            return Color(hex: 0xD5648A)
        case .lecture:
            return Color(hex: 0x4C8DFF)
        case .assignment:
            return Color(hex: 0xFF9F45)
        case .note:
            return Color(hex: 0x46C97A)
        case .file:
            return Color(hex: 0x9AA0AA)
        case .concept:
            return Color(hex: 0xA06DFF)
        }
    }
}

private struct CourseBrainPanelLayout {
    let isCompact: Bool
    let leftPanelWidth: CGFloat
    let rightPanelWidth: CGFloat
}

private struct WrapFlowLayout<ItemContent: View>: View {
    let items: [String]
    @ViewBuilder let itemView: (String) -> ItemContent

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                itemView(item)
            }
        }
    }
}

private struct CourseBrainSearchBar: View {
    @Binding var text: String
    let placeholder: String
    let isEditable: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(Color.white.opacity(0.48))

            if isEditable {
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.white)
            } else {
                Text(placeholder)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.48))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(Color(hex: 0x171A22))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// NOTE: The graph canvas is now rendered via CourseBrainSpriteScene + CourseBrainSpriteView (SpriteKit).
