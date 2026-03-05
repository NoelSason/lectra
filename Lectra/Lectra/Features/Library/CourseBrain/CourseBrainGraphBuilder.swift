import Foundation

struct CourseBrainGraphBuildResult {
    let graph: CourseBrainGraph
    let allNodes: [CourseBrainNode]
    let allEdges: [CourseBrainEdge]
    let courseSummaries: [CourseBrainCourseSummary]
    let timelineBuckets: [CourseBrainTimelineBucket]
    let conceptCache: [CourseBrainConceptCacheConcept]
}

struct CourseBrainLayoutSnapshot {
    let fingerprint: String
    let positions: [String: CGPoint]
}

final class CourseBrainGraphBuilder {
    static let shared = CourseBrainGraphBuilder()

    private let assignmentTypes: Set<String> = ["assignment", "quiz"]
    private let fileTypes: Set<String> = ["file", "pdf", "document", "slides", "video", "page", "externalurl", "externaltool", "discussion"]

    private let lectureRegex = try? NSRegularExpression(pattern: "\\b(lecture|lec|week|session|class)\\b", options: [.caseInsensitive])
    private let numberRegex = try? NSRegularExpression(pattern: "(?:lecture|lec|week|session|class)?\\s*(\\d{1,3})", options: [.caseInsensitive])

    private let stopwords: Set<String> = [
        "the", "and", "for", "from", "with", "your", "this", "that", "into", "of", "to", "in", "on", "at", "by", "as", "is", "it", "be", "are", "or", "an", "a", "lab", "homework", "hw", "module", "assignment", "quiz", "lecture", "week", "class", "session", "notes", "note", "practice", "review"
    ]

    func build(payload: CourseBrainBuildPayload, maxVisibleNodes: Int = 180, maxVisibleEdges: Int = 300) -> CourseBrainGraphBuildResult {
        let scopedRecords = payload.records.filter { record in
            guard let courseFilter = payload.courseFilter else { return true }
            return record.courseId == courseFilter
        }

        let courseSummaries = buildCourseSummaries(from: payload.records)

        var nodeMap: [String: CourseBrainNode] = [:]
        var sourceNodeIDs: [String] = []

        for record in scopedRecords {
            guard let node = mapRecordToNode(record) else { continue }
            if nodeMap[node.id] == nil {
                sourceNodeIDs.append(node.id)
                nodeMap[node.id] = node
            } else {
                nodeMap[node.id] = mergeNodes(existing: nodeMap[node.id]!, incoming: node)
            }
        }

        for note in payload.localNotes where payload.courseFilter == nil || note.courseId == payload.courseFilter {
            nodeMap[note.id] = note
            sourceNodeIDs.append(note.id)
        }

        for note in payload.syncedNoteNodes where payload.courseFilter == nil || note.courseId == payload.courseFilter {
            nodeMap[note.id] = note
            sourceNodeIDs.append(note.id)
        }

        let sourceNodes = sourceNodeIDs.compactMap { nodeMap[$0] }
        let conceptCandidates = extractConcepts(from: sourceNodes)

        for candidate in conceptCandidates {
            let node = CourseBrainNode(
                id: candidate.id,
                type: .concept,
                title: candidate.title,
                courseId: payload.courseFilter,
                metadata: CourseBrainNodeMetadata(
                    courseName: nil,
                    moduleName: nil,
                    dueAt: nil,
                    unlockAt: nil,
                    lockAt: nil,
                    scannedAt: nil,
                    folderPath: nil,
                    platform: nil,
                    sourceItemType: "derived",
                    sourceSyncedItemId: nil,
                    sourceURLString: nil,
                    instructions: nil,
                    description: nil,
                    body: nil,
                    content: nil,
                    text: nil
                ),
                resourceURL: nil
            )
            nodeMap[node.id] = node
        }

        var edges = inferConceptEdges(nodes: Array(nodeMap.values), concepts: conceptCandidates)
        edges.append(contentsOf: inferAssignmentLectureEdges(nodes: Array(nodeMap.values)))
        edges.append(contentsOf: inferFileLectureEdges(nodes: Array(nodeMap.values)))

        let manualEdges = mapManualLinkEdges(payload.manualLinks, nodeMap: &nodeMap, courseFilter: payload.courseFilter)
        edges.append(contentsOf: manualEdges)

        let dedupedEdges = dedupeEdges(edges)
        let allNodes = sortNodes(Array(nodeMap.values))
        let timelineBuckets = buildTimelineBuckets(from: allNodes)

        let fingerprintSeed = allNodes.map(\ .id).joined(separator: "|") + "#" + dedupedEdges.map(\ .id).joined(separator: "|")
        let fingerprint = "graph-\(courseBrainStableHash(fingerprintSeed))"

        let visibleNodeIDs = cappedNodeIDs(nodes: allNodes, edges: dedupedEdges, limit: maxVisibleNodes)
        let visibleNodes = allNodes.filter { visibleNodeIDs.contains($0.id) }

        var visibleEdges = dedupedEdges.filter { visibleNodeIDs.contains($0.source) && visibleNodeIDs.contains($0.target) }
        if visibleEdges.count > maxVisibleEdges {
            visibleEdges = Array(visibleEdges.prefix(maxVisibleEdges))
        }

        let graph = CourseBrainGraph(
            nodes: visibleNodes,
            edges: visibleEdges,
            generatedAt: Date(),
            fullNodeCount: allNodes.count,
            fullEdgeCount: dedupedEdges.count,
            fingerprint: fingerprint
        )

        return CourseBrainGraphBuildResult(
            graph: graph,
            allNodes: allNodes,
            allEdges: dedupedEdges,
            courseSummaries: courseSummaries,
            timelineBuckets: timelineBuckets,
            conceptCache: conceptCandidates
        )
    }

