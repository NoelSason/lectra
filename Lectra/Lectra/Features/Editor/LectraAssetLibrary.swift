import Foundation

nonisolated enum LectraReusableAssetKind: String, Codable, CaseIterable, Sendable {
    case stamp
    case signature
    case savedInkObjectGroup
    case pageTemplate
}

nonisolated struct LectraReusableAsset: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var kind: LectraReusableAssetKind
    var title: String
    var annotations: [LectraAnnotationObject]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        kind: LectraReusableAssetKind,
        title: String,
        annotations: [LectraAnnotationObject] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.annotations = annotations
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct LectraAssetLibrary: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var assets: [LectraReusableAsset]

    init(version: Int = LectraAssetLibrary.currentVersion, assets: [LectraReusableAsset] = []) {
        self.version = version
        self.assets = assets
    }

    mutating func upsert(_ asset: LectraReusableAsset) {
        if let index = assets.firstIndex(where: { $0.id == asset.id }) {
            assets[index] = asset
        } else {
            assets.append(asset)
        }
    }

    mutating func remove(id: UUID) {
        assets.removeAll { $0.id == id }
    }
}
