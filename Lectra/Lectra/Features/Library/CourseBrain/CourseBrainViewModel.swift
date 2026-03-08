import Foundation
import Combine

enum CourseBrainAssignmentBucket: String, CaseIterable, Identifiable, Hashable {
    case pastWeek = "Past 7 Days"
    case nextWeek = "Next 7 Days"
    case nextMonth = "Next 30 Days"

    var id: String { rawValue }
}

struct CourseBrainCourseFilter: Identifiable, Hashable {
    let id: Int
    let name: String
    let count: Int
}

struct CourseBrainAssignmentSummary: Identifiable, Hashable {
    let id: String
    let courseId: Int
    let courseName: String
    let title: String
    let moduleId: String?
    let moduleName: String?
    let assignmentGroupId: String?
    let assignmentGroupName: String?
    let dueAt: Date?
    let unlockAt: Date?
    let lockAt: Date?
    let anchorDate: Date
    let instructions: String?
    let url: URL?
    let snapshotFingerprint: String
    let lastSyncedAt: Date?
    let mission: CourseMission

    var searchableText: String {
        [
            title,
            courseName,
            moduleName,
            assignmentGroupName,
            instructions,
            headlineSubmissionStatus?.displayTitle,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    var headlineSubmissionStatus: CourseBrainSubmissionStatus? {
        mission.headlineSubmissionStatus
    }
}

struct CourseBrainAssignmentSection: Identifiable, Hashable {
    let bucket: CourseBrainAssignmentBucket
    let items: [CourseBrainAssignmentSummary]

    var id: String { bucket.id }
}

struct CourseBrainRelatedResource: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let kind: CourseBrainMissionResourceKind
    let url: URL?
    let date: Date?
    let assignmentId: String?
    let submitted: Bool?
    let submissionStatus: CourseBrainSubmissionStatus?
    let submissionSummary: CourseBrainSubmissionSummary?

    var headlineSubmissionStatus: CourseBrainSubmissionStatus? {
        CourseBrainSubmissionStatus.resolveHeadlineStatus(
            submitted: submitted,
            submissionStatus: submissionStatus,
            submissionSummary: submissionSummary
        )
    }
}

struct CourseBrainRelatedDocument: Identifiable, Hashable {
    let id: UUID
    let title: String
    let updatedAt: Date
    let status: DocumentStatus
}

struct CourseBrainEvidencePreview: Identifiable, Hashable {
    let id: String
    let title: String
    let excerpt: String?
    let documentId: UUID?
}

struct CourseBrainAssignmentDetail: Hashable {
    let assignment: CourseBrainAssignmentSummary
    let lastSyncedAt: Date?
    let relatedResources: [CourseBrainRelatedResource]
    let relatedDocuments: [CourseBrainRelatedDocument]
    let evidence: [CourseBrainEvidencePreview]
}

struct CourseBrainDashboardData {
    let assignments: [CourseBrainAssignmentSummary]
    let courseFilters: [CourseBrainCourseFilter]
    let detailsByAssignmentID: [String: CourseBrainAssignmentDetail]
    let overallLastSyncedAt: Date?
}

struct CourseBrainDashboardBuilder {
    private let pastWindowDays: TimeInterval = 7 * 24 * 60 * 60
    private let futureWindowDays: TimeInterval = 30 * 24 * 60 * 60