    func buildLayout(nodes: [CourseBrainNode], fingerprint: String) -> CourseBrainLayoutSnapshot {
        var grouped: [CourseBrainNodeType: [CourseBrainNode]] = [:]
        for node in nodes {
            grouped[node.type, default: []].append(node)
        }

        let typeOrder: [CourseBrainNodeType] = [.assignment, .lecture, .note, .file, .concept]
        let groupCenters: [CourseBrainNodeType: CGPoint] = [
            .assignment: CGPoint(x: 540, y: 220),
            .lecture: CGPoint(x: 260, y: 240),
            .note: CGPoint(x: 240, y: 520),
            .file: CGPoint(x: 520, y: 560),
            .concept: CGPoint(x: 390, y: 390)
        ]

        var positions: [String: CGPoint] = [:]

        for type in typeOrder {
            let nodesForType = sortNodes(grouped[type] ?? [])
            guard !nodesForType.isEmpty else { continue }

            let center = groupCenters[type] ?? CGPoint(x: 390, y: 390)
            let radius = max(58, min(250, CGFloat(nodesForType.count) * 6.6))

            for (index, node) in nodesForType.enumerated() {
                if nodesForType.count == 1 {
                    positions[node.id] = center
                    continue
                }

                let angle = (CGFloat(index) / CGFloat(nodesForType.count)) * (.pi * 2)
                let jitter = CGFloat((index % 5) - 2) * 7
                let point = CGPoint(
                    x: center.x + cos(angle) * (radius + jitter),
                    y: center.y + sin(angle) * (radius - jitter)
                )
                positions[node.id] = point
            }
        }

        return CourseBrainLayoutSnapshot(fingerprint: fingerprint, positions: positions)
    }

    // MARK: - Mapping

