//
//  LectraAIRateLimiter.swift
//  Lectra
//
//  Lightweight local throttling for Foundation Models usage. The model runs on
//  device today, but unchecked repeated requests still burn battery, memory, and
//  UI responsiveness.
//

import Foundation

struct LectraAIRateLimitError: LocalizedError, Equatable {
    let retryAfter: TimeInterval

    var errorDescription: String? {
        "Intelligence is cooling down. Try again in \(Self.formattedDuration(retryAfter))."
    }

    private static func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = max(1, Int(ceil(duration)))
        if seconds < 60 {
            return seconds == 1 ? "1 second" : "\(seconds) seconds"
        }

        let minutes = Int(ceil(Double(seconds) / 60.0))
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}

actor LectraAIRateLimiter {
    struct Policy {
        let burstLimit: Int
        let burstWindow: TimeInterval
        let rollingLimit: Int
        let rollingWindow: TimeInterval

        static let standard = Policy(
            burstLimit: 4,
            burstWindow: 20,
            rollingLimit: 20,
            rollingWindow: 10 * 60
        )
    }

    static let shared = LectraAIRateLimiter()

    private let policy: Policy
    private var requestTimes: [TimeInterval] = []

    init(policy: Policy = .standard) {
        self.policy = policy
    }

    func acquire(at now: Date = Date()) throws {
        let current = now.timeIntervalSinceReferenceDate
        requestTimes.removeAll { current - $0 >= policy.rollingWindow }

        if let retryAfter = retryAfter(from: current) {
            throw LectraAIRateLimitError(retryAfter: retryAfter)
        }

        requestTimes.append(current)
    }

    func reset() {
        requestTimes.removeAll()
    }

    private func retryAfter(from current: TimeInterval) -> TimeInterval? {
        var delays: [TimeInterval] = []

        let burstTimes = requestTimes.filter { current - $0 < policy.burstWindow }
        if burstTimes.count >= policy.burstLimit, let oldest = burstTimes.min() {
            delays.append(policy.burstWindow - (current - oldest))
        }

        if requestTimes.count >= policy.rollingLimit, let oldest = requestTimes.min() {
            delays.append(policy.rollingWindow - (current - oldest))
        }

        guard let delay = delays.max() else { return nil }
        return max(1, ceil(delay))
    }
}