    func build(
        courseTwins: [CourseTwin],
        documents: [LocalDocument],
        noteNodes: [CourseBrainNode],
        now: Date = Date()
    ) -> CourseBrainDashboardData {
        let latestTwins = latestTwinByCourse(from: courseTwins)
        let noteTitles = Dictionary(uniqueKeysWithValues: noteNodes.map { ($0.id, $0.title) })

        var documentLookup: [UUID: LocalDocument] = [:]
        for document in documents {
            documentLookup[document.id] = document
            documentLookup[document.supabaseRowId] = document
        }

        var assignments: [CourseBrainAssignmentSummary] = []
        var detailsByAssignmentID: [String: CourseBrainAssignmentDetail] = [:]

        for twin in latestTwins.values {
            let lastSyncedAt = courseLastSyncedAt(for: twin)
            let visibleMissions = twin.missions.compactMap { mission -> CourseBrainAssignmentSummary? in
                guard let anchorDate = anchorDate(for: mission),
                      isVisible(anchorDate: anchorDate, now: now) else {
                    return nil
                }

                return CourseBrainAssignmentSummary(
                    id: assignmentID(for: mission),
                    courseId: mission.courseId,
                    courseName: twin.metadata.courseName,
                    title: mission.title,
                    moduleId: mission.moduleId,
                    moduleName: mission.moduleName,
                    assignmentGroupId: mission.assignmentGroupId,
                    assignmentGroupName: mission.assignmentGroupName,
                    dueAt: mission.dueAt,
                    unlockAt: mission.unlockAt,
                    lockAt: mission.lockAt,
                    anchorDate: anchorDate,
                    instructions: mission.instructions,
                    url: mission.url,
                    snapshotFingerprint: mission.snapshotFingerprint,
                    lastSyncedAt: lastSyncedAt,
                    mission: mission
                )
            }

            for assignment in visibleMissions {
                assignments.append(assignment)
                detailsByAssignmentID[assignment.id] = buildDetail(
                    for: assignment,
                    twin: twin,
                    documents: documents,
                    documentLookup: documentLookup,
                    noteTitles: noteTitles
                )
            }
        }

        assignments.sort(by: sortAssignments)

        let courseFilters = assignments
            .reduce(into: [Int: CourseBrainCourseFilter]()) { partialResult, assignment in
                let existing = partialResult[assignment.courseId]
                partialResult[assignment.courseId] = CourseBrainCourseFilter(
                    id: assignment.courseId,
                    name: existing?.name ?? assignment.courseName,
                    count: (existing?.count ?? 0) + 1
                )
            }
            .values
            .sorted {
                if $0.name == $1.name {
                    return $0.id < $1.id
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

        let overallLastSyncedAt = latestTwins.values.compactMap(courseLastSyncedAt(for:)).max()

        return CourseBrainDashboardData(
            assignments: assignments,
            courseFilters: courseFilters,
            detailsByAssignmentID: detailsByAssignmentID,
            overallLastSyncedAt: overallLastSyncedAt
        )
    }

    func buildSections(assignments: [CourseBrainAssignmentSummary], now: Date = Date()) -> [CourseBrainAssignmentSection] {
        var buckets: [CourseBrainAssignmentBucket: [CourseBrainAssignmentSummary]] = [
            .pastWeek: [],
            .nextWeek: [],
            .nextMonth: [],
        ]

        for assignment in assignments {
            let bucket: CourseBrainAssignmentBucket
            if assignment.anchorDate < now {
                bucket = .pastWeek
            } else if assignment.anchorDate <= now.addingTimeInterval(pastWindowDays) {
                bucket = .nextWeek
            } else {
                bucket = .nextMonth
            }
            buckets[bucket, default: []].append(assignment)
        }

        return CourseBrainAssignmentBucket.allCases.compactMap { bucket in
            guard let items = buckets[bucket], !items.isEmpty else { return nil }
            return CourseBrainAssignmentSection(bucket: bucket, items: items.sorted(by: sortAssignments))
        }
    }

    func anchorDate(for mission: CourseMission) -> Date? {
        mission.dueAt ?? mission.unlockAt ?? mission.lockAt
    }

    private func assignmentID(for mission: CourseMission) -> String {
        "assignment:\(mission.courseId):\(mission.assignmentId):\(mission.snapshotFingerprint)"
    }

    private func latestTwinByCourse(from courseTwins: [CourseTwin]) -> [Int: CourseTwin] {
        courseTwins.reduce(into: [Int: CourseTwin]()) { partialResult, twin in
            guard let existing = partialResult[twin.courseId] else {
                partialResult[twin.courseId] = twin
                return
            }

            let existingSync = courseLastSyncedAt(for: existing) ?? .distantPast
            let incomingSync = courseLastSyncedAt(for: twin) ?? .distantPast

            if incomingSync > existingSync {
                partialResult[twin.courseId] = twin
                return
            }

            if incomingSync == existingSync, twin.missions.count > existing.missions.count {
                partialResult[twin.courseId] = twin
            }
        }
    }

    private func courseLastSyncedAt(for twin: CourseTwin) -> Date? {
        twin.metadata.scannedAt
            ?? twin.resources.compactMap(\.scannedAt).max()
            ?? twin.resources.compactMap(\.updatedAt).max()
    }

    private func buildDetail(
        for assignment: CourseBrainAssignmentSummary,
        twin: CourseTwin,
        documents: [LocalDocument],
        documentLookup: [UUID: LocalDocument],
        noteTitles: [String: String]
    ) -> CourseBrainAssignmentDetail {
        let relatedResources = twin.resources
            .filter { resource in
                if resource.kind == .module {
                    return false
                }

                if resource.kind == .assignment {
                    return resource.id != assignment.mission.resourceId
                        && resource.assignmentId == assignment.mission.assignmentId
                }

                return true
            }
            .sorted { lhs, rhs in
                relatedResourceSort(lhs: lhs, rhs: rhs, assignment: assignment)
            }
            .prefix(6)
            .map { resource in
                let kindLabel = firstNonEmpty([
                    resource.rawItem.firstString(keys: ["type", "itemType", "kind"])?.capitalized,
                    resource.kind.rawValue.capitalized,
                ])
                let subtitleParts: [String] = [
                    kindLabel,
                    resource.moduleName,
                    resource.assignmentGroupName,
                ]
                .compactMap { part in
                    guard let part else { return nil }
                    let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }

                return CourseBrainRelatedResource(
                    id: resource.id,
                    title: resource.title,
                    subtitle: subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " • "),
                    kind: resource.kind,
                    url: resource.url,
                    date: resource.dueAt ?? resource.unlockAt ?? resource.lockAt ?? resource.updatedAt ?? resource.scannedAt,
                    assignmentId: resource.assignmentId,
                    submitted: resource.submitted,
                    submissionStatus: resource.submissionStatus,
                    submissionSummary: resource.submissionSummary
                )
            }

        let relatedDocuments = documents
            .filter { $0.courseId == assignment.courseId }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .prefix(6)
            .map { document in
                CourseBrainRelatedDocument(
                    id: document.id,
                    title: document.title,
                    updatedAt: document.updatedAt,
                    status: document.status
                )
            }

        let evidence = twin.noteEvidence
            .filter { $0.assignmentId == assignment.mission.assignmentId }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.id < rhs.id
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .prefix(6)
            .map { item in
                let title: String
                if let sourceNodeId = item.sourceNodeId,
                   let noteTitle = noteTitles[sourceNodeId] {
                    title = noteTitle
                } else if let sourceDocumentId = item.sourceDocumentId,
                          let document = documentLookup[sourceDocumentId] {
                    title = document.title
                } else {
                    title = "Linked Note"
                }

                return CourseBrainEvidencePreview(
                    id: item.id,
                    title: title,
                    excerpt: firstNonEmpty([item.selectionText, item.excerpt]),
                    documentId: item.sourceDocumentId.flatMap { documentLookup[$0] != nil ? $0 : nil }
                )
            }

        return CourseBrainAssignmentDetail(
            assignment: assignment,
            lastSyncedAt: assignment.lastSyncedAt,
            relatedResources: relatedResources,
            relatedDocuments: relatedDocuments,
            evidence: evidence
        )
    }

    private func relatedResourceSort(
        lhs: MissionResource,
        rhs: MissionResource,
        assignment: CourseBrainAssignmentSummary
    ) -> Bool {
        let lhsSameAssignment = lhs.assignmentId == assignment.mission.assignmentId && lhs.assignmentId != nil
        let rhsSameAssignment = rhs.assignmentId == assignment.mission.assignmentId && rhs.assignmentId != nil
        if lhsSameAssignment != rhsSameAssignment {
            return lhsSameAssignment
        }

        let lhsSameModuleID = lhs.moduleId == assignment.moduleId && assignment.moduleId != nil
        let rhsSameModuleID = rhs.moduleId == assignment.moduleId && assignment.moduleId != nil
        if lhsSameModuleID != rhsSameModuleID {
            return lhsSameModuleID
        }

        let lhsSameModuleName = normalized(lhs.moduleName) == normalized(assignment.moduleName)
            && !normalized(assignment.moduleName).isEmpty
        let rhsSameModuleName = normalized(rhs.moduleName) == normalized(assignment.moduleName)
            && !normalized(assignment.moduleName).isEmpty
        if lhsSameModuleName != rhsSameModuleName {
            return lhsSameModuleName
        }

        let lhsSameGroup = sameAssignmentGroup(resource: lhs, assignment: assignment)
        let rhsSameGroup = sameAssignmentGroup(resource: rhs, assignment: assignment)
        if lhsSameGroup != rhsSameGroup {
            return lhsSameGroup
        }

        let lhsDistance = dateDistance(resource: lhs, anchorDate: assignment.anchorDate)
        let rhsDistance = dateDistance(resource: rhs, anchorDate: assignment.anchorDate)
        if lhsDistance != rhsDistance {
            return lhsDistance < rhsDistance
        }

        let lhsPriority = resourceKindPriority(lhs.kind)
        let rhsPriority = resourceKindPriority(rhs.kind)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func resourceKindPriority(_ kind: CourseBrainMissionResourceKind) -> Int {
        switch kind {
        case .lecture:
            return 0
        case .page:
            return 1
        case .discussion:
            return 2
        case .file:
            return 3
        case .module:
            return 4
        case .assignment:
            return 5
        }
    }

    private func sameAssignmentGroup(resource: MissionResource, assignment: CourseBrainAssignmentSummary) -> Bool {
        if let groupId = assignment.assignmentGroupId,
           resource.assignmentGroupId == groupId {
            return true
        }

        let assignmentGroupName = normalized(assignment.assignmentGroupName)
        return !assignmentGroupName.isEmpty && normalized(resource.assignmentGroupName) == assignmentGroupName
    }

    private func normalized(_ raw: String?) -> String {
        raw?
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func dateDistance(resource: MissionResource, anchorDate: Date) -> TimeInterval {
        guard let resourceDate = resource.dueAt ?? resource.unlockAt ?? resource.lockAt ?? resource.updatedAt ?? resource.scannedAt else {
            return .greatestFiniteMagnitude
        }
        return abs(resourceDate.timeIntervalSince(anchorDate))
    }

    private func isVisible(anchorDate: Date, now: Date) -> Bool {
        let start = now.addingTimeInterval(-pastWindowDays)
        let end = now.addingTimeInterval(futureWindowDays)
        return anchorDate >= start && anchorDate <= end
    }

    private func sortAssignments(lhs: CourseBrainAssignmentSummary, rhs: CourseBrainAssignmentSummary) -> Bool {
        if lhs.anchorDate == rhs.anchorDate {
            let lhsSubmissionRank = lhs.headlineSubmissionStatus?.attentionSortRank ?? CourseBrainSubmissionStatus.unknown.attentionSortRank
            let rhsSubmissionRank = rhs.headlineSubmissionStatus?.attentionSortRank ?? CourseBrainSubmissionStatus.unknown.attentionSortRank
            if lhsSubmissionRank != rhsSubmissionRank {
                return lhsSubmissionRank < rhsSubmissionRank
            }

            if lhs.courseName == rhs.courseName {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.courseName.localizedCaseInsensitiveCompare(rhs.courseName) == .orderedAscending
        }
        return lhs.anchorDate < rhs.anchorDate
    }

    private func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            guard let value else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}

@MainActor
final class CourseBrainViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var sections: [CourseBrainAssignmentSection] = []
    @Published private(set) var courseFilters: [CourseBrainCourseFilter] = []
    @Published private(set) var selectedAssignmentDetail: CourseBrainAssignmentDetail?
    @Published private(set) var overallLastSyncedAt: Date?
    @Published var searchText = ""
    @Published var selectedCourseID: Int?
    @Published var bannerMessage: String?

    private let repository = CourseBrainRepository()
    private let builder = CourseBrainDashboardBuilder()
    private let resetDefaultsKey = "course_brain_v2_reset_completed"

    private var localDocuments: [LocalDocument] = []
    private var courseTwins: [CourseTwin] = []
    private var syncedNoteNodes: [CourseBrainNode] = []
    private var allAssignments: [CourseBrainAssignmentSummary] = []
    private var detailsByAssignmentID: [String: CourseBrainAssignmentDetail] = [:]
    private var selectedAssignmentID: String?
    private var searchCancellable: AnyCancellable?
    private var rebuildTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?

    init() {
        searchCancellable = $searchText
            .removeDuplicates()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyFilters()
            }
    }

    deinit {
        rebuildTask?.cancel()
        bannerTask?.cancel()
    }

    func load(documents: [LocalDocument]) {
        localDocuments = documents
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            guard let self else { return }
            await fetchAndBuild()
        }
    }

    func updateLocalDocuments(_ documents: [LocalDocument]) {
        localDocuments = documents
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            guard let self else { return }
            self.rebuildDashboard()
        }
    }