    private func mapRecordToNode(_ record: CourseBrainSourceRecord) -> CourseBrainNode? {
        let normalizedType = record.normalizedType

        let nodeType: CourseBrainNodeType
        if assignmentTypes.contains(normalizedType) {
            nodeType = .assignment
        } else if isLectureLike(record: record) {
            nodeType = .lecture
        } else if fileTypes.contains(normalizedType) {
            nodeType = .file
        } else {
            return nil
        }

        let primaryKey = canonicalPrimaryKey(for: record, nodeType: nodeType)
        let nodeId = "\(nodeType.rawValue):\(courseBrainStableHash(primaryKey))"

        let metadata = CourseBrainNodeMetadata(
            courseName: record.courseName,
            moduleName: record.moduleName,
            dueAt: record.dueAt,
            unlockAt: record.unlockAt,
            lockAt: record.lockAt,
            scannedAt: record.scannedAt,
            folderPath: record.folderPath,
            platform: record.platform,
            sourceItemType: record.sourceItemType,
            sourceSyncedItemId: record.sourceSyncedItemId,
            sourceURLString: record.url?.absoluteString,
            instructions: record.instructions,
            description: record.description,
            body: record.body,
            content: record.content,
            text: record.text
        )

        return CourseBrainNode(
            id: nodeId,
            type: nodeType,
            title: normalizeWhitespace(record.title),
            courseId: record.courseId,
            metadata: metadata,
            resourceURL: record.url
        )
    }

    private func canonicalPrimaryKey(for record: CourseBrainSourceRecord, nodeType: CourseBrainNodeType) -> String {
        if let absoluteURL = record.url?.absoluteString.lowercased(), !absoluteURL.isEmpty {
            return "\(nodeType.rawValue)|\(absoluteURL)"
        }

        return [
            nodeType.rawValue,
            String(record.courseId ?? -1),
            normalizeForMatching(record.title),
            normalizeForMatching(record.moduleName ?? ""),
            normalizeForMatching(record.type)
        ].joined(separator: "|")
    }

    private func mergeNodes(existing: CourseBrainNode, incoming: CourseBrainNode) -> CourseBrainNode {
        let mergedMetadata = CourseBrainNodeMetadata(
            courseName: existing.metadata.courseName ?? incoming.metadata.courseName,
            moduleName: existing.metadata.moduleName ?? incoming.metadata.moduleName,
            dueAt: existing.metadata.dueAt ?? incoming.metadata.dueAt,
            unlockAt: existing.metadata.unlockAt ?? incoming.metadata.unlockAt,
            lockAt: existing.metadata.lockAt ?? incoming.metadata.lockAt,
            scannedAt: existing.metadata.scannedAt ?? incoming.metadata.scannedAt,
            folderPath: existing.metadata.folderPath ?? incoming.metadata.folderPath,
            platform: existing.metadata.platform ?? incoming.metadata.platform,
            sourceItemType: existing.metadata.sourceItemType ?? incoming.metadata.sourceItemType,
            sourceSyncedItemId: existing.metadata.sourceSyncedItemId ?? incoming.metadata.sourceSyncedItemId,
            sourceURLString: existing.metadata.sourceURLString ?? incoming.metadata.sourceURLString,
            instructions: existing.metadata.instructions ?? incoming.metadata.instructions,
            description: existing.metadata.description ?? incoming.metadata.description,
            body: existing.metadata.body ?? incoming.metadata.body,
            content: existing.metadata.content ?? incoming.metadata.content,
            text: existing.metadata.text ?? incoming.metadata.text
        )

        return CourseBrainNode(
            id: existing.id,
            type: existing.type,
            title: existing.title.count >= incoming.title.count ? existing.title : incoming.title,
            courseId: existing.courseId ?? incoming.courseId,
            metadata: mergedMetadata,
            resourceURL: existing.resourceURL ?? incoming.resourceURL
        )
    }

    private func isLectureLike(record: CourseBrainSourceRecord) -> Bool {
        let joined = "\(record.title) \(record.moduleName ?? "")"
        let range = NSRange(location: 0, length: joined.utf16.count)
        return lectureRegex?.firstMatch(in: joined, options: [], range: range) != nil
    }

