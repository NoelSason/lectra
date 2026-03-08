import Foundation

private struct CourseBrainModuleJoinMatch {
    let module: CourseBrainModule
    let item: CourseBrainModuleItem?
}

private struct CourseBrainModuleJoinIndex {
    let byContentID: [String: CourseBrainModuleJoinMatch]
    let byCanonicalURL: [String: CourseBrainModuleJoinMatch]
    let byTitleAndModule: [String: CourseBrainModuleJoinMatch]
    let byModuleName: [String: CourseBrainModule]
}

enum CourseBrainMissionNormalization {
    static let snapshotItemType = "canvascope_course_snapshot_v1"

    nonisolated static func snapshotFingerprint(for snapshotObject: [String: CourseBrainJSONValue]) -> String {
        let root = CourseBrainJSONValue.object(snapshotObject)
        let canonical = canonicalJSONString(for: root)
        return "snapshot-\(stableDigest(canonical))"
    }

    nonisolated static func canonicalJSONString(for value: CourseBrainJSONValue) -> String {
        let object = jsonObject(for: value)
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "\(value)"
        }
        return string
    }

    nonisolated static func assignmentID(contentId: String?, url: URL?) -> String? {
        if let contentId {
            let trimmed = CourseBrainText.normalizeWhitespace(contentId)
            if !trimmed.isEmpty {
                let digits = trimmed.filter(\.isNumber)
                return digits.isEmpty ? trimmed : digits
            }
        }

        guard let url else { return nil }
        let components = url.pathComponents.map { $0.lowercased() }
        for marker in ["assignments", "quizzes"] {
            if let index = components.firstIndex(of: marker), components.indices.contains(index + 1) {
                let candidate = components[index + 1].filter(\.isNumber)
                if !candidate.isEmpty {
                    return candidate
                }
            }
        }

        return nil
    }

    nonisolated static func canonicalURLString(for url: URL?) -> String? {
        guard let url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else {
            return nil
        }

        components.query = nil
        components.fragment = nil

        var path = components.path.lowercased()
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }

        let scheme = (components.scheme ?? "https").lowercased()
        return "\(scheme)://\(host)\(path)"
    }

    nonisolated static func stableResourceID(
        kind: CourseBrainMissionResourceKind,
        courseId: Int,
        contentId: String?,
        url: URL?,
        title: String,
        moduleName: String?,
        type: String
    ) -> String {
        let seed: String
        if let contentId, !contentId.isEmpty {
            seed = "\(kind.rawValue)|\(courseId)|content|\(contentId)"
        } else if let canonicalURL = canonicalURLString(for: url), !canonicalURL.isEmpty {
            seed = "\(kind.rawValue)|\(courseId)|url|\(canonicalURL)"
        } else {
            seed = [
                kind.rawValue,
                String(courseId),
                CourseBrainText.normalizeForMatching(title),
                CourseBrainText.normalizeForMatching(moduleName ?? ""),
                CourseBrainText.normalizeForMatching(type)
            ].joined(separator: "|")
        }

        return "resource:\(kind.rawValue):\(stableDigest(seed))"
    }

    nonisolated static func legacyNodeID(for resource: MissionResource) -> String? {
        let nodeType: String
        switch resource.kind {
        case .assignment:
            nodeType = CourseBrainNodeType.assignment.rawValue
        case .lecture:
            nodeType = CourseBrainNodeType.lecture.rawValue
        case .page, .discussion, .file:
            nodeType = CourseBrainNodeType.file.rawValue
        case .module:
            return nil
        }

        let primaryKey: String
        if let absoluteURL = resource.url?.absoluteString.lowercased(), !absoluteURL.isEmpty {
            primaryKey = "\(nodeType)|\(absoluteURL)"
        } else {
            primaryKey = [
                nodeType,
                String(resource.courseId),
                CourseBrainText.normalizeForMatching(resource.title),
                CourseBrainText.normalizeForMatching(resource.moduleName ?? ""),
                CourseBrainText.normalizeForMatching(resource.rawItem.firstString(keys: ["type", "itemType", "kind"]) ?? resource.kind.rawValue)
            ].joined(separator: "|")
        }

        return "\(nodeType):\(courseBrainStableHash(primaryKey))"
    }

    nonisolated private static func jsonObject(for value: CourseBrainJSONValue) -> Any {
        switch value {
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        case .array(let values):
            return values.map(jsonObject(for:))
        case .object(let object):
            return Dictionary(uniqueKeysWithValues: object.map { ($0.key, jsonObject(for: $0.value)) })
        }
    }

    nonisolated private static func stableDigest(_ input: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16, uppercase: false)
    }
}

