//
//  IntelligenceAvailability.swift
//  Lectra
//
//  Single source of truth for whether Lectra's on-device intelligence
//  (Apple Foundation Models) can run on this device right now. Every AI
//  entry point in the UI checks this first and degrades gracefully on
//  iOS 17–25 devices or when Apple Intelligence is turned off.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Why intelligence is (or isn't) available, in product terms.
enum LectraIntelligenceStatus: Equatable {
    /// On-device model is loaded and ready.
    case ready
    /// OS is older than iOS 26 — Foundation Models doesn't exist here.
    case unsupportedOS
    /// Device supports Apple Intelligence but the user hasn't enabled it.
    case appleIntelligenceOff
    /// Hardware can't run Apple Intelligence.
    case deviceNotEligible
    /// Model is still downloading / warming up.
    case modelNotReady
    /// Unavailable for an unknown reason.
    case unknownUnavailable

    var isReady: Bool { self == .ready }

    /// Short title for the empty/disabled state.
    var headline: String {
        switch self {
        case .ready:               return "Intelligence ready"
        case .unsupportedOS:       return "Requires iOS 26"
        case .appleIntelligenceOff: return "Turn on Apple Intelligence"
        case .deviceNotEligible:   return "Not available on this iPad"
        case .modelNotReady:       return "Getting intelligence ready…"
        case .unknownUnavailable:  return "Intelligence unavailable"
        }
    }

    /// One-line explanation shown beneath the headline.
    var message: String {
        switch self {
        case .ready:
            return "Summaries, flashcards, and answers run privately on your iPad."
        case .unsupportedOS:
            return "Update to iOS 26 or later to use Lectra's on-device study tools."
        case .appleIntelligenceOff:
            return "Enable Apple Intelligence in Settings to summarize and study your documents."
        case .deviceNotEligible:
            return "This iPad's chip doesn't support Apple Intelligence features."
        case .modelNotReady:
            return "The on-device model is still preparing. Try again in a moment."
        case .unknownUnavailable:
            return "On-device intelligence can't run right now. Try again later."
        }
    }

    var systemImage: String {
        switch self {
        case .ready:               return "sparkles"
        case .modelNotReady:       return "hourglass"
        case .appleIntelligenceOff: return "switch.2"
        default:                   return "sparkles.slash"
        }
    }
}

/// Namespace for resolving intelligence availability at runtime.
enum LectraIntelligence {
    /// Live availability, recomputed each access (cheap; the framework caches).
    static var status: LectraIntelligenceStatus {
        guard #available(iOS 26.0, *) else { return .unsupportedOS }
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceOff
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .unknownUnavailable
        @unknown default:
            return .unknownUnavailable
        }
        #else
        return .unsupportedOS
        #endif
    }

    static var isReady: Bool { status.isReady }

    /// Whether the Private Cloud Compute tier (iOS 27+) can serve a request
    /// right now. Long documents route here for a larger context window while
    /// keeping the same privacy guarantees. `false` on iOS 26, in the
    /// Simulator (FB177684296), or without the managed PCC entitlement.
    static var pccAvailable: Bool {
        guard #available(iOS 27.0, *) else { return false }
        #if canImport(FoundationModels)
        if case .available = PrivateCloudComputeLanguageModel().availability {
            return true
        }
        return false
        #else
        return false
        #endif
    }
}