    // MARK: - Concepts

    private func extractConcepts(from nodes: [CourseBrainNode]) -> [CourseBrainConceptCacheConcept] {
        struct CandidateStats {
            var score: Double
            var appearances: Int
            var nodeTypes: Set<CourseBrainNodeType>
        }

        var stats: [String: CandidateStats] = [:]

        for node in nodes where node.type == .lecture || node.type == .assignment || node.type == .note {
            let baseWeight: Double
            switch node.type {
            case .lecture:
                baseWeight = 1.25
            case .assignment:
                baseWeight = 1.15
            case .note:
                baseWeight = 1.0
            default:
                baseWeight = 1.0
            }

            let text = [node.title, node.metadata.bestInstructionText].compactMap { $0 }.joined(separator: " ")
            let phrases = conceptPhrases(from: text)
            for phrase in phrases {
                let slug = "concept:\(slugify(phrase))"
                var entry = stats[slug] ?? CandidateStats(score: 0, appearances: 0, nodeTypes: [])
                entry.score += baseWeight
                entry.appearances += 1
                entry.nodeTypes.insert(node.type)
                stats[slug] = entry
            }
        }

        var concepts: [CourseBrainConceptCacheConcept] = []
        concepts.reserveCapacity(stats.count)

        for (id, info) in stats {
            guard info.appearances >= 2 || info.nodeTypes.count >= 2 else { continue }
            let title = titleFromConceptID(id)
            guard title.count >= 3 && title.count <= 40 else { continue }
            concepts.append(.init(id: id, title: title, score: info.score + Double(info.nodeTypes.count)))
        }

        concepts.sort { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.score > rhs.score
        }

        if concepts.count > 60 {
            concepts = Array(concepts.prefix(60))
        }

        return concepts
    }

    private func conceptPhrases(from text: String) -> Set<String> {
        let separators = CharacterSet(charactersIn: "-:|()[]{}").union(.newlines)
        let segments = text
            .components(separatedBy: separators)
            .map(normalizeForMatching)
            .filter { !$0.isEmpty }

        var results: Set<String> = []

        for segment in segments {
            let tokens = segment
                .split(separator: " ")
                .map(String.init)
                .filter { token in
                    token.count >= 3 && !stopwords.contains(token)
                }

            guard !tokens.isEmpty else { continue }

            for n in 1...3 {
                guard tokens.count >= n else { continue }
                for i in 0...(tokens.count - n) {
                    let phrase = tokens[i..<(i + n)].joined(separator: " ")
                    guard phrase.count >= 3 && phrase.count <= 40 else { continue }
                    results.insert(phrase)
                }
            }
        }

        return results
    }

    private func inferConceptEdges(nodes: [CourseBrainNode], concepts: [CourseBrainConceptCacheConcept]) -> [CourseBrainEdge] {
        let conceptByID = Dictionary(uniqueKeysWithValues: concepts.map { ($0.id, $0) })
        var edges: [CourseBrainEdge] = []

        for node in nodes where node.type == .lecture || node.type == .assignment || node.type == .note {
            let text = normalizeForMatching(node.searchableText)
            guard !text.isEmpty else { continue }

            for concept in concepts {
                let phrase = normalizeForMatching(concept.title)
                guard !phrase.isEmpty, text.contains(phrase) else { continue }

                let relationship: CourseBrainRelationship
                switch node.type {
                case .lecture:
                    relationship = .teaches
                case .assignment:
                    relationship = .tests
                case .note:
                    relationship = .references
                default:
                    relationship = .references
                }

                guard conceptByID[concept.id] != nil else { continue }

                edges.append(
                    CourseBrainEdge(
                        id: "\(relationship.rawValue):\(node.id)->\(concept.id)",
                        source: node.id,
                        target: concept.id,
                        relationship: relationship,
                        directional: true,
                        inferred: true,
                        manualLinkRowId: nil
                    )
                )
            }
        }

        return edges
    }

