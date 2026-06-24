//
//  PackageCache.swift
//  Lectra
//
//  Offline cache of Python wheels installed at runtime via micropip. The kernel
//  ships a fixed wheel set; when a notebook installs something extra from PyPI,
//  micropip resolves the dependency closure and reports each wheel's URL. We
//  mirror those wheels to disk here so later sessions re-install instantly and
//  fully offline (see PyodideRuntime's boot-time re-install).
//
//  Wheels live under Documents/pypackages/<file>.whl with a small JSON manifest
//  tracking which top-level packages the user explicitly asked for.
//

import Foundation

/// One wheel resolved by micropip: its filename and the URL it came from.
struct WheelRef: Equatable {
    let fileName: String
    let url: URL
}

actor PackageCache {
    static let shared = PackageCache()

    private let fileManager = FileManager.default

    /// Top-level package names the user explicitly installed (not their deps),
    /// for display in the Packages panel.
    private(set) var installedNames: Set<String> = []

    /// Wheel cache directory, created on demand. `nonisolated` so the initializer
    /// can resolve paths before actor isolation is established.
    private nonisolated static func directoryURL() -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("pypackages", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private nonisolated static func manifestFileURL() -> URL {
        directoryURL().appendingPathComponent("manifest.json")
    }

    private var directory: URL { Self.directoryURL() }
    private var manifestURL: URL { Self.manifestFileURL() }

    init() {
        if let data = try? Data(contentsOf: Self.manifestFileURL()),
           let names = try? JSONDecoder().decode([String].self, from: data) {
            installedNames = Set(names)
        }
    }

    // MARK: Query

    /// Local paths of every cached wheel, for offline re-install at kernel boot.
    func cachedWheelPaths() -> [URL] {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "whl" }
    }

    func isEmpty() -> Bool { cachedWheelPaths().isEmpty }

    func names() -> [String] { installedNames.sorted() }

    // MARK: Mutation

    /// Downloads the given wheels into the cache (skipping ones already present)
    /// and records `topLevel` as an explicitly-installed package. Returns the
    /// number of new wheels written. Network errors are tolerated per-wheel.
    @discardableResult
    func store(topLevel: String, wheels: [WheelRef]) async -> Int {
        var added = 0
        for wheel in wheels {
            let dest = directory.appendingPathComponent(wheel.fileName)
            if fileManager.fileExists(atPath: dest.path) { continue }
            do {
                let (tmp, _) = try await URLSession.shared.download(from: wheel.url)
                try? fileManager.removeItem(at: dest)
                try fileManager.moveItem(at: tmp, to: dest)
                added += 1
            } catch {
                // Best-effort: a missing mirror just means this package won't be
                // available offline next launch; it still installed this session.
                continue
            }
        }
        installedNames.insert(topLevel)
        persistManifest()
        return added
    }

    /// Removes an explicitly-installed package from the manifest. Wheels are left
    /// on disk (deps may be shared); they simply stop auto-installing if no name
    /// references them — kept simple for v1.
    func remove(name: String) {
        installedNames.remove(name)
        persistManifest()
    }

    private func persistManifest() {
        let data = try? JSONEncoder().encode(installedNames.sorted())
        try? data?.write(to: manifestURL, options: .atomic)
    }
}