struct CourseBrainMissionNormalizer {
    func buildCourseTwins(
        from rows: [CourseBrainSyncedItemRow],
        manualLinks: [CourseBrainManualLink],
        evidenceLinks: [CourseBrainEvidenceLink],
        missionArtifacts: [CourseBrainMissionArtifact],
        studyPlans: [CourseBrainStudyPlanArtifact]
    ) -> [CourseTwin] {
        var twins: [CourseTwin] = []
        var seenIDs: Set<String> = []

        for row in rows where row.itemType == CourseBrainMissionNormalization.snapshotItemType {
            for snapshotObject in snapshotObjects(from: row) {
                guard let twin = buildCourseTwin(
                    snapshotObject: snapshotObject,
                    manualLinks: manualLinks,
                    evidenceLinks: evidenceLinks,
                    missionArtifacts: missionArtifacts,
                    studyPlans: studyPlans
                ) else {
                    continue
                }

                if seenIDs.insert(twin.id).inserted {
                    twins.append(twin)
                }
            }
        }

        return twins.sorted {
            if $0.metadata.courseName == $1.metadata.courseName {
                return $0.snapshotFingerprint.localizedCaseInsensitiveCompare($1.snapshotFingerprint) == .orderedAscending
            }
            return $0.metadata.courseName.localizedCaseInsensitiveCompare($1.metadata.courseName) == .orderedAscending
        }
    }

    private func snapshotObjects(from row: CourseBrainSyncedItemRow) -> [[String: CourseBrainJSONValue]] {
        if let root = row.itemData.objectValue {
            if let snapshots = root.array("courseSnapshots") {
                return snapshots.compactMap(\.objectValue)
            }

            if root.object("course") != nil || root.array("indexedContent") != nil {
                return [root]
            }
        }

        if let array = row.itemData.arrayValue {
            return array.compactMap(\.objectValue)
        }

        return []
    }