    func selectAssignment(_ assignmentID: String?) {
        selectedAssignmentID = assignmentID
        syncSelection()
    }

    func setCourseFilter(_ courseID: Int?) {
        guard selectedCourseID != courseID else { return }
        selectedCourseID = courseID
        applyFilters()
    }

    func headerLastSyncedAt() -> Date? {
        selectedAssignmentDetail?.lastSyncedAt ?? overallLastSyncedAt
    }

    private func fetchAndBuild() async {
        isLoading = true
        await purgeDerivedStateIfNeeded()

        do {
            let snapshot = try await repository.fetchSnapshot()
            courseTwins = snapshot.courseTwins
            syncedNoteNodes = snapshot.syncedNoteNodes
            rebuildDashboard()
            isLoading = false
        } catch {
            isLoading = false
            showBanner("Course Brain load failed: \(error.localizedDescription)")
        }
    }

    private func purgeDerivedStateIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: resetDefaultsKey) else { return }

        do {
            try await repository.purgeDerivedState()
            UserDefaults.standard.set(true, forKey: resetDefaultsKey)
        } catch {
            showBanner("Course Brain reset failed. Showing fresh UI without purging old state.")
        }
    }

    private func rebuildDashboard() {
        let data = builder.build(
            courseTwins: courseTwins,
            documents: localDocuments,
            noteNodes: syncedNoteNodes
        )

        allAssignments = data.assignments
        detailsByAssignmentID = data.detailsByAssignmentID
        courseFilters = data.courseFilters
        overallLastSyncedAt = data.overallLastSyncedAt

        if let selectedCourseID,
           !courseFilters.contains(where: { $0.id == selectedCourseID }) {
            self.selectedCourseID = nil
        }

        applyFilters()
    }

    private func applyFilters() {
        let normalizedQuery = normalizeSearch(searchText)
        let filteredAssignments = allAssignments.filter { assignment in
            if let selectedCourseID, assignment.courseId != selectedCourseID {
                return false
            }

            guard !normalizedQuery.isEmpty else { return true }
            return normalizeSearch(assignment.searchableText).contains(normalizedQuery)
        }

        sections = builder.buildSections(assignments: filteredAssignments)

        let visibleIDs = Set(filteredAssignments.map(\.id))
        if selectedAssignmentID == nil || !visibleIDs.contains(selectedAssignmentID ?? "") {
            selectedAssignmentID = filteredAssignments.first?.id
        }

        syncSelection()
    }

    private func syncSelection() {
        guard let selectedAssignmentID else {
            selectedAssignmentDetail = nil
            return
        }
        selectedAssignmentDetail = detailsByAssignmentID[selectedAssignmentID]
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