    private func inferAssignmentLectureEdges(nodes: [CourseBrainNode]) -> [CourseBrainEdge] {
        let assignments = nodes.filter { $0.type == .assignment }
        let lectures = nodes.filter { $0.type == .lecture }
        guard !assignments.isEmpty, !lectures.isEmpty else { return [] }

        var edges: [CourseBrainEdge] = []

        for assignment in assignments {
            let sameCourseLectures = lectures.filter { lecture in
                guard let lectureCourse = lecture.courseId else { return assignment.courseId == nil }
                return lectureCourse == assignment.courseId
            }
            guard !sameCourseLectures.isEmpty else { continue }

            let ranked = sameCourseLectures
                .map { lecture -> (CourseBrainNode, Double) in
                    (lecture, lectureAffinity(assignment: assignment, lecture: lecture))
                }
                .sorted { $0.1 > $1.1 }

            guard let best = ranked.first, best.1 >= 2.0 else { continue }

            edges.append(
                CourseBrainEdge(
                    id: "assignmentToLecture:\(assignment.id)->\(best.0.id)",
                    source: assignment.id,
                    target: best.0.id,
                    relationship: .assignmentToLecture,
                    directional: true,
                    inferred: true,
                    manualLinkRowId: nil
                )
            )
        }

        return edges
    }

    private func inferFileLectureEdges(nodes: [CourseBrainNode]) -> [CourseBrainEdge] {
        let files = nodes.filter { $0.type == .file }
        let lectures = nodes.filter { $0.type == .lecture }
        guard !files.isEmpty, !lectures.isEmpty else { return [] }

        var edges: [CourseBrainEdge] = []

        for file in files {
            let sameCourseLectures = lectures.filter { lecture in
                guard let lectureCourse = lecture.courseId else { return file.courseId == nil }
                return lectureCourse == file.courseId
            }
            guard !sameCourseLectures.isEmpty else { continue }

            let ranked = sameCourseLectures
                .map { lecture -> (CourseBrainNode, Double) in
                    (lecture, lectureAffinity(file: file, lecture: lecture))
                }
                .sorted { $0.1 > $1.1 }

            guard let best = ranked.first, best.1 >= 2.0 else { continue }

            edges.append(
                CourseBrainEdge(
                    id: "belongsToLecture:\(file.id)->\(best.0.id)",
                    source: file.id,
                    target: best.0.id,
                    relationship: .belongsToLecture,
                    directional: true,
                    inferred: true,
                    manualLinkRowId: nil
                )
            )
        }

        return edges
    }

    private func lectureAffinity(assignment: CourseBrainNode, lecture: CourseBrainNode) -> Double {
        var score: Double = 1.0

        let assignmentModule = normalizeForMatching(assignment.metadata.moduleName ?? "")
        let lectureModule = normalizeForMatching(lecture.metadata.moduleName ?? "")

        if !assignmentModule.isEmpty && assignmentModule == lectureModule {
            score += 2.0
        }

        if let assignmentLectureNumber = extractLectureNumber(from: assignment.searchableText),
           let lectureNumber = extractLectureNumber(from: lecture.searchableText),
           assignmentLectureNumber == lectureNumber {
            score += 2.5
        }

        if normalizeForMatching(assignment.title).contains(normalizeForMatching(lecture.title)) ||
            normalizeForMatching(lecture.title).contains(normalizeForMatching(assignment.title)) {
            score += 0.8
        }

        return score
    }