    private func buildCourseTwin(
        snapshotObject: [String: CourseBrainJSONValue],
        manualLinks: [CourseBrainManualLink],
        evidenceLinks: [CourseBrainEvidenceLink],
        missionArtifacts: [CourseBrainMissionArtifact],
        studyPlans: [CourseBrainStudyPlanArtifact]
    ) -> CourseTwin? {
        let courseObject = snapshotObject.object("course") ?? [:]
        let indexedContent = snapshotObject.array("indexedContent") ?? []

        let courseId = courseObject.int("courseId")
            ?? snapshotObject.int("courseId")
            ?? indexedContent.compactMap { $0.objectValue?.int("courseId") }.first

        guard let courseId else { return nil }

        let snapshotFingerprint = CourseBrainMissionNormalization.snapshotFingerprint(for: snapshotObject)
        let assignmentGroups = parseAssignmentGroups(snapshotObject.array("assignmentGroups") ?? [], courseId: courseId)
        let modules = parseModules(snapshotObject.array("modules") ?? [], courseId: courseId)
        let moduleIndex = buildModuleJoinIndex(modules: modules)

        var resources = parseMissionResources(
            indexedContent: indexedContent,
            courseId: courseId,
            snapshotFingerprint: snapshotFingerprint,
            moduleIndex: moduleIndex
        )
        resources.append(contentsOf: syntheticModuleResources(from: modules, courseName: courseObject.firstString(keys: ["courseName", "name"]), snapshotFingerprint: snapshotFingerprint))
        resources = dedupeMissionResources(resources)

        let conceptClusters = buildConceptClusters(from: resources)
        let artifactByAssignment = Dictionary(
            missionArtifacts
                .filter { $0.courseId == courseId && $0.snapshotFingerprint == snapshotFingerprint }
                .map { ($0.assignmentId, $0) },
            uniquingKeysWith: { lhs, rhs in
                lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
            }
        )
        let studyPlanByAssignment = Dictionary(
            studyPlans
                .filter { $0.courseId == courseId && $0.snapshotFingerprint == snapshotFingerprint }
                .map { ($0.assignmentId, $0) },
            uniquingKeysWith: { lhs, rhs in
                lhs.updatedAt >= rhs.updatedAt ? lhs : rhs
            }
        )
        let legacyNodeMap = Dictionary(
            resources.compactMap { resource -> (String, MissionResource)? in
                guard let nodeID = CourseBrainMissionNormalization.legacyNodeID(for: resource) else { return nil }
                return (nodeID, resource)
            },
            uniquingKeysWith: { lhs, rhs in
                let lhsScore = (lhs.primaryText?.count ?? 0) + (lhs.url == nil ? 0 : 1_000)
                let rhsScore = (rhs.primaryText?.count ?? 0) + (rhs.url == nil ? 0 : 1_000)
                return lhsScore >= rhsScore ? lhs : rhs
            }
        )

        let noteEvidence = buildNoteEvidence(
            courseId: courseId,
            snapshotFingerprint: snapshotFingerprint,
            manualLinks: manualLinks,
            evidenceLinks: evidenceLinks,
            legacyNodeMap: legacyNodeMap
        )
        let missions = buildMissions(
            from: resources,
            conceptClusters: conceptClusters,
            noteEvidence: noteEvidence,
            missionArtifacts: artifactByAssignment,
            studyPlans: studyPlanByAssignment
        )

        let metadata = CourseTwinMetadata(
            courseName: courseObject.firstString(keys: ["courseName", "name"])
                ?? snapshotObject.firstString(keys: ["courseName"])
                ?? resources.compactMap(\.courseName).first
                ?? "Course \(courseId)",
            courseCode: courseObject.firstString(keys: ["courseCode"]),
            termName: courseObject.firstString(keys: ["termName"]),
            startAt: courseBrainParseISODate(courseObject.firstString(keys: ["startAt"])),
            endAt: courseBrainParseISODate(courseObject.firstString(keys: ["endAt"])),
            defaultView: courseObject.firstString(keys: ["defaultView"]),
            workflowState: courseObject.firstString(keys: ["workflowState"]),
            enrollmentState: courseObject.firstString(keys: ["enrollmentState"]),
            imageURL: courseObject.firstString(keys: ["imageUrl"]).flatMap(URL.init(string:)),
            syllabusText: courseObject.firstString(keys: ["syllabusText"]),
            platform: snapshotObject.firstString(keys: ["platform"]),
            platformDomain: snapshotObject.firstString(keys: ["platformDomain"]),
            sourceApp: snapshotObject.firstString(keys: ["sourceApp"]),
            sourceKind: snapshotObject.firstString(keys: ["sourceKind"]),
            scannedAt: courseBrainParseISODate(snapshotObject.firstString(keys: ["scannedAt"])),
            teacherSummaries: parseTeacherSummaries(snapshotObject.array("teacherSummaries") ?? []),
            scanStats: snapshotObject.object("scanStats") ?? [:]
        )

        return CourseTwin(
            courseId: courseId,
            snapshotFingerprint: snapshotFingerprint,
            metadata: metadata,
            assignmentGroups: assignmentGroups,
            modules: modules,
            resources: resources.sorted(by: missionResourceSort),
            missions: missions,
            conceptClusters: conceptClusters,
            noteEvidence: noteEvidence.sorted { $0.createdAt < $1.createdAt }
        )
    }

