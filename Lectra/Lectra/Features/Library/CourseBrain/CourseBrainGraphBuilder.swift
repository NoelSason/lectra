import Foundation
import CoreGraphics

struct CourseBrainGraphBuildResult {
    let graph: CourseBrainGraph
    let allNodes: [CourseBrainNode]
    let allEdges: [CourseBrainEdge]
    let courseSummaries: [CourseBrainCourseSummary]
    let timelineBuckets: [CourseBrainTimelineBucket]
    let conceptCache: [CourseBrainConceptCacheConcept]
    let topicBuckets: [CourseBrainTopicBucket]
    let leafByID: [String: CourseBrainLeafSummary]
    let topicToLeafIDs: [String: [String]]
}

struct CourseBrainLayoutSnapshot {
    let fingerprint: String
    let positions: [String: CGPoint]
}

private struct CourseBrainTopicConceptScore {
    var score: Double
    var typeCounts: [CourseBrainNodeType: Int]
}

private struct CourseBrainTopicAggregation {
    let topicNodes: [CourseBrainNode]
    let topicBuckets: [CourseBrainTopicBucket]
    let topicToLeafIDs: [String: [String]]
    let conceptScoresByTopic: [String: [String: CourseBrainTopicConceptScore]]
}

final class CourseBrainGraphBuilder {
    static let shared = CourseBrainGraphBuilder()

    private let assignmentTypes: Set<String> = ["assignment", "quiz"]
    private let fileTypes: Set<String> = ["file", "pdf", "document", "slides", "video", "page", "externalurl", "externaltool", "discussion"]

    // Compatibility shims for stale editor state in older buffers.
    private let topicRegex = try? NSRegularExpression(pattern: "\\b(week|lecture|lec|unit|chapter|session|class)\\s*([0-9]{1,3})\\b", options: [.caseInsensitive])
    private let genericTopicWords: Set<String> = ["module", "course", "materials", "content", "general", "misc", "resources"]

    private let lectureRegex = try? NSRegularExpression(pattern: "\\b(lecture|lec|week|session|class)\\b", options: [.caseInsensitive])
    private let leadingOrdinalRegex = try? NSRegularExpression(pattern: "^\\d+\\s*[\\.)-]\\s*", options: [])

    private let stopwords: Set<String> = [
        "the", "and", "for", "from", "with", "your", "this", "that", "into", "of", "to", "in", "on", "at", "by", "as", "is", "it", "be", "are", "or", "an", "a", "lab", "homework", "hw", "module", "assignment", "quiz", "lecture", "week", "class", "session", "notes", "note", "practice", "review", "page", "pages", "file", "files", "document", "documents", "course", "content", "resource", "resources", "admin", "links"
    ]

    private let structuralNoiseLabels: Set<String> = [
        "general", "unfiled", "course files", "course file", "files", "file", "content", "module", "modules", "pages", "assignments", "quizzes", "discussions", "course image", "course_image", "photos", "images", "media gallery"
    ]