    private func lectureAffinity(file: CourseBrainNode, lecture: CourseBrainNode) -> Double {
        var score: Double = 1.0

        let fileModule = normalizeForMatching(file.metadata.moduleName ?? "")
        let lectureModule = normalizeForMatching(lecture.metadata.moduleName ?? "")

        if !fileModule.isEmpty && fileModule == lectureModule {
            score += 2.2
        }

        if let fileLectureNumber = extractLectureNumber(from: file.searchableText),
           let lectureNumber = extractLectureNumber(from: lecture.searchableText),
           fileLectureNumber == lectureNumber {
            score += 2.2
        }

        if normalizeForMatching(file.title).contains(normalizeForMatching(lecture.title)) ||
            normalizeForMatching(lecture.title).contains(normalizeForMatching(file.title)) {
            score += 0.8
        }

        return score
    }

    private func extractLectureNumber(from text: String) -> Int? {
        let normalized = normalizeWhitespace(text)
        let range = NSRange(location: 0, length: normalized.utf16.count)
        guard let match = numberRegex?.firstMatch(in: normalized, options: [], range: range),
              match.numberOfRanges >= 2,
              let groupRange = Range(match.range(at: 1), in: normalized) else {
            return nil
        }

        return Int(normalized[groupRange])
    }

    private func mapManualLinkEdges(
        _ manualLinks: [CourseBrainManualLink],
        nodeMap: inout [String: CourseBrainNode],
        courseFilter: Int?
    ) -> [CourseBrainEdge] {
        var edges: [CourseBrainEdge] = []

        for manualLink in manualLinks {
            if let courseFilter, let manualCourseId = manualLink.courseId, manualCourseId != courseFilter {
                continue
            }

            if nodeMap[manualLink.targetNodeId] == nil,
               manualLink.targetNodeId.hasPrefix("concept:") {
                let conceptTitle = titleFromConceptID(manualLink.targetNodeId)
                nodeMap[manualLink.targetNodeId] = CourseBrainNode(
                    id: manualLink.targetNodeId,
                    type: .concept,
                    title: conceptTitle,
                    courseId: manualLink.courseId,
                    metadata: CourseBrainNodeMetadata(
                        courseName: nil,
                        moduleName: nil,
                        dueAt: nil,
                        unlockAt: nil,
                        lockAt: nil,
                        scannedAt: nil,
                        folderPath: nil,
                        platform: nil,
                        sourceItemType: "manual",
                        sourceSyncedItemId: manualLink.rowId,
                        sourceURLString: nil,
                        instructions: nil,
                        description: nil,
                        body: nil,
                        content: nil,
                        text: nil
                    ),
                    resourceURL: nil
                )
            }

            guard nodeMap[manualLink.sourceNodeId] != nil,
                  nodeMap[manualLink.targetNodeId] != nil else {
                continue
            }

            edges.append(
                CourseBrainEdge(
                    id: "manual:\(manualLink.rowId.uuidString)",
                    source: manualLink.sourceNodeId,
                    target: manualLink.targetNodeId,
                    relationship: .manualLink,
                    directional: true,
                    inferred: false,
                    manualLinkRowId: manualLink.rowId
                )
            )
        }

        return edges
    }

    // MARK: - Bucketing & Sorting