    private func parseAssignmentGroups(_ array: [CourseBrainJSONValue], courseId: Int) -> [CourseBrainAssignmentGroup] {
        array.compactMap { value in
            guard let object = value.objectValue else { return nil }
            let name = object.firstString(keys: ["name"]) ?? "Assignment Group"
            return CourseBrainAssignmentGroup(
                courseId: courseId,
                rawGroupId: object.string("id") ?? object.int("id").map(String.init),
                name: name,
                position: object.int("position"),
                groupWeight: object.double("groupWeight"),
                rules: object.object("rules") ?? [:]
            )
        }
        .sorted {
            switch ($0.position, $1.position) {
            case let (lhs?, rhs?):
                return lhs < rhs
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private func parseModules(_ array: [CourseBrainJSONValue], courseId: Int) -> [CourseBrainModule] {
        array.compactMap { value in
            guard let object = value.objectValue else { return nil }
            let name = object.firstString(keys: ["name", "title"]) ?? "Module"
            let moduleID = object.string("id") ?? object.int("id").map(String.init)
            let moduleIdentity = moduleID ?? "module:\(courseId):\(courseBrainStableHash(name))"
            let items = (object.array("items") ?? []).compactMap { itemValue -> CourseBrainModuleItem? in
                guard let item = itemValue.objectValue else { return nil }
                return CourseBrainModuleItem(
                    moduleId: moduleIdentity,
                    rawItemId: item.string("id") ?? item.int("id").map(String.init),
                    contentId: item.string("contentId") ?? item.int("contentId").map(String.init),
                    position: item.int("position"),
                    title: item.firstString(keys: ["title", "name"]) ?? "Untitled Item",
                    type: item.firstString(keys: ["type", "itemType", "kind"]) ?? "item",
                    url: item.firstString(keys: ["url"]).flatMap(URL.init(string:)),
                    pageURL: item.firstString(keys: ["pageUrl"]),
                    published: item.bool("published"),
                    completionRequirement: item.object("completionRequirement") ?? [:],
                    contentDetails: item.object("contentDetails") ?? [:]
                )
            }
            .sorted {
                switch ($0.position, $1.position) {
                case let (lhs?, rhs?):
                    return lhs < rhs
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            }

            return CourseBrainModule(
                courseId: courseId,
                rawModuleId: moduleID,
                name: name,
                position: object.int("position"),
                published: object.bool("published"),
                unlockAt: courseBrainParseISODate(object.firstString(keys: ["unlockAt"])),
                items: items
            )
        }
        .sorted {
            switch ($0.position, $1.position) {
            case let (lhs?, rhs?):
                return lhs < rhs
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private func buildModuleJoinIndex(modules: [CourseBrainModule]) -> CourseBrainModuleJoinIndex {
        var byContentID: [String: CourseBrainModuleJoinMatch] = [:]
        var byCanonicalURL: [String: CourseBrainModuleJoinMatch] = [:]
        var byTitleAndModule: [String: CourseBrainModuleJoinMatch] = [:]
        var byModuleName: [String: CourseBrainModule] = [:]

        for module in modules {
            let normalizedModuleName = CourseBrainText.normalizeForMatching(module.name)
            if !normalizedModuleName.isEmpty, byModuleName[normalizedModuleName] == nil {
                byModuleName[normalizedModuleName] = module
            }

            for item in module.items {
                let match = CourseBrainModuleJoinMatch(module: module, item: item)

                if let contentId = item.contentId?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !contentId.isEmpty,
                   byContentID[contentId] == nil {
                    byContentID[contentId] = match
                }

                if let canonicalURL = CourseBrainMissionNormalization.canonicalURLString(for: item.url),
                   !canonicalURL.isEmpty,
                   byCanonicalURL[canonicalURL] == nil {
                    byCanonicalURL[canonicalURL] = match
                }

                let titleKey = titleModuleKey(title: item.title, moduleName: module.name)
                if !titleKey.isEmpty, byTitleAndModule[titleKey] == nil {
                    byTitleAndModule[titleKey] = match
                }
            }
        }

        return CourseBrainModuleJoinIndex(
            byContentID: byContentID,
            byCanonicalURL: byCanonicalURL,
            byTitleAndModule: byTitleAndModule,
            byModuleName: byModuleName
        )
    }

    private func parseMissionResources(
        indexedContent: [CourseBrainJSONValue],
        courseId: Int,
        snapshotFingerprint: String,
        moduleIndex: CourseBrainModuleJoinIndex
    ) -> [MissionResource] {
        indexedContent.compactMap { value -> MissionResource? in
            guard let object = value.objectValue else { return nil }

            let title = object.firstString(keys: ["title", "name", "label"]) ?? "Untitled Resource"
            let rawType = object.firstString(keys: ["type", "itemType", "kind"]) ?? "resource"
            let matchedModule = moduleJoinMatch(for: object, index: moduleIndex)
            let moduleName = object.firstString(keys: ["moduleName", "module", "section"]) ?? matchedModule?.module.name
            let kind = missionResourceKind(for: object, title: title, moduleName: moduleName, rawType: rawType)
            let urlString = object.firstString(keys: ["url", "sourceUrl", "source_url"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let url = urlString.flatMap { URL(string: $0) }
            let contentId = object.string("contentId") ?? object.int("contentId").map(String.init) ?? matchedModule?.item?.contentId
            let assignmentId = kind == .assignment
                ? (CourseBrainMissionNormalization.assignmentID(contentId: contentId, url: url) ?? CourseBrainMissionNormalization.stableResourceID(
                    kind: kind,
                    courseId: courseId,
                    contentId: contentId,
                    url: url,
                    title: title,
                    moduleName: moduleName,
                    type: rawType
                ))
                : nil
            let resourceID = CourseBrainMissionNormalization.stableResourceID(
                kind: kind,
                courseId: courseId,
                contentId: contentId,
                url: url,
                title: title,
                moduleName: moduleName,
                type: rawType
            )

            return MissionResource(
                id: resourceID,
                kind: kind,
                courseId: courseId,
                snapshotFingerprint: snapshotFingerprint,
                assignmentId: assignmentId,
                title: CourseBrainText.normalizeWhitespace(title),
                courseName: object.firstString(keys: ["courseName", "course_name"]),
                moduleId: matchedModule?.module.id,
                moduleName: moduleName,
                modulePosition: matchedModule?.module.position,
                moduleItemId: matchedModule?.item?.id,
                moduleItemPosition: matchedModule?.item?.position,
                assignmentGroupId: object.string("assignmentGroupId") ?? object.int("assignmentGroupId").map(String.init),
                assignmentGroupName: object.firstString(keys: ["assignmentGroupName"]),
                folderPath: object.firstString(keys: ["folderPath", "folder_path"]),
                dueAt: courseBrainParseISODate(object.firstString(keys: ["dueAt", "due_at"]))
                    ?? courseBrainParseISODate(matchedModule?.item?.contentDetails.firstString(keys: ["dueAt", "due_at"])),
                unlockAt: courseBrainParseISODate(object.firstString(keys: ["unlockAt", "unlock_at"]))
                    ?? courseBrainParseISODate(matchedModule?.item?.contentDetails.firstString(keys: ["unlockAt", "unlock_at"]))
                    ?? matchedModule?.module.unlockAt,
                lockAt: courseBrainParseISODate(object.firstString(keys: ["lockAt", "lock_at"]))
                    ?? courseBrainParseISODate(matchedModule?.item?.contentDetails.firstString(keys: ["lockAt", "lock_at"])),
                scannedAt: courseBrainParseISODate(object.firstString(keys: ["scannedAt", "scanned_at"])),
                updatedAt: courseBrainParseISODate(object.firstString(keys: ["updatedAt", "updated_at"])),
                published: object.bool("published") ?? matchedModule?.item?.published ?? matchedModule?.module.published,
                pointsPossible: object.double("pointsPossible")
                    ?? matchedModule?.item?.contentDetails.double("pointsPossible"),
                submissionTypes: object.stringArray("submissionTypes"),
                allowedExtensions: object.stringArray("allowedExtensions"),
                platform: object.firstString(keys: ["platform"]),
                platformDomain: object.firstString(keys: ["platformDomain"]),
                url: url,
                contentId: contentId,
                contentType: object.firstString(keys: ["contentType"]),
                sizeBytes: object.int("sizeBytes"),
                instructions: object.firstString(keys: ["instructions"]),
                description: object.firstString(keys: ["description"]),
                body: object.firstString(keys: ["body"]),
                content: object.firstString(keys: ["content"]),
                text: object.firstString(keys: ["text"]),
                rawItem: object
            )
        }
    }

    private func syntheticModuleResources(
        from modules: [CourseBrainModule],
        courseName: String?,
        snapshotFingerprint: String
    ) -> [MissionResource] {
        modules.map { module in
            MissionResource(
                id: "resource:module:\(module.id)",
                kind: .module,
                courseId: module.courseId,
                snapshotFingerprint: snapshotFingerprint,
                assignmentId: nil,
                title: module.name,
                courseName: courseName,
                moduleId: module.id,
                moduleName: module.name,
                modulePosition: module.position,
                moduleItemId: nil,
                moduleItemPosition: nil,
                assignmentGroupId: nil,
                assignmentGroupName: nil,
                folderPath: nil,
                dueAt: nil,
                unlockAt: module.unlockAt,
                lockAt: nil,
                scannedAt: nil,
                updatedAt: nil,
                published: module.published,
                pointsPossible: nil,
                submissionTypes: [],
                allowedExtensions: [],
                platform: nil,
                platformDomain: nil,
                url: nil,
                contentId: module.rawModuleId,
                contentType: "module",
                sizeBytes: nil,
                instructions: nil,
                description: nil,
                body: nil,
                content: nil,
                text: module.items.map(\.title).joined(separator: "\n"),
                rawItem: [:]
            )
        }
    }

    private func dedupeMissionResources(_ resources: [MissionResource]) -> [MissionResource] {
        var merged: [String: MissionResource] = [:]
        for resource in resources {
            if let existing = merged[resource.id] {
                merged[resource.id] = merge(existing: existing, incoming: resource)
            } else {
                merged[resource.id] = resource
            }
        }
        return Array(merged.values)
    }

    private func merge(existing: MissionResource, incoming: MissionResource) -> MissionResource {
        MissionResource(
            id: existing.id,
            kind: existing.kind,
            courseId: existing.courseId,
            snapshotFingerprint: existing.snapshotFingerprint,
            assignmentId: existing.assignmentId ?? incoming.assignmentId,
            title: existing.title.count >= incoming.title.count ? existing.title : incoming.title,
            courseName: existing.courseName ?? incoming.courseName,
            moduleId: existing.moduleId ?? incoming.moduleId,
            moduleName: existing.moduleName ?? incoming.moduleName,
            modulePosition: existing.modulePosition ?? incoming.modulePosition,
            moduleItemId: existing.moduleItemId ?? incoming.moduleItemId,
            moduleItemPosition: existing.moduleItemPosition ?? incoming.moduleItemPosition,
            assignmentGroupId: existing.assignmentGroupId ?? incoming.assignmentGroupId,
            assignmentGroupName: existing.assignmentGroupName ?? incoming.assignmentGroupName,
            folderPath: existing.folderPath ?? incoming.folderPath,
            dueAt: existing.dueAt ?? incoming.dueAt,
            unlockAt: existing.unlockAt ?? incoming.unlockAt,
            lockAt: existing.lockAt ?? incoming.lockAt,
            scannedAt: existing.scannedAt ?? incoming.scannedAt,
            updatedAt: existing.updatedAt ?? incoming.updatedAt,
            published: existing.published ?? incoming.published,
            pointsPossible: existing.pointsPossible ?? incoming.pointsPossible,
            submissionTypes: existing.submissionTypes.isEmpty ? incoming.submissionTypes : existing.submissionTypes,
            allowedExtensions: existing.allowedExtensions.isEmpty ? incoming.allowedExtensions : existing.allowedExtensions,
            platform: existing.platform ?? incoming.platform,
            platformDomain: existing.platformDomain ?? incoming.platformDomain,
            url: existing.url ?? incoming.url,
            contentId: existing.contentId ?? incoming.contentId,
            contentType: existing.contentType ?? incoming.contentType,
            sizeBytes: existing.sizeBytes ?? incoming.sizeBytes,
            instructions: existing.instructions ?? incoming.instructions,
            description: existing.description ?? incoming.description,
            body: existing.body ?? incoming.body,
            content: existing.content ?? incoming.content,
            text: existing.text ?? incoming.text,
            rawItem: existing.rawItem.merging(incoming.rawItem) { current, _ in current }
        )
    }

    private func buildConceptClusters(from resources: [MissionResource]) -> [ConceptCluster] {
        let sources = resources.compactMap { resource -> CourseBrainConceptSource? in
            let text = [
                resource.title,
                resource.moduleName,
                resource.assignmentGroupName,
                resource.folderPath,
                resource.primaryText
            ]
            .compactMap { $0 }
            .joined(separator: " ")

            guard !CourseBrainText.normalizeWhitespace(text).isEmpty else { return nil }
            return CourseBrainConceptSource(id: resource.id, text: text, kind: conceptSourceKind(for: resource.kind))
        }

        return CourseBrainConceptExtractor.shared.extractClusters(from: sources)
    }

    private func buildNoteEvidence(
        courseId: Int,
        snapshotFingerprint: String,
        manualLinks: [CourseBrainManualLink],
        evidenceLinks: [CourseBrainEvidenceLink],
        legacyNodeMap: [String: MissionResource]
    ) -> [NoteEvidence] {
        var results: [NoteEvidence] = []

        for manualLink in manualLinks {
            guard manualLink.courseId == courseId
                || legacyNodeMap[manualLink.targetNodeId] != nil else {
                continue
            }

            let targetKind: CourseBrainEvidenceTargetKind
            let targetID: String
            let assignmentID: String?

            if let resource = legacyNodeMap[manualLink.targetNodeId], resource.kind == .assignment {
                targetKind = .assignment
                targetID = resource.assignmentId ?? resource.id
                assignmentID = resource.assignmentId
            } else if manualLink.targetNodeId.hasPrefix("concept:") {
                targetKind = .concept
                targetID = manualLink.targetNodeId
                assignmentID = nil
            } else if let resource = legacyNodeMap[manualLink.targetNodeId], resource.kind == .lecture {
                targetKind = .lecture
                targetID = resource.id
                assignmentID = nil
            } else if let resource = legacyNodeMap[manualLink.targetNodeId] {
                targetKind = .resource
                targetID = resource.id
                assignmentID = nil
            } else {
                targetKind = .resource
                targetID = manualLink.targetNodeId
                assignmentID = nil
            }

            results.append(
                NoteEvidence(
                    id: "manual:\(manualLink.rowId.uuidString)",
                    rowId: manualLink.rowId,
                    courseId: manualLink.courseId ?? courseId,
                    assignmentId: assignmentID,
                    snapshotFingerprint: snapshotFingerprint,
                    sourceKind: .manualLink,
                    targetKind: targetKind,
                    targetId: targetID,
                    sourceNodeId: manualLink.sourceNodeId,
                    sourceDocumentId: nil,
                    selectionText: nil,
                    excerpt: nil,
                    pageIndex: nil,
                    pageRect: nil,
                    createdAt: manualLink.createdAt,
                    updatedAt: manualLink.createdAt,
                    rawPayload: [
                        "sourceNodeId": .string(manualLink.sourceNodeId),
                        "targetNodeId": .string(manualLink.targetNodeId),
                        "relationship": .string(manualLink.relationship.rawValue)
                    ]
                )
            )
        }

        for evidenceLink in evidenceLinks {
            guard evidenceLink.courseId == nil || evidenceLink.courseId == courseId else { continue }
            guard evidenceLink.snapshotFingerprint == nil || evidenceLink.snapshotFingerprint == snapshotFingerprint else { continue }

            results.append(
                NoteEvidence(
                    id: evidenceLink.rowId.uuidString,
                    rowId: evidenceLink.rowId,
                    courseId: evidenceLink.courseId ?? courseId,
                    assignmentId: evidenceLink.assignmentId,
                    snapshotFingerprint: evidenceLink.snapshotFingerprint ?? snapshotFingerprint,
                    sourceKind: evidenceLink.sourceKind,
                    targetKind: evidenceLink.targetKind,
                    targetId: evidenceLink.targetId,
                    sourceNodeId: evidenceLink.sourceNodeId,
                    sourceDocumentId: evidenceLink.sourceDocumentId,
                    selectionText: evidenceLink.selectionText,
                    excerpt: evidenceLink.excerpt,
                    pageIndex: evidenceLink.pageIndex,
                    pageRect: evidenceLink.pageRect,
                    createdAt: evidenceLink.createdAt,
                    updatedAt: evidenceLink.updatedAt,
                    rawPayload: evidenceLink.rawPayload
                )
            )
        }

        var deduped: [String: NoteEvidence] = [:]
        for evidence in results {
            deduped[evidence.id] = evidence
        }
        return Array(deduped.values)
    }

    private func buildMissions(
        from resources: [MissionResource],
        conceptClusters: [ConceptCluster],
        noteEvidence: [NoteEvidence],
        missionArtifacts: [String: CourseBrainMissionArtifact],
        studyPlans: [String: CourseBrainStudyPlanArtifact]
    ) -> [CourseMission] {
        resources
            .filter { $0.kind == .assignment }
            .map { resource in
                let assignmentID = resource.assignmentId ?? resource.id
                let linkedConcepts = conceptClusters
                    .filter { $0.resourceIDs.contains(resource.id) }
                    .sorted { lhs, rhs in lhs.score > rhs.score }
                    .map(\.id)
                let linkedEvidence = noteEvidence
                    .filter { $0.assignmentId == assignmentID }
                    .sorted { $0.createdAt < $1.createdAt }
                    .map(\.id)

                return CourseMission(
                    courseId: resource.courseId,
                    assignmentId: assignmentID,
                    snapshotFingerprint: resource.snapshotFingerprint,
                    title: resource.title,
                    resourceId: resource.id,
                    moduleId: resource.moduleId,
                    moduleName: resource.moduleName,
                    modulePosition: resource.modulePosition,
                    assignmentGroupId: resource.assignmentGroupId,
                    assignmentGroupName: resource.assignmentGroupName,
                    dueAt: resource.dueAt,
                    unlockAt: resource.unlockAt,
                    lockAt: resource.lockAt,
                    pointsPossible: resource.pointsPossible,
                    submissionTypes: resource.submissionTypes,
                    allowedExtensions: resource.allowedExtensions,
                    instructions: resource.instructions ?? resource.description ?? resource.body ?? resource.content ?? resource.text,
                    url: resource.url,
                    linkedConceptIDs: linkedConcepts,
                    linkedEvidenceIDs: linkedEvidence,
                    missionArtifact: missionArtifacts[assignmentID],
                    studyPlan: studyPlans[assignmentID]
                )
            }
            .sorted {
                switch ($0.dueAt, $1.dueAt) {
                case let (lhs?, rhs?):
                    return lhs < rhs
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            }
    }

    private func missionResourceKind(
        for object: [String: CourseBrainJSONValue],
        title: String,
        moduleName: String?,
        rawType: String
    ) -> CourseBrainMissionResourceKind {
        let normalizedType = CourseBrainText.normalizeForMatching(rawType)
        if normalizedType == "assignment" || normalizedType == "quiz" {
            return .assignment
        }

        if isLectureLike(title: title, moduleName: moduleName) {
            return .lecture
        }

        switch normalizedType {
        case "page":
            return .page
        case "discussion":
            return .discussion
        default:
            return .file
        }
    }

    private func isLectureLike(title: String, moduleName: String?) -> Bool {
        let haystack = CourseBrainText.normalizeForMatching([title, moduleName].compactMap { $0 }.joined(separator: " "))
        guard !haystack.isEmpty else { return false }
        return haystack.contains("lecture")
            || haystack.contains(" lec ")
            || haystack.hasPrefix("lec ")
            || haystack.contains(" session ")
            || haystack.contains(" class ")
    }

    private func moduleJoinMatch(
        for object: [String: CourseBrainJSONValue],
        index: CourseBrainModuleJoinIndex
    ) -> CourseBrainModuleJoinMatch? {
        if let contentId = object.string("contentId") ?? object.int("contentId").map(String.init),
           let match = index.byContentID[contentId] {
            return match
        }

        if let canonicalURL = CourseBrainMissionNormalization.canonicalURLString(for: object.firstString(keys: ["url", "sourceUrl", "source_url"]).flatMap(URL.init(string:))),
           let match = index.byCanonicalURL[canonicalURL] {
            return match
        }

        let title = object.firstString(keys: ["title", "name", "label"]) ?? ""
        let moduleName = object.firstString(keys: ["moduleName", "module", "section"]) ?? ""
        let titleKey = titleModuleKey(title: title, moduleName: moduleName)
        if let match = index.byTitleAndModule[titleKey] {
            return match
        }

        let normalizedModuleName = CourseBrainText.normalizeForMatching(moduleName)
        if let module = index.byModuleName[normalizedModuleName] {
            return CourseBrainModuleJoinMatch(module: module, item: nil)
        }

        return nil
    }

    private func titleModuleKey(title: String, moduleName: String) -> String {
        let normalizedTitle = CourseBrainText.normalizeForMatching(title)
        let normalizedModule = CourseBrainText.normalizeForMatching(moduleName)
        if normalizedTitle.isEmpty && normalizedModule.isEmpty {
            return ""
        }
        return "\(normalizedTitle)|\(normalizedModule)"
    }

    private func conceptSourceKind(for resourceKind: CourseBrainMissionResourceKind) -> CourseBrainConceptSourceKind {
        switch resourceKind {
        case .assignment:
            return .assignment
        case .lecture:
            return .lecture
        case .page:
            return .page
        case .discussion:
            return .discussion
        case .module:
            return .module
        case .file:
            return .file
        }
    }

    private func parseTeacherSummaries(_ array: [CourseBrainJSONValue]) -> [String] {
        array.compactMap { value in
            if let string = value.stringValue, !string.isEmpty {
                return string
            }
            guard let object = value.objectValue else { return nil }
            return object.firstString(keys: ["name", "displayName", "title", "email"])
        }
    }

    private func missionResourceSort(lhs: MissionResource, rhs: MissionResource) -> Bool {
        if lhs.kind == rhs.kind {
            if lhs.modulePosition == rhs.modulePosition {
                if lhs.moduleItemPosition == rhs.moduleItemPosition {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return (lhs.moduleItemPosition ?? Int.max) < (rhs.moduleItemPosition ?? Int.max)
            }
            return (lhs.modulePosition ?? Int.max) < (rhs.modulePosition ?? Int.max)
        }
        return lhs.kind.rawValue < rhs.kind.rawValue
    }
}

private extension Dictionary where Key == String, Value == CourseBrainJSONValue {
    func stringArray(_ key: String) -> [String] {
        array(key)?
            .compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }
}