    func build(payload: CourseBrainBuildPayload, maxVisibleNodes: Int = 90, maxVisibleEdges: Int = 140) -> CourseBrainGraphBuildResult {
        let scopedRecords = payload.records.filter { record in
            guard let courseFilter = payload.courseFilter else { return true }
            return record.courseId == courseFilter
        }

        let courseSummaries = buildCourseSummaries(from: payload.records)

        var allNodeMap: [String: CourseBrainNode] = [:]

        for record in scopedRecords {
            guard let node = mapRecordToNode(record) else { continue }
            if let existing = allNodeMap[node.id] {
                allNodeMap[node.id] = mergeNodes(existing: existing, incoming: node)
            } else {
                allNodeMap[node.id] = node
            }
        }

        let leafNodes = allNodeMap.values.filter {
            $0.type == .assignment || $0.type == .lecture || $0.type == .file
        }

        for note in payload.localNotes where payload.courseFilter == nil || note.courseId == payload.courseFilter {
            allNodeMap[note.id] = note
        }

        for note in payload.syncedNoteNodes where payload.courseFilter == nil || note.courseId == payload.courseFilter {
            allNodeMap[note.id] = note
        }

        let noteNodes = allNodeMap.values.filter { $0.type == .note }

        let conceptCandidates = extractConcepts(from: leafNodes + noteNodes)
        let conceptNodes = conceptCandidates.map { concept -> CourseBrainNode in
            CourseBrainNode(
                id: concept.id,
                type: .concept,
                title: concept.title,
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
        }

        for concept in conceptNodes {
            allNodeMap[concept.id] = concept
        }

        let leafByID = buildLeafSummaries(from: leafNodes)
        let topicAggregation = buildTopicAggregation(leaves: leafNodes, concepts: conceptCandidates)

        for topicNode in topicAggregation.topicNodes {
            allNodeMap[topicNode.id] = topicNode
        }

        var edges = buildTopicConceptEdges(
            topicScores: topicAggregation.conceptScoresByTopic,
            topicToConceptIDs: Dictionary(uniqueKeysWithValues: topicAggregation.topicBuckets.map { ($0.id, $0.topConceptIDs) })
        )

        edges.append(contentsOf: inferNoteConceptEdges(notes: noteNodes, concepts: conceptCandidates))

        let manualEdges = mapManualLinkEdges(payload.manualLinks, nodeMap: &allNodeMap, courseFilter: payload.courseFilter)
        edges.append(contentsOf: manualEdges)

        let dedupedEdges = dedupeEdges(edges)
        let allNodes = sortNodes(Array(allNodeMap.values))
        let timelineBuckets = buildTimelineBuckets(from: allNodes)

        let overviewNodeIDs = Set(allNodes.compactMap { node -> String? in
            switch node.type {
            case .topic, .concept, .note:
                return node.id
            default:
                return nil
            }
        })

        let overviewNodes = allNodes.filter { overviewNodeIDs.contains($0.id) }
        let overviewEdges = dedupedEdges.filter { overviewNodeIDs.contains($0.source) && overviewNodeIDs.contains($0.target) }

        let fingerprintSeed = allNodes.map(\ .id).joined(separator: "|") + "#" + dedupedEdges.map(\ .id).joined(separator: "|")
        let fingerprint = "graph-\(courseBrainStableHash(fingerprintSeed))"

        let visibleNodeIDs = cappedNodeIDs(nodes: overviewNodes, edges: overviewEdges, limit: maxVisibleNodes)
        let visibleNodes = overviewNodes.filter { visibleNodeIDs.contains($0.id) }

        var visibleEdges = overviewEdges.filter { visibleNodeIDs.contains($0.source) && visibleNodeIDs.contains($0.target) }
        if visibleEdges.count > maxVisibleEdges {
            visibleEdges = Array(visibleEdges.prefix(maxVisibleEdges))
        }

        let graph = CourseBrainGraph(
            nodes: visibleNodes,
            edges: visibleEdges,
            generatedAt: Date(),
            fullNodeCount: overviewNodes.count,
            fullEdgeCount: overviewEdges.count,
            fingerprint: fingerprint
        )

        return CourseBrainGraphBuildResult(
            graph: graph,
            allNodes: allNodes,
            allEdges: dedupedEdges,
            courseSummaries: courseSummaries,
            timelineBuckets: timelineBuckets,
            conceptCache: conceptCandidates,
            topicBuckets: topicAggregation.topicBuckets,
            leafByID: leafByID,
            topicToLeafIDs: topicAggregation.topicToLeafIDs
        )
    }

    func buildLayout(nodes: [CourseBrainNode], fingerprint: String) -> CourseBrainLayoutSnapshot {
        var grouped: [CourseBrainNodeType: [CourseBrainNode]] = [:]
        for node in nodes {
            grouped[node.type, default: []].append(node)
        }

        let typeOrder: [CourseBrainNodeType] = [.topic, .concept, .note, .assignment, .lecture, .file]
        let groupCenters: [CourseBrainNodeType: CGPoint] = [
            .topic: CGPoint(x: 0.34, y: 0.50),
            .concept: CGPoint(x: 0.66, y: 0.50),
            .note: CGPoint(x: 0.50, y: 0.18),
            .assignment: CGPoint(x: 0.20, y: 0.78),
            .lecture: CGPoint(x: 0.50, y: 0.84),
            .file: CGPoint(x: 0.80, y: 0.78)
        ]

        var positions: [String: CGPoint] = [:]

        for type in typeOrder {
            let nodesForType = sortNodes(grouped[type] ?? [])
            guard !nodesForType.isEmpty else { continue }

            let center = groupCenters[type] ?? CGPoint(x: 0.5, y: 0.5)
            let radius = max(0.04, min(0.22, CGFloat(nodesForType.count) * 0.012))

            for (index, node) in nodesForType.enumerated() {
                if nodesForType.count == 1 {
                    positions[node.id] = center
                    continue
                }

                let angle = (CGFloat(index) / CGFloat(nodesForType.count)) * (.pi * 2)
                let jitter = CGFloat((index % 4) - 2) * 0.008
                let point = CGPoint(
                    x: center.x + cos(angle) * (radius + jitter),
                    y: center.y + sin(angle) * (radius - jitter)
                )
                positions[node.id] = CGPoint(
                    x: min(max(point.x, 0.06), 0.94),
                    y: min(max(point.y, 0.08), 0.92)
                )
            }
        }

        return CourseBrainLayoutSnapshot(fingerprint: fingerprint, positions: positions)
    }

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

    private func buildLeafSummaries(from leaves: [CourseBrainNode]) -> [String: CourseBrainLeafSummary] {
        var result: [String: CourseBrainLeafSummary] = [:]
        for leaf in leaves {
            result[leaf.id] = CourseBrainLeafSummary(
                id: leaf.id,
                type: leaf.type,
                title: leaf.title,
                courseId: leaf.courseId,
                courseName: leaf.metadata.courseName,
                moduleName: leaf.metadata.moduleName,
                dueAt: leaf.metadata.dueAt,
                unlockAt: leaf.metadata.unlockAt,
                lockAt: leaf.metadata.lockAt,
                url: leaf.resourceURL,
                instructionPreview: leaf.metadata.bestInstructionText
            )
        }
        return result
    }

    private func buildTopicAggregation(leaves: [CourseBrainNode], concepts: [CourseBrainConceptCacheConcept]) -> CourseBrainTopicAggregation {
        struct MutableBucket {
            var title: String
            var courseId: Int?
            var courseName: String?
            var memberNodeIDs: [String]
            var countsByType: [CourseBrainNodeType: Int]
            var conceptScores: [String: CourseBrainTopicConceptScore]
        }

        var moduleFrequencyByCourse: [Int: [String: Int]] = [:]
        var folderFrequencyByCourse: [Int: [String: Int]] = [:]
        for leaf in leaves {
            let courseScope = leaf.courseId ?? -1
            if let module = normalizedStructuralLabel(leaf.metadata.moduleName),
               !structuralNoiseLabels.contains(normalizeForMatching(module)) {
                incrementFrequency(&moduleFrequencyByCourse, courseScope: courseScope, label: module)
            }
            if let folder = folderRoot(from: leaf.metadata.folderPath),
               let normalizedFolder = normalizedStructuralLabel(folder),
               !structuralNoiseLabels.contains(normalizeForMatching(normalizedFolder)) {
                incrementFrequency(&folderFrequencyByCourse, courseScope: courseScope, label: normalizedFolder)
            }
        }

        var buckets: [String: MutableBucket] = [:]

        for leaf in leaves {
            let rawTitle = deriveTopicTitle(
                for: leaf,
                moduleFrequencyByCourse: moduleFrequencyByCourse,
                folderFrequencyByCourse: folderFrequencyByCourse
            )
            let normalizedTitle = normalizeTopicTitle(rawTitle)
            let courseScope = leaf.courseId ?? -1
            let bucketKey = "\(courseScope)|\(slugify(normalizedTitle))"

            var bucket = buckets[bucketKey] ?? MutableBucket(
                title: normalizedTitle,
                courseId: leaf.courseId,
                courseName: leaf.metadata.courseName,
                memberNodeIDs: [],
                countsByType: [:],
                conceptScores: [:]
            )

            bucket.memberNodeIDs.append(leaf.id)
            bucket.countsByType[leaf.type, default: 0] += 1

            let evidenceText = topicEvidenceText(for: leaf)
            for concept in concepts {
                let phrase = normalizeForMatching(concept.title)
                guard !phrase.isEmpty, evidenceText.contains(phrase) else { continue }
                var conceptScore = bucket.conceptScores[concept.id] ?? CourseBrainTopicConceptScore(score: 0, typeCounts: [:])

                let weight: Double
                switch leaf.type {
                case .assignment:
                    weight = 1.3
                case .lecture:
                    weight = 1.2
                case .file:
                    weight = 1.0
                default:
                    weight = 1.0
                }

                conceptScore.score += weight
                conceptScore.typeCounts[leaf.type, default: 0] += 1
                bucket.conceptScores[concept.id] = conceptScore
            }

            buckets[bucketKey] = bucket
        }

        var groupedKeysByCourse: [Int: [String]] = [:]
        for (key, bucket) in buckets {
            groupedKeysByCourse[bucket.courseId ?? -1, default: []].append(key)
        }

        for (courseScope, keys) in groupedKeysByCourse {
            let sparseKeys = keys.filter { key in
                guard let bucket = buckets[key] else { return false }
                return bucket.memberNodeIDs.count < 3 && bucket.title.lowercased() != "general"
            }
            guard !sparseKeys.isEmpty else { continue }

            let generalKey = "\(courseScope)|general"
            if buckets[generalKey] == nil {
                buckets[generalKey] = MutableBucket(
                    title: "General",
                    courseId: courseScope == -1 ? nil : courseScope,
                    courseName: sparseKeys.compactMap { buckets[$0]?.courseName }.first,
                    memberNodeIDs: [],
                    countsByType: [:],
                    conceptScores: [:]
                )
            }

            for sparseKey in sparseKeys {
                guard let sparse = buckets[sparseKey], var general = buckets[generalKey] else { continue }
                general.memberNodeIDs.append(contentsOf: sparse.memberNodeIDs)
                for (type, count) in sparse.countsByType {
                    general.countsByType[type, default: 0] += count
                }
                for (conceptID, score) in sparse.conceptScores {
                    var existing = general.conceptScores[conceptID] ?? CourseBrainTopicConceptScore(score: 0, typeCounts: [:])
                    existing.score += score.score
                    for (type, count) in score.typeCounts {
                        existing.typeCounts[type, default: 0] += count
                    }
                    general.conceptScores[conceptID] = existing
                }
                buckets[generalKey] = general
                buckets.removeValue(forKey: sparseKey)
            }
        }

        var topicNodes: [CourseBrainNode] = []
        var topicBuckets: [CourseBrainTopicBucket] = []
        var topicToLeafIDs: [String: [String]] = [:]
        var conceptScoresByTopic: [String: [String: CourseBrainTopicConceptScore]] = [:]

        for (_, bucket) in buckets {
            let topicSeed = "\(bucket.courseId ?? -1)|\(bucket.title.lowercased())"
            let topicID = "topic:\(courseBrainStableHash(topicSeed))"

            let sortedConceptIDs = bucket.conceptScores
                .sorted { lhs, rhs in
                    if lhs.value.score == rhs.value.score {
                        return lhs.key < rhs.key
                    }
                    return lhs.value.score > rhs.value.score
                }
                .map { $0.key }

            let topConceptIDs = Array(sortedConceptIDs.prefix(8))
            let counts = bucket.countsByType

            let countsText = [
                "Assignments: \(counts[.assignment, default: 0])",
                "Lectures: \(counts[.lecture, default: 0])",
                "Files: \(counts[.file, default: 0])"
            ].joined(separator: " • ")

            let topicNode = CourseBrainNode(
                id: topicID,
                type: .topic,
                title: bucket.title,
                courseId: bucket.courseId,
                metadata: CourseBrainNodeMetadata(
                    courseName: bucket.courseName,
                    moduleName: bucket.title,
                    dueAt: nil,
                    unlockAt: nil,
                    lockAt: nil,
                    scannedAt: nil,
                    folderPath: nil,
                    platform: nil,
                    sourceItemType: "derived_topic",
                    sourceSyncedItemId: nil,
                    sourceURLString: nil,
                    instructions: nil,
                    description: countsText,
                    body: nil,
                    content: nil,
                    text: nil
                ),
                resourceURL: nil
            )

            topicNodes.append(topicNode)
            topicBuckets.append(
                CourseBrainTopicBucket(
                    id: topicID,
                    title: bucket.title,
                    courseId: bucket.courseId,
                    memberNodeIDs: bucket.memberNodeIDs.sorted(),
                    countsByType: bucket.countsByType,
                    topConceptIDs: topConceptIDs
                )
            )
            topicToLeafIDs[topicID] = bucket.memberNodeIDs.sorted()
            conceptScoresByTopic[topicID] = bucket.conceptScores
        }

        topicNodes = sortNodes(topicNodes)
        topicBuckets.sort {
            if $0.title == $1.title {
                return ($0.courseId ?? -1) < ($1.courseId ?? -1)
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        return CourseBrainTopicAggregation(
            topicNodes: topicNodes,
            topicBuckets: topicBuckets,
            topicToLeafIDs: topicToLeafIDs,
            conceptScoresByTopic: conceptScoresByTopic
        )
    }

    private func deriveTopicTitle(
        for leaf: CourseBrainNode,
        moduleFrequencyByCourse: [Int: [String: Int]],
        folderFrequencyByCourse: [Int: [String: Int]]
    ) -> String {
        let courseScope = leaf.courseId ?? -1

        let normalizedModule = normalizedStructuralLabel(leaf.metadata.moduleName)
        let normalizedFolder = normalizedStructuralLabel(folderRoot(from: leaf.metadata.folderPath))
        let structuralSignal = normalizeForMatching([
            normalizedModule,
            normalizedFolder,
            urlStructureToken(for: leaf.resourceURL),
            fallbackTopicTitle(for: leaf.type)
        ].compactMap { $0 }.joined(separator: " "))

        if let structuralCategory = structuralCategoryTitle(signal: structuralSignal, nodeType: leaf.type) {
            return structuralCategory
        }

        if let normalizedModule {
            let moduleKey = normalizeForMatching(normalizedModule)
            if !structuralNoiseLabels.contains(moduleKey) {
                let moduleFrequency = frequency(of: normalizedModule, in: moduleFrequencyByCourse, courseScope: courseScope)
                if moduleFrequency >= 8 {
                    return normalizedModule
                }
            }
        }

        if let normalizedFolder {
            let folderKey = normalizeForMatching(normalizedFolder)
            if !structuralNoiseLabels.contains(folderKey) {
                let folderFrequency = frequency(of: normalizedFolder, in: folderFrequencyByCourse, courseScope: courseScope)
                if folderFrequency >= 8 {
                    return normalizedFolder
                }
            }
        }

        if let normalizedModule, !structuralNoiseLabels.contains(normalizeForMatching(normalizedModule)), normalizedModule.count <= 34 {
            return normalizedModule
        }

        if let normalizedFolder, !structuralNoiseLabels.contains(normalizeForMatching(normalizedFolder)), normalizedFolder.count <= 34 {
            return normalizedFolder
        }

        return fallbackTopicTitle(for: leaf.type)
    }

    private func normalizeTopicTitle(_ raw: String) -> String {
        let normalized = normalizeWhitespace(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "General" : normalized
    }

    private func normalizedStructuralLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var normalized = normalizeWhitespace(raw)
        if let leadingOrdinalRegex {
            let range = NSRange(location: 0, length: normalized.utf16.count)
            normalized = leadingOrdinalRegex.stringByReplacingMatches(in: normalized, options: [], range: range, withTemplate: "")
        }
        normalized = normalizeWhitespace(normalized)
        guard !normalized.isEmpty else { return nil }
        return normalized
    }

    private func folderRoot(from raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = normalizeWhitespace(raw)
        guard !normalized.isEmpty else { return nil }
        if let first = normalized.split(separator: ">", maxSplits: 1, omittingEmptySubsequences: true).first {
            return normalizeWhitespace(String(first))
        }
        return normalized
    }

    private func incrementFrequency(_ map: inout [Int: [String: Int]], courseScope: Int, label: String) {
        var scoped = map[courseScope] ?? [:]
        scoped[label, default: 0] += 1
        map[courseScope] = scoped
    }

    private func frequency(of label: String, in map: [Int: [String: Int]], courseScope: Int) -> Int {
        map[courseScope]?[label] ?? 0
    }

    private func topicEvidenceText(for leaf: CourseBrainNode) -> String {
        let evidence = [
            normalizedStructuralLabel(leaf.metadata.moduleName),
            normalizedStructuralLabel(folderRoot(from: leaf.metadata.folderPath)),
            urlStructureToken(for: leaf.resourceURL),
            fallbackTopicTitle(for: leaf.type)
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        if evidence.isEmpty {
            return normalizeForMatching(leaf.title)
        }

        return normalizeForMatching(evidence)
    }

    private func structuralCategoryTitle(signal: String, nodeType: CourseBrainNodeType) -> String? {
        let normalized = normalizeForMatching(signal)
        guard !normalized.isEmpty else { return nil }

        if containsAny(in: normalized, keywords: ["orientation", "policy", "procedure", "syllabus", "campus resource", "resource", "important link", "logistic"]) {
            return "Course Admin & Links"
        }
        if containsAny(in: normalized, keywords: ["exam", "midterm", "final", "answer key", "keys", "solution", "review"]) {
            return "Exams & Review"
        }
        if containsAny(in: normalized, keywords: ["lab", "experiment", "manual"]) {
            return "Lab Materials"
        }
        if containsAny(in: normalized, keywords: ["lecture", "slides", "notes", "classppt", "head gsi"]) {
            return "Lecture Materials"
        }
        if containsAny(in: normalized, keywords: ["worksheet", "plws", "practice"]) {
            return "Worksheets & Practice"
        }
        if containsAny(in: normalized, keywords: ["week", "weekly"]) {
            return "Weekly Content"
        }
        if containsAny(in: normalized, keywords: ["external", "redirect", "tool", "link"]) {
            return "External Resources"
        }
        if containsAny(in: normalized, keywords: ["image", "images", "photo", "video", "media"]) {
            return "Media & Images"
        }
        if containsAny(in: normalized, keywords: ["quiz", "discussion"]) {
            return "Quizzes & Discussions"
        }

        switch nodeType {
        case .assignment:
            return "Assignments"
        case .lecture:
            return "Lecture Materials"
        case .file:
            return "Files & Documents"
        default:
            return nil
        }
    }

    private func containsAny(in text: String, keywords: [String]) -> Bool {
        keywords.contains(where: { text.contains($0) })
    }

    private func fallbackTopicTitle(for type: CourseBrainNodeType) -> String {
        switch type {
        case .assignment:
            return "Assignments"
        case .lecture:
            return "Lecture Materials"
        case .file:
            return "Files & Documents"
        case .note:
            return "Notes"
        case .concept:
            return "Concepts"
        case .topic:
            return "Topics"
        }
    }

    private func urlStructureToken(for url: URL?) -> String? {
        guard let path = url?.path.lowercased() else { return nil }

        if path.contains("/assignments/") { return "assignment" }
        if path.contains("/quizzes/") { return "quiz" }
        if path.contains("/discussion_topics/") { return "discussion" }
        if path.contains("/pages/") || path.contains("/wiki/") { return "page" }
        if path.contains("/files/") { return "file" }
        if path.contains("/module_item_redirect/") { return "external link" }
        if path.contains("/external_tools/") || path.contains("/modules/items/") { return "external tool" }
        return nil
    }

    private func buildTopicConceptEdges(
        topicScores: [String: [String: CourseBrainTopicConceptScore]],
        topicToConceptIDs: [String: [String]]
    ) -> [CourseBrainEdge] {
        var edges: [CourseBrainEdge] = []

        for (topicID, conceptIDs) in topicToConceptIDs {
            guard let scoreMap = topicScores[topicID] else { continue }

            for conceptID in conceptIDs {
                guard let score = scoreMap[conceptID] else { continue }

                let relationship = dominantRelationship(for: score.typeCounts)
                edges.append(
                    CourseBrainEdge(
                        id: "topicConcept:\(topicID)->\(conceptID)",
                        source: topicID,
                        target: conceptID,
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

    private func dominantRelationship(for typeCounts: [CourseBrainNodeType: Int]) -> CourseBrainRelationship {
        let assignmentCount = typeCounts[.assignment, default: 0]
        let lectureCount = typeCounts[.lecture, default: 0]
        let fileCount = typeCounts[.file, default: 0]

        if assignmentCount >= lectureCount && assignmentCount >= fileCount && assignmentCount > 0 {
            return .tests
        }
        if lectureCount > 0 || fileCount > 0 {
            return .teaches
        }
        return .references
    }

    private func inferNoteConceptEdges(notes: [CourseBrainNode], concepts: [CourseBrainConceptCacheConcept]) -> [CourseBrainEdge] {
        var edges: [CourseBrainEdge] = []

        for note in notes {
            let text = normalizeForMatching(note.searchableText)
            guard !text.isEmpty else { continue }

            for concept in concepts {
                let phrase = normalizeForMatching(concept.title)
                guard !phrase.isEmpty, text.contains(phrase) else { continue }

                edges.append(
                    CourseBrainEdge(
                        id: "noteConcept:\(note.id)->\(concept.id)",
                        source: note.id,
                        target: concept.id,
                        relationship: .references,
                        directional: true,
                        inferred: true,
                        manualLinkRowId: nil
                    )
                )
            }
        }

        return edges
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

    private func extractConcepts(from nodes: [CourseBrainNode]) -> [CourseBrainConceptCacheConcept] {
        let sources = nodes.compactMap { node -> CourseBrainConceptSource? in
            guard node.type == .lecture || node.type == .assignment || node.type == .note || node.type == .file else {
                return nil
            }

            let text: String
            let kind: CourseBrainConceptSourceKind

            switch node.type {
            case .lecture:
                text = topicEvidenceText(for: node)
                kind = .lecture
            case .assignment:
                text = topicEvidenceText(for: node)
                kind = .assignment
            case .file:
                text = topicEvidenceText(for: node)
                kind = .file
            case .note:
                text = [node.title, node.metadata.bestInstructionText, node.metadata.moduleName, node.metadata.folderPath]
                    .compactMap { $0 }
                    .joined(separator: " ")
                kind = .note
            case .topic, .concept:
                return nil
            }

            guard !normalizeWhitespace(text).isEmpty else { return nil }
            return CourseBrainConceptSource(id: node.id, text: text, kind: kind)
        }

        return CourseBrainConceptExtractor.shared.extractClusters(from: sources).map {
            CourseBrainConceptCacheConcept(id: $0.id, title: $0.title, score: $0.score)
        }
    }

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

        for node in nodes where node.type != .concept && node.type != .topic {
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
        case .topic: return 0
        case .concept: return 1
        case .note: return 2
        case .assignment: return 3
        case .lecture: return 4
        case .file: return 5
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

    private func normalizeWhitespace(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeForMatching(_ raw: String) -> String {
        normalizeWhitespace(raw)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func slugify(_ raw: String) -> String {
        let lowered = normalizeForMatching(raw)
        if lowered.isEmpty {
            return "general"
        }
        return lowered.replacingOccurrences(of: " ", with: "-")
    }

    private func titleFromConceptID(_ conceptID: String) -> String {
        conceptID
            .replacingOccurrences(of: "concept:", with: "")
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

nonisolated func courseBrainStableHash(_ input: String) -> Int64 {
    var hasher = Hasher()
    hasher.combine(input)
    let value = hasher.finalize()
    return Int64(abs(value))
}
