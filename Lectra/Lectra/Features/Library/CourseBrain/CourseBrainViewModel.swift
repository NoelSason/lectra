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
    @Published private(set) var topicBuckets: [CourseBrainTopicBucket] = []

    @Published var searchText = ""
    @Published var selectedNodeID: String?
    @Published var selectedLeafID: String?
    @Published var highlightedNodeIDs: Set<String> = []
    @Published var highlightedLeafID: String?
    @Published var leftSection: CourseBrainLeftSection = .topics
    @Published var displayMode: CourseBrainDisplayMode = .graph
    @Published var densityMode: CourseBrainGraphDensityMode = .overviewTopicFirst
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

    private var leafByID: [String: CourseBrainLeafSummary] = [:]
    private var topicToLeafIDs: [String: [String]] = [:]
    private var leafToTopicID: [String: String] = [:]

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
        selectedLeafID = nil
        highlightedLeafID = nil

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
        selectedLeafID = nil
        highlightedLeafID = nil
        selectedNodeID = id
        if let id {
            leftSection = sectionForNode(id: id)
        }
        applyFocusAndCapping(reapplySearch: true)
    }

    func selectTopicLeaf(_ leafID: String) {
        guard leafByID[leafID] != nil else { return }
        selectedLeafID = leafID
        highlightedLeafID = leafID

        if let topicID = leafToTopicID[leafID] {
            selectedNodeID = topicID
            leftSection = .topics
        }

        applyFocusAndCapping(reapplySearch: true)
    }

    func selectTimelineItem(_ nodeID: String) {
        displayMode = .graph
        selectedLeafID = nil
        highlightedLeafID = nil
        selectedNodeID = nodeID
        applyFocusAndCapping(reapplySearch: true)
    }

    func nodesForLeftSection(_ section: CourseBrainLeftSection) -> [CourseBrainNode] {
        switch section {
        case .topics:
            let nodeMap = Dictionary(uniqueKeysWithValues: allNodes.map { ($0.id, $0) })
            let orderedTopicNodes = topicBuckets
                .sorted { lhs, rhs in
                    if lhs.memberNodeIDs.count == rhs.memberNodeIDs.count {
                        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                    }
                    return lhs.memberNodeIDs.count > rhs.memberNodeIDs.count
                }
                .compactMap { bucket in
                    nodeMap[bucket.id]
                }
            return Array(orderedTopicNodes.prefix(80))
        case .concepts:
            return limitedSortedNodes(of: .concept, limit: 80)
        case .assignments:
            return limitedSortedNodes(of: .assignment, limit: 120)
        case .lectures:
            return limitedSortedNodes(of: .lecture, limit: 120)
        case .files:
            return limitedSortedNodes(of: .file, limit: 120)
        case .timeline:
            return []
        }
    }

    func topicMemberCount(topicID: String) -> Int {
        topicToLeafIDs[topicID]?.count ?? 0
    }

    func selectedNode() -> CourseBrainNode? {
        guard let selectedNodeID else { return nil }
        return allNodes.first(where: { $0.id == selectedNodeID })
    }

    func selectedLeafSummary() -> CourseBrainLeafSummary? {
        guard let selectedLeafID else { return nil }
        return leafByID[selectedLeafID]
    }

    func node(for id: String) -> CourseBrainNode? {
        allNodes.first(where: { $0.id == id })
    }

    func topicBucket(for topicID: String) -> CourseBrainTopicBucket? {
        topicBuckets.first(where: { $0.id == topicID })
    }

    func topicLeaves(topicID: String, type: CourseBrainNodeType? = nil) -> [CourseBrainLeafSummary] {
        let ids = topicToLeafIDs[topicID] ?? []
        return ids
            .compactMap { leafByID[$0] }
            .filter { summary in
                if let type {
                    return summary.type == type
                }
                return true
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.dueAt ?? lhs.unlockAt ?? lhs.lockAt
                let rhsDate = rhs.dueAt ?? rhs.unlockAt ?? rhs.lockAt
                if lhsDate == rhsDate {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                switch (lhsDate, rhsDate) {
                case let (lhs?, rhs?):
                    return lhs < rhs
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }
    }

    func topicConceptNodes(topicID: String) -> [CourseBrainNode] {
        guard let bucket = topicBucket(for: topicID) else { return [] }
        return bucket.topConceptIDs
            .compactMap { conceptID in
                allNodes.first(where: { $0.id == conceptID })
            }
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
        topicBuckets = buildResult.topicBuckets
        leafByID = buildResult.leafByID
        topicToLeafIDs = buildResult.topicToLeafIDs
        leafToTopicID = buildInverseTopicMap(buildResult.topicToLeafIDs)

        if selectedNodeID == nil {
            selectedNodeID = buildResult.topicBuckets.first?.id ?? buildResult.allNodes.first?.id
        }

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
        var nodesToRender = overviewNodes()
        var edgesToRender = allEdges.filter { edge in
            nodesToRender.contains(where: { $0.id == edge.source }) && nodesToRender.contains(where: { $0.id == edge.target })
        }

        if focusSelectionOnly, let selectedNodeID {
            let neighborIDs = Set(edgesToRender.compactMap { edge -> String? in
                if edge.source == selectedNodeID { return edge.target }
                if edge.target == selectedNodeID { return edge.source }
                return nil
            })

            let allowed = neighborIDs.union([selectedNodeID])
            nodesToRender = nodesToRender.filter { allowed.contains($0.id) }
            edgesToRender = edgesToRender.filter { allowed.contains($0.source) && allowed.contains($0.target) }
        }

        let fullNodeCount = nodesToRender.count
        let fullEdgeCount = edgesToRender.count

        if nodesToRender.count > 90 {
            var cappedIDs = cappedNodeIDs(nodes: nodesToRender, edges: edgesToRender, limit: 90)
            if let selectedNodeID {
                cappedIDs.insert(selectedNodeID)
            }
            cappedIDs.formUnion(highlightedNodeIDs)
            nodesToRender = nodesToRender.filter { cappedIDs.contains($0.id) }
            edgesToRender = edgesToRender.filter { cappedIDs.contains($0.source) && cappedIDs.contains($0.target) }
        }

        if edgesToRender.count > 140 {
            edgesToRender = Array(edgesToRender.prefix(140))
        }

        let renderedNodeIDs = Set(nodesToRender.map(\ .id))
        nodePositions = allPositions.filter { key, _ in
            renderedNodeIDs.contains(key)
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
            showBanner("Showing \(nodesToRender.count) overview nodes. Search or filter for details.")
        }

        if reapplySearch {
            applySearch(searchText)
        }
    }

    private func applySearch(_ rawQuery: String) {
        let query = normalizeSearch(rawQuery)
        guard !query.isEmpty else {
            highlightedNodeIDs = []
            highlightedLeafID = nil
            applyFocusAndCapping(reapplySearch: false)
            return
        }

        let leafMatches = leafByID.values
            .filter { summary in
                normalizeSearch([
                    summary.title,
                    summary.courseName,
                    summary.moduleName,
                    summary.instructionPreview
                ].compactMap { $0 }.joined(separator: " ")).contains(query)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        if let firstLeaf = leafMatches.first {
            selectedLeafID = firstLeaf.id
            highlightedLeafID = firstLeaf.id
            if let topicID = leafToTopicID[firstLeaf.id] {
                selectedNodeID = topicID
                leftSection = .topics
                highlightedNodeIDs = [topicID]
            }
            applyFocusAndCapping(reapplySearch: false)
            return
        }

        let nodeMatches = allNodes.filter { node in
            normalizeSearch(node.searchableText).contains(query)
        }

        let overviewMatches = nodeMatches.filter { isOverviewType($0.type) }
        let matchesToUse = overviewMatches.isEmpty ? nodeMatches : overviewMatches

        selectedLeafID = nil
        highlightedLeafID = nil
        highlightedNodeIDs = Set(matchesToUse.map(\ .id))

        if let first = matchesToUse.first {
            selectedNodeID = first.id
            leftSection = sectionForNode(id: first.id)
        }

        applyFocusAndCapping(reapplySearch: false)
    }

    private func overviewNodes() -> [CourseBrainNode] {
        switch densityMode {
        case .overviewTopicFirst:
            return allNodes.filter { isOverviewType($0.type) }
        case .expandedTopic:
            return allNodes
        }
    }

    private func isOverviewType(_ type: CourseBrainNodeType) -> Bool {
        switch type {
        case .topic, .concept, .note:
            return true
        default:
            return false
        }
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
        guard let node = allNodes.first(where: { $0.id == id }) else { return .topics }
        switch node.type {
        case .topic: return .topics
        case .concept: return .concepts
        case .assignment: return .assignments
        case .lecture: return .lectures
        case .file: return .files
        case .note: return .concepts
        }
    }

    private func nodePriority(_ type: CourseBrainNodeType) -> Int {
        switch type {
        case .topic: return 0
        case .concept: return 1
        case .note: return 2
        case .assignment: return 3
        case .lecture: return 4
        case .file: return 5
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

    private func limitedSortedNodes(of type: CourseBrainNodeType, limit: Int) -> [CourseBrainNode] {
        let filtered = allNodes.filter { $0.type == type }
        let sorted = filtered.sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return Array(sorted.prefix(limit))
    }

    private func normalizeSearch(_ raw: String) -> String {
        raw
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildInverseTopicMap(_ topicToLeaf: [String: [String]]) -> [String: String] {
        var result: [String: String] = [:]
        for (topicID, leafIDs) in topicToLeaf {
            for leafID in leafIDs {
                result[leafID] = topicID
            }
        }
        return result
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
