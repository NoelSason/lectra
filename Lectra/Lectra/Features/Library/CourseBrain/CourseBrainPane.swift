import SwiftUI

struct CourseBrainPane: View {
    let documents: [LocalDocument]

    @StateObject private var viewModel = CourseBrainViewModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            HStack(spacing: 0) {
                leftPanel
                    .frame(width: 290)

                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 1)

                centerPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 1)

                rightPanel
                    .frame(width: 370)
            }
        }
        .background(Color.black)
        .onAppear {
            viewModel.load(documents: documents)
        }
        .onChange(of: documents.map(\ .id)) { _, _ in
            viewModel.updateLocalDocuments(documents)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Text("Course Brain")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.96))

                Spacer(minLength: 0)

                Picker("Mode", selection: $viewModel.displayMode) {
                    ForEach(CourseBrainDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            HStack(spacing: 12) {
                CourseBrainSearchBar(
                    text: $viewModel.searchText,
                    placeholder: "Search concept, assignment, lecture, or file",
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

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Filters")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.top, 12)
                .padding(.horizontal, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    courseChip(title: "All Courses", isSelected: viewModel.courseFilter == nil) {
                        viewModel.setCourseFilter(nil)
                    }

                    ForEach(viewModel.courseSummaries) { course in
                        courseChip(
                            title: "\(course.name) (\(course.count))",
                            isSelected: viewModel.courseFilter == course.id
                        ) {
                            viewModel.setCourseFilter(course.id)
                        }
                    }
                }
                .padding(.horizontal, 14)
            }

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
                                .font(.system(size: 15, weight: .medium))
                            Spacer(minLength: 0)
                        }
                        .foregroundColor(.white.opacity(viewModel.leftSection == section ? 0.96 : 0.74))
                        .padding(.horizontal, 12)
                        .frame(height: 38)
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
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(node.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white)
                                        .lineLimit(2)
                                    if let courseName = node.metadata.courseName {
                                        Text(courseName)
                                            .font(.system(size: 11, weight: .regular))
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

    private func courseChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
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
            } else if let graph = viewModel.graph, !graph.nodes.isEmpty {
                CourseBrainGraphCanvas(
                    graph: graph,
                    positions: viewModel.nodePositions,
                    selectedNodeID: $viewModel.selectedNodeID,
                    highlightedNodeIDs: viewModel.highlightedNodeIDs,
                    onNodeTap: { nodeID in
                        viewModel.selectNode(nodeID)
                    }
                )

                HStack(spacing: 8) {
                    Button {
                        viewModel.setFocusSelectionOnly(!viewModel.focusSelectionOnly)
                    } label: {
                        Text(viewModel.focusSelectionOnly ? "Show Full Graph" : "Expand Connections")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(hex: 0x251E21).opacity(0.95))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 16)
                .padding(.top, 14)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.8))
                    Text("No Course Brain data yet")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Import course content or notes to start building your graph.")
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
                if let selected = viewModel.selectedNode() {
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

                    if selected.type == .assignment {
                        assignmentWorkspace(for: selected)
                    }

                    if selected.type == .note {
                        manualLinkEditor(for: selected)
                    }

                    relationshipSection(for: selected)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Node Details")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Select any node in Course Brain to inspect linked lectures, assignments, files, and notes.")
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

    private func assignmentWorkspace(for node: CourseBrainNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Assignment Workspace")

            if let instructions = node.metadata.bestInstructionText {
                Text(instructions)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.82))
                    .lineLimit(10)
            } else {
                Text("No assignment instructions found in indexed metadata.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.62))
            }

            if let dueAt = node.metadata.dueAt {
                detailRow(label: "Due", value: dueAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let unlockAt = node.metadata.unlockAt {
                detailRow(label: "Unlock", value: unlockAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let lockAt = node.metadata.lockAt {
                detailRow(label: "Lock", value: lockAt.formatted(date: .abbreviated, time: .shortened))
            }

            if let url = node.resourceURL {
                Button {
                    openURL(url)
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
        let assignments = viewModel.relatedNodes(for: node.id, type: .assignment)
        let lectures = viewModel.relatedNodes(for: node.id, type: .lecture)
        let files = viewModel.relatedNodes(for: node.id, type: .file)
        let concepts = viewModel.relatedNodes(for: node.id, type: .concept)

        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Relationships")

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

            if concepts.isEmpty && notes.isEmpty && assignments.isEmpty && lectures.isEmpty && files.isEmpty {
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

    fileprivate func nodeColor(_ type: CourseBrainNodeType) -> Color {
        switch type {
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
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white)
            } else {
                Text(placeholder)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.48))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(Color(hex: 0x171A22))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct CourseBrainGraphCanvas: View {
    let graph: CourseBrainGraph
    let positions: [String: CGPoint]
    @Binding var selectedNodeID: String?
    let highlightedNodeIDs: Set<String>
    let onNodeTap: (String) -> Void

    @State private var scale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(hex: 0x070708)
                    .ignoresSafeArea()

                Canvas { context, _ in
                    drawEdges(in: &context, size: proxy.size)
                }

                ForEach(graph.nodes) { node in
                    if let position = positions[node.id] {
                        Button {
                            onNodeTap(node.id)
                        } label: {
                            CourseBrainNodeBubble(
                                node: node,
                                isSelected: selectedNodeID == node.id,
                                isHighlighted: highlightedNodeIDs.contains(node.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .position(screenPoint(for: position, size: proxy.size))
                    }
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        panOffset.width += value.translation.width
                        panOffset.height += value.translation.height
                        dragOffset = .zero
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = min(max(value, 0.55), 2.4)
                    }
            )
            .onChange(of: selectedNodeID) { _, newValue in
                guard let newValue, let point = positions[newValue] else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    center(on: point, viewport: proxy.size)
                }
            }
            .onAppear {
                if let selectedNodeID, let point = positions[selectedNodeID] {
                    center(on: point, viewport: proxy.size)
                }
            }
        }
    }

    private func drawEdges(in context: inout GraphicsContext, size: CGSize) {
        for edge in graph.edges {
            guard let source = positions[edge.source], let target = positions[edge.target] else { continue }
            let sourcePoint = screenPoint(for: source, size: size)
            let targetPoint = screenPoint(for: target, size: size)

            var path = Path()
            path.move(to: sourcePoint)
            path.addLine(to: targetPoint)

            let strokeColor: Color = edge.relationship == .manualLink ? Color(hex: 0xE84D4D) : Color.white.opacity(0.24)
            context.stroke(path, with: .color(strokeColor), style: StrokeStyle(lineWidth: edge.relationship == .manualLink ? 2.2 : 1.2, lineCap: .round))

            if edge.directional {
                let arrowPath = arrowHead(from: sourcePoint, to: targetPoint)
                context.fill(arrowPath, with: .color(strokeColor.opacity(0.95)))
            }
        }
    }

    private func arrowHead(from start: CGPoint, to end: CGPoint) -> Path {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 9
        let spread: CGFloat = .pi / 6

        let p1 = CGPoint(
            x: end.x - cos(angle - spread) * length,
            y: end.y - sin(angle - spread) * length
        )
        let p2 = CGPoint(
            x: end.x - cos(angle + spread) * length,
            y: end.y - sin(angle + spread) * length
        )

        var path = Path()
        path.move(to: end)
        path.addLine(to: p1)
        path.addLine(to: p2)
        path.closeSubpath()
        return path
    }

    private func screenPoint(for worldPoint: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: ((worldPoint.x - 390) * scale) + (size.width / 2) + panOffset.width + dragOffset.width,
            y: ((worldPoint.y - 390) * scale) + (size.height / 2) + panOffset.height + dragOffset.height
        )
    }

    private func center(on worldPoint: CGPoint, viewport: CGSize) {
        panOffset = CGSize(
            width: -((worldPoint.x - 390) * scale),
            height: -((worldPoint.y - 390) * scale)
        )
    }
}

private struct CourseBrainNodeBubble: View {
    let node: CourseBrainNode
    let isSelected: Bool
    let isHighlighted: Bool

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(nodeColor)
                .frame(width: isSelected ? 20 : 16, height: isSelected ? 20 : 16)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isSelected || isHighlighted ? 0.9 : 0.25), lineWidth: isSelected ? 2 : 1)
                )

            Text(node.title)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundColor(.white.opacity(isSelected || isHighlighted ? 0.95 : 0.75))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 110)
        }
        .padding(.horizontal, 4)
    }

    private var nodeColor: Color {
        switch node.type {
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
