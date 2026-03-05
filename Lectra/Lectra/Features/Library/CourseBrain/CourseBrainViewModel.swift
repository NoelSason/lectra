import Foundation
import Combine
import CoreGraphics

@MainActor
final class CourseBrainViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var graph: CourseBrainGraph?
    @Published private(set) var allNodes: [CourseBrainNode] = []
    @Published private(set) var allEdges: [CourseBrainEdge] = []
    @Published private(set) var nodePositions: [String: CGPoint] = [:]
    @Published private(set) var courseSummaries: [CourseBrainCourseSummary] = []
    @Published private(set) var timelineBuckets: [CourseBrainTimelineBucket] = []

    @Published var searchText = ""
    @Published var selectedNodeID: String?
    @Published var highlightedNodeIDs: Set<String> = []
    @Published var leftSection: CourseBrainLeftSection = .concepts
    @Published var displayMode: CourseBrainDisplayMode = .graph
    @Published var courseFilter: Int? = nil
    @Published var focusSelectionOnly = false
    @Published var bannerMessage: String?
    @Published var collapsedTimelineBuckets: Set<String> = []

    private let repository = CourseBrainRepository()
    private let graphBuilder = CourseBrainGraphBuilder.shared
    private let layoutCache = CourseBrainLayoutCache.shared

    private var allPositions: [String: CGPoint] = [:]
    private var sourceRecords: [CourseBrainSourceRecord] = []
    private var syncedNoteNodes: [CourseBrainNode] = []
    private var manualLinks: [CourseBrainManualLink] = []
    private var localDocuments: [LocalDocument] = []
    private var baseFingerprint = ""

    private var searchCancellable: AnyCancellable?
    private var bannerTask: Task<Void, Never>?
    private var rebuildTask: Task<Void, Never>?

    init() {
        searchCancellable = $searchText
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] query in
                self?.applySearch(query)
            }
    }

    deinit {
        bannerTask?.cancel()
        rebuildTask?.cancel()
    }

    func load(documents: [LocalDocument]) {
        localDocuments = documents
        rebuildTask?.cancel()

        rebuildTask = Task { [weak self] in
            guard let self else { return }
            await self.fetchAndBuild()
        }
    }

    func updateLocalDocuments(_ documents: [LocalDocument]) {
        localDocuments = documents
        rebuildTask?.cancel()

        rebuildTask = Task { [weak self] in
            guard let self else { return }
            await self.rebuildFromCurrentData()
        }
    }

    func setCourseFilter(_ courseId: Int?) {
        guard courseFilter != courseId else { return }
        courseFilter = courseId

        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            guard let self else { return }
            await self.rebuildFromCurrentData()
        }
    }

    func setFocusSelectionOnly(_ isFocused: Bool) {
        focusSelectionOnly = isFocused
        applyFocusAndCapping(reapplySearch: true)
    }

    func selectNode(_ id: String?) {
        selectedNodeID = id
        if let id {
            leftSection = sectionForNode(id: id)
        }
        applyFocusAndCapping(reapplySearch: true)
    }

    func selectTimelineItem(_ nodeID: String) {
        displayMode = .graph
        selectedNodeID = nodeID
        applyFocusAndCapping(reapplySearch: true)
    }

    func nodesForLeftSection(_ section: CourseBrainLeftSection) -> [CourseBrainNode] {
        switch section {
        case .concepts:
            return allNodes.filter { $0.type == .concept }
        case .assignments:
            return allNodes.filter { $0.type == .assignment }
        case .lectures:
            return allNodes.filter { $0.type == .lecture }
        case .files:
            return allNodes.filter { $0.type == .file }
        case .timeline:
            return []
        }
    }

    func selectedNode() -> CourseBrainNode? {
        guard let selectedNodeID else { return nil }
        return allNodes.first(where: { $0.id == selectedNodeID })
    }

    func connectedNodes(for nodeID: String) -> [CourseBrainNode] {
        let neighborIDs = Set(allEdges.compactMap { edge -> String? in
            if edge.source == nodeID { return edge.target }
            if edge.target == nodeID { return edge.source }
            return nil
        })

        return allNodes
            .filter { neighborIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.type == rhs.type {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return nodePriority(lhs.type) < nodePriority(rhs.type)
            }
    }

    func relatedNodes(for nodeID: String, type: CourseBrainNodeType) -> [CourseBrainNode] {
        connectedNodes(for: nodeID).filter { $0.type == type }
    }

    func manualLinksForSelectedNote() -> [(edge: CourseBrainEdge, target: CourseBrainNode)] {
        guard let note = selectedNode(), note.type == .note else { return [] }

        return allEdges
            .filter { $0.relationship == .manualLink && $0.source == note.id }
            .compactMap { edge in
                guard let target = allNodes.first(where: { $0.id == edge.target }) else { return nil }
                return (edge, target)
            }
    }

    func createManualLink(from sourceNodeID: String, to targetNodeID: String, relationship: CourseBrainRelationship) {
        guard let source = allNodes.first(where: { $0.id == sourceNodeID }) else { return }

        let temporaryRowID = UUID()
        let optimistic = CourseBrainManualLink(
            rowId: temporaryRowID,
            sourceNodeId: sourceNodeID,
            targetNodeId: targetNodeID,
            relationship: relationship,
            courseId: source.courseId,
            createdAt: Date()
        )

        manualLinks.append(optimistic)

        Task {
            await rebuildFromCurrentData(skipRemoteFetch: true)

            do {
                let persisted = try await repository.createManualLink(
                    sourceNodeId: sourceNodeID,
                    targetNodeId: targetNodeID,
                    relationship: relationship,
                    courseId: source.courseId
                )

                manualLinks.removeAll(where: { $0.rowId == temporaryRowID })
                manualLinks.append(persisted)
                await rebuildFromCurrentData(skipRemoteFetch: true)
            } catch {
                manualLinks.removeAll(where: { $0.rowId == temporaryRowID })
                await rebuildFromCurrentData(skipRemoteFetch: true)
                showBanner("Could not save manual link: \(error.localizedDescription)")
            }
        }
    }

    func deleteManualLink(_ edge: CourseBrainEdge) {
        guard let rowId = edge.manualLinkRowId else { return }

        let snapshot = manualLinks
        manualLinks.removeAll(where: { $0.rowId == rowId })

        Task {
            await rebuildFromCurrentData(skipRemoteFetch: true)
            do {
                try await repository.deleteManualLink(rowId: rowId)
            } catch {
                manualLinks = snapshot
                await rebuildFromCurrentData(skipRemoteFetch: true)
                showBanner("Could not remove link: \(error.localizedDescription)")
            }
        }
    }

    func toggleTimelineBucket(_ bucketID: String) {
        if collapsedTimelineBuckets.contains(bucketID) {
            collapsedTimelineBuckets.remove(bucketID)
        } else {
            collapsedTimelineBuckets.insert(bucketID)
        }

        Task {
            do {
                try await repository.saveTimelineMeta(collapsedBuckets: Array(collapsedTimelineBuckets).sorted())
            } catch {
                showBanner("Could not save timeline state")
            }
        }
    }

    private func fetchAndBuild() async {
        isLoading = true
        do {
            let snapshot = try await repository.fetchSnapshot()
            sourceRecords = snapshot.sourceRecords
            manualLinks = snapshot.manualLinks
            syncedNoteNodes = snapshot.syncedNoteNodes
            collapsedTimelineBuckets = snapshot.collapsedTimelineBuckets

            await rebuildFromCurrentData(skipRemoteFetch: true)
            isLoading = false
        } catch {
            isLoading = false
            showBanner("Course Brain load failed: \(error.localizedDescription)")
        }
    }

    private func rebuildFromCurrentData(skipRemoteFetch: Bool = false) async {
        if !skipRemoteFetch {
            do {
                let snapshot = try await repository.fetchSnapshot()
                sourceRecords = snapshot.sourceRecords
                manualLinks = snapshot.manualLinks
                syncedNoteNodes = snapshot.syncedNoteNodes
                collapsedTimelineBuckets = snapshot.collapsedTimelineBuckets
            } catch {
                showBanner("Course Brain refresh failed: \(error.localizedDescription)")
            }
        }

        let localNoteNodes = makeLocalNoteNodes(from: localDocuments)
        let payload = CourseBrainBuildPayload(
            records: sourceRecords,
            localNotes: localNoteNodes,
            syncedNoteNodes: syncedNoteNodes,
            manualLinks: manualLinks,
            courseFilter: courseFilter
        )

        let buildResult = await Task.detached(priority: .userInitiated) {
            await CourseBrainGraphBuilder.shared.build(payload: payload)
        }.value

        allNodes = buildResult.allNodes
        allEdges = buildResult.allEdges
        courseSummaries = buildResult.courseSummaries
        timelineBuckets = buildResult.timelineBuckets
        baseFingerprint = buildResult.graph.fingerprint

        if let cached = await layoutCache.snapshot(for: buildResult.graph.fingerprint) {
            allPositions = cached
        } else {
            let layoutSnapshot = await Task.detached(priority: .userInitiated) {
                await CourseBrainGraphBuilder.shared.buildLayout(nodes: buildResult.allNodes, fingerprint: buildResult.graph.fingerprint)
            }.value
            allPositions = layoutSnapshot.positions
            await layoutCache.save(snapshot: layoutSnapshot)
        }

        Task {
            do {
                try await repository.saveConceptCache(
                    fingerprint: buildResult.graph.fingerprint,
                    concepts: buildResult.conceptCache
                )
            } catch {
                // Best effort cache write.
            }
        }

        applyFocusAndCapping(reapplySearch: true)
    }

    private func applyFocusAndCapping(reapplySearch: Bool) {
        var nodesToRender = allNodes
        var edgesToRender = allEdges

        if focusSelectionOnly, let selectedNodeID {
            let neighborIDs = Set(allEdges.compactMap { edge -> String? in
                if edge.source == selectedNodeID { return edge.target }
                if edge.target == selectedNodeID { return edge.source }
                return nil
            })

            let allowed = neighborIDs.union([selectedNodeID])
            nodesToRender = allNodes.filter { allowed.contains($0.id) }
            edgesToRender = allEdges.filter { allowed.contains($0.source) && allowed.contains($0.target) }
        }

        let fullNodeCount = nodesToRender.count
        let fullEdgeCount = edgesToRender.count

        if nodesToRender.count > 180 {
            var cappedIDs = cappedNodeIDs(nodes: nodesToRender, edges: edgesToRender, limit: 180)
            if let selectedNodeID {
                cappedIDs.insert(selectedNodeID)
            }
            cappedIDs.formUnion(highlightedNodeIDs)
            nodesToRender = nodesToRender.filter { cappedIDs.contains($0.id) }
            edgesToRender = edgesToRender.filter { cappedIDs.contains($0.source) && cappedIDs.contains($0.target) }
        }

        if edgesToRender.count > 300 {
            edgesToRender = Array(edgesToRender.prefix(300))
        }

        nodePositions = allPositions.filter { key, _ in
            nodesToRender.contains(where: { $0.id == key })
        }

        graph = CourseBrainGraph(
            nodes: nodesToRender,
            edges: edgesToRender,
            generatedAt: Date(),
            fullNodeCount: fullNodeCount,
            fullEdgeCount: fullEdgeCount,
            fingerprint: baseFingerprint
        )

        if graph?.isCapped == true {
            showBanner("Showing top \(nodesToRender.count) nodes. Search or filter for a narrower view.")
        }

        if reapplySearch {
            applySearch(searchText)
        }
    }

    private func applySearch(_ rawQuery: String) {
        let query = normalizeSearch(rawQuery)
        guard !query.isEmpty else {
            highlightedNodeIDs = []
            applyFocusAndCapping(reapplySearch: false)
            return
        }

        let matches = allNodes.filter { node in
            normalizeSearch(node.searchableText).contains(query)
        }

        highlightedNodeIDs = Set(matches.map(\.id))
        if let first = matches.first {
            selectedNodeID = first.id
        }

        applyFocusAndCapping(reapplySearch: false)
    }

    private func makeLocalNoteNodes(from documents: [LocalDocument]) -> [CourseBrainNode] {
        let keywords = ["notebook", "quicknote", "quick note", "text doc", "whiteboard", "notes"]

        return documents.compactMap { document in
            let titleLower = document.title.lowercased()
            let looksLikeNote = document.status == .local || keywords.contains(where: { titleLower.contains($0) })
            guard looksLikeNote else { return nil }

            let metadata = CourseBrainNodeMetadata(
                courseName: nil,
                moduleName: nil,
                dueAt: nil,
                unlockAt: nil,
                lockAt: nil,
                scannedAt: document.updatedAt,
                folderPath: nil,
                platform: "lectra_local",
                sourceItemType: "local_note",
                sourceSyncedItemId: nil,
                sourceURLString: document.localPDFURL?.absoluteString,
                instructions: nil,
                description: nil,
                body: nil,
                content: nil,
                text: nil
            )

            return CourseBrainNode(
                id: "note:local:\(document.id.uuidString)",
                type: .note,
                title: document.title,
                courseId: document.courseId,
                metadata: metadata,
                resourceURL: document.localPDFURL
            )
        }
    }

    private func sectionForNode(id: String) -> CourseBrainLeftSection {
        guard let node = allNodes.first(where: { $0.id == id }) else { return .concepts }
        switch node.type {
        case .concept: return .concepts
        case .assignment: return .assignments
        case .lecture: return .lectures
        case .file: return .files
        case .note: return .concepts
        }
    }

    private func nodePriority(_ type: CourseBrainNodeType) -> Int {
        switch type {
        case .assignment: return 0
        case .lecture: return 1
        case .note: return 2
        case .file: return 3
        case .concept: return 4
        }
    }

    private func cappedNodeIDs(nodes: [CourseBrainNode], edges: [CourseBrainEdge], limit: Int) -> Set<String> {
        var degree: [String: Int] = [:]
        for edge in edges {
            degree[edge.source, default: 0] += 1
            degree[edge.target, default: 0] += 1
        }

        let sorted = nodes.sorted { lhs, rhs in
            let lhsDegree = degree[lhs.id, default: 0]
            let rhsDegree = degree[rhs.id, default: 0]
            if lhsDegree == rhsDegree {
                if lhs.type == rhs.type {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return nodePriority(lhs.type) < nodePriority(rhs.type)
            }
            return lhsDegree > rhsDegree
        }

        return Set(sorted.prefix(limit).map(\ .id))
    }

    private func normalizeSearch(_ raw: String) -> String {
        raw
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func showBanner(_ message: String) {
        bannerTask?.cancel()
        bannerMessage = message

        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.bannerMessage = nil
        }
    }
}

actor CourseBrainLayoutCache {
    static let shared = CourseBrainLayoutCache()

    private var snapshots: [String: [String: CGPoint]] = [:]

    func snapshot(for fingerprint: String) -> [String: CGPoint]? {
        snapshots[fingerprint]
    }

    func save(snapshot: CourseBrainLayoutSnapshot) {
        snapshots[snapshot.fingerprint] = snapshot.positions
    }
}
