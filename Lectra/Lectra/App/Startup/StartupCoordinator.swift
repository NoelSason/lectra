//
//  StartupCoordinator.swift
//  Lectra
//
//  Coordinates startup animation timing so the splash exits only after
//  both minimum display time and startup data readiness are satisfied.
//

import SwiftUI
import Combine

@MainActor
final class StartupCoordinator: ObservableObject {
    enum Stage: Equatable {
        case intro
        case mark
        case pulse
        case wordmark
        case waiting
    }

    @Published private(set) var stage: Stage = .intro
    @Published private(set) var isCompleted = false

    private var hasStarted = false
    private var minimumDurationElapsed = false
    private var dataReady = false
    private var timelineTask: Task<Void, Never>?

    deinit {
        timelineTask?.cancel()
    }

    func start(dataReady: Bool) {
        self.dataReady = dataReady

        guard !hasStarted else {
            evaluateCompletion()
            return
        }

        hasStarted = true
        timelineTask = Task { [weak self] in
            await self?.runTimeline()
        }
    }

    func updateDataReady(_ ready: Bool) {
        dataReady = ready
        evaluateCompletion()
    }

    func completeImmediately() {
        timelineTask?.cancel()
        hasStarted = true
        minimumDurationElapsed = true
        dataReady = true
        isCompleted = true
    }

    private func runTimeline() async {
        stage = .intro

        try? await Task.sleep(for: .milliseconds(16))
        guard !Task.isCancelled else { return }
        stage = .mark

        try? await Task.sleep(for: .milliseconds(80))
        guard !Task.isCancelled else { return }
        stage = .pulse

        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
        stage = .wordmark

        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }

        minimumDurationElapsed = true
        evaluateCompletion()

        if !isCompleted {
            stage = .waiting
        }
    }

    private func evaluateCompletion() {
        guard !isCompleted else { return }
        guard minimumDurationElapsed, dataReady else { return }
        isCompleted = true
    }
}