    private func buildCourseSummaries(from records: [CourseBrainSourceRecord]) -> [CourseBrainCourseSummary] {
        var counters: [Int: (name: String, count: Int)] = [:]

        for record in records {
            guard let courseId = record.courseId else { continue }
            let fallbackName = record.courseName ?? "Course \(courseId)"
            let existing = counters[courseId] ?? (name: fallbackName, count: 0)
            counters[courseId] = (name: existing.name, count: existing.count + 1)
        }

        return counters
            .map { CourseBrainCourseSummary(id: $0.key, name: $0.value.name, count: $0.value.count) }
            .sorted {
                if $0.count == $1.count {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.count > $1.count
            }
    }

    private func buildTimelineBuckets(from nodes: [CourseBrainNode]) -> [CourseBrainTimelineBucket] {
        var buckets: [String: [CourseBrainNode]] = [:]
        var bucketSortDates: [String: Date] = [:]

        for node in nodes where node.type != .concept {
            let date = node.metadata.dueAt ?? node.metadata.unlockAt ?? node.metadata.lockAt ?? node.metadata.scannedAt

            if let date {
                let key = DateFormatter.courseBrainTimelineFormatter.string(from: date)
                buckets[key, default: []].append(node)
                if let existing = bucketSortDates[key] {
                    if date < existing {
                        bucketSortDates[key] = date
                    }
                } else {
                    bucketSortDates[key] = date
                }
            } else {
                buckets["undated", default: []].append(node)
            }
        }

        var result: [CourseBrainTimelineBucket] = []
        result.reserveCapacity(buckets.count)

        for (bucketID, items) in buckets {
            let sortedItems = items.sorted {
                let lhsDate = $0.metadata.dueAt ?? $0.metadata.unlockAt ?? $0.metadata.lockAt ?? $0.metadata.scannedAt
                let rhsDate = $1.metadata.dueAt ?? $1.metadata.unlockAt ?? $1.metadata.lockAt ?? $1.metadata.scannedAt

                if lhsDate == rhsDate {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return (lhsDate ?? .distantFuture) < (rhsDate ?? .distantFuture)
            }

            if bucketID == "undated" {
                result.append(.init(id: bucketID, title: "Undated", sortDate: nil, items: sortedItems))
            } else {
                let formattedTitle = timelineTitle(from: bucketID)
                result.append(.init(id: bucketID, title: formattedTitle, sortDate: bucketSortDates[bucketID], items: sortedItems))
            }
        }

        result.sort {
            switch ($0.sortDate, $1.sortDate) {
            case let (lhs?, rhs?):
                return lhs < rhs
            case (.none, .some):
                return false
            case (.some, .none):
                return true
            case (.none, .none):
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }

        return result
    }

    private func timelineTitle(from bucketID: String) -> String {
        let parts = bucketID.split(separator: "W")
        guard parts.count == 2 else { return bucketID }
        return "Week \(parts[1]) · \(parts[0])"
    }

    private func dedupeEdges(_ edges: [CourseBrainEdge]) -> [CourseBrainEdge] {
        var seen: Set<String> = []
        var result: [CourseBrainEdge] = []
        result.reserveCapacity(edges.count)

        for edge in edges {
            let key = "\(edge.source)|\(edge.target)|\(edge.relationship.rawValue)|\(edge.manualLinkRowId?.uuidString ?? "")"
            guard seen.insert(key).inserted else { continue }
            result.append(edge)
        }

        return result
    }

    private func sortNodes(_ nodes: [CourseBrainNode]) -> [CourseBrainNode] {
        nodes.sorted {
            if $0.type == $1.type {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return nodePriority($0.type) < nodePriority($1.type)
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
        guard nodes.count > limit else {
            return Set(nodes.map(\ .id))
        }

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

    // MARK: - Text Helpers

    private func normalizeWhitespace(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeForMatching(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let cleaned = lowered.replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
        return normalizeWhitespace(cleaned)
    }

    private func slugify(_ raw: String) -> String {
        normalizeForMatching(raw)
            .replacingOccurrences(of: " ", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func titleFromConceptID(_ id: String) -> String {
        let slug = id.replacingOccurrences(of: "concept:", with: "")
        let spaced = slug.replacingOccurrences(of: "-", with: " ")
        return spaced
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

func courseBrainStableHash(_ input: String) -> String {
    // Deterministic FNV-1a 64-bit hash for stable IDs/fingerprints.
    let bytes = Array(input.utf8)
    var hash: UInt64 = 0xcbf29ce484222325
    let prime: UInt64 = 0x100000001b3

    for byte in bytes {
        hash ^= UInt64(byte)
        hash = hash &* prime
    }

    return String(hash, radix: 16)
}
