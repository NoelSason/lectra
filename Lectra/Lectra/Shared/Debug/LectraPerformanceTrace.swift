import Foundation
import QuartzCore
import UIKit

#if DEBUG
import os
#endif

enum PerformanceSurface: String {
    case unknown
    case annotation
    case save
    case projects
    case terminal
    case sync
    case web
}

@MainActor
private enum LectraPerformanceSurfaceTracker {
    static var activeSurface: PerformanceSurface = .unknown
}

enum LectraPerformanceTrace {
    enum Category {
        case annotation
        case save
        case projects
        case terminal
        case sync
        case web
    }

    struct SignpostToken {
        #if DEBUG
        fileprivate let category: Category
        fileprivate let name: StaticString
        fileprivate let id: OSSignpostID
        #endif
    }

    @MainActor
    static func setActiveSurface(_ surface: PerformanceSurface) {
        #if DEBUG
        LectraPerformanceSurfaceTracker.activeSurface = surface
        #endif
    }

    @MainActor
    static var activeSurface: PerformanceSurface {
        #if DEBUG
        LectraPerformanceSurfaceTracker.activeSurface
        #else
        .unknown
        #endif
    }

    nonisolated static func begin(_ category: Category, _ name: StaticString) -> SignpostToken {
        #if DEBUG
        let log = log(for: category)
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return SignpostToken(category: category, name: name, id: id)
        #else
        return SignpostToken()
        #endif
    }

    nonisolated static func end(_ token: SignpostToken) {
        #if DEBUG
        os_signpost(.end, log: log(for: token.category), name: token.name, signpostID: token.id)
        #endif
    }

    nonisolated static func event(_ category: Category, _ name: StaticString) {
        #if DEBUG
        os_signpost(.event, log: log(for: category), name: name)
        #endif
    }

    static func withSignpost<T>(
        _ category: Category,
        _ name: StaticString,
        isolation: isolated (any Actor)? = #isolation,
        _ operation: () throws -> T
    ) rethrows -> T {
        #if DEBUG
        let token = begin(category, name)
        defer { end(token) }
        #endif
        return try operation()
    }

    static func withAsyncSignpost<T>(
        _ category: Category,
        _ name: StaticString,
        isolation: isolated (any Actor)? = #isolation,
        _ operation: () async throws -> T
    ) async rethrows -> T {
        #if DEBUG
        let token = begin(category, name)
        defer { end(token) }
        #endif
        return try await operation()
    }

    #if DEBUG
    nonisolated private static let subsystem = Bundle.main.bundleIdentifier ?? "com.canvascope.Lectra"

    nonisolated private static let annotationLog = OSLog(subsystem: subsystem, category: "annotation")
    nonisolated private static let saveLog = OSLog(subsystem: subsystem, category: "save")
    nonisolated private static let projectsLog = OSLog(subsystem: subsystem, category: "projects")
    nonisolated private static let terminalLog = OSLog(subsystem: subsystem, category: "terminal")
    nonisolated private static let syncLog = OSLog(subsystem: subsystem, category: "sync")
    nonisolated private static let webLog = OSLog(subsystem: subsystem, category: "web")

    nonisolated private static func log(for category: Category) -> OSLog {
        switch category {
        case .annotation:
            return annotationLog
        case .save:
            return saveLog
        case .projects:
            return projectsLog
        case .terminal:
            return terminalLog
        case .sync:
            return syncLog
        case .web:
            return webLog
        }
    }
    #endif
}

@MainActor
final class MainThreadHitchMonitor {
    static let shared = MainThreadHitchMonitor()

    private var displayLink: CADisplayLink?
    private var previousTimestamp: CFTimeInterval?

    private init() {}

    func start() {
        #if DEBUG
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(displayLinkDidTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        #endif
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        previousTimestamp = nil
    }

    @objc
    private func displayLinkDidTick(_ link: CADisplayLink) {
        #if DEBUG
        defer { previousTimestamp = link.timestamp }
        guard let previousTimestamp else { return }

        let delta = link.timestamp - previousTimestamp
        guard delta >= 0.05 else { return }

        let severity = delta >= 0.10 ? "100ms" : "50ms"
        LectraPerformanceTrace.event(.annotation, "MainThreadHitch")
        LectraDebugLog(
            "[Performance] Main thread hitch over \(severity): \(String(format: "%.1f", delta * 1000)) ms on \(LectraPerformanceTrace.activeSurface.rawValue)"
        )
        #endif
    }
}
