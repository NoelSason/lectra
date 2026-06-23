//
//  LectraModelRouter.swift
//  Lectra
//
//  Central decision point for which Apple Foundation Model serves a request.
//
//  Today (Xcode 26 / iOS 26 SDK) only the on-device `SystemLanguageModel`
//  ships, so every request runs privately on-device. The router is written
//  so the Private Cloud Compute (PCC) tier — `PrivateCloudComputeLanguageModel`,
//  iOS 27, larger 32K context + reasoning levels — drops in at the marked
//  seam below once the Xcode 27 SDK and the managed
//  `com.apple.developer.private-cloud-compute` entitlement are available,
//  WITHOUT touching any of the feature services.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@available(iOS 26.0, *)
@MainActor
final class LectraModelRouter {
    static let shared = LectraModelRouter()

    enum Tier: Equatable {
        case onDevice
        /// Reserved for `PrivateCloudComputeLanguageModel` (iOS 27+).
        case privateCloudCompute
    }

    /// Rough char→token heuristic (~4 chars/token) for tier selection.
    static func estimatedTokens(forChars chars: Int) -> Int { max(1, chars / 4) }

    /// On-device model's usable prompt budget in tokens (≈4K window, leaving
    /// headroom for instructions + the response).
    private let onDeviceTokenBudget = 3_000

    /// Which tier *would* serve an input of this size. Drives UI hints and
    /// actual routing. Inputs that overflow the on-device window prefer PCC;
    /// whether PCC is actually used still depends on its runtime availability.
    func preferredTier(forApproxTokens tokens: Int) -> Tier {
        tokens > onDeviceTokenBudget ? .privateCloudCompute : .onDevice
    }

    /// The character budget a caller should clamp document text to, based on
    /// the best tier available right now. PCC (iOS 27+) handles a far larger
    /// window than the on-device model, so long documents keep their tail.
    func documentCharBudget() -> Int {
        if #available(iOS 27.0, *), LectraIntelligence.pccAvailable {
            return PDFTextExtractor.pccCharBudget
        }
        return PDFTextExtractor.onDeviceCharBudget
    }

    /// How a document of a given length will actually be handled, so the UI can
    /// be honest with the user instead of silently truncating long material.
    enum ContextHandling: Equatable {
        /// Fits comfortably in the on-device window — handled in full, privately.
        case standard
        /// Long, and handled in full via the larger Private Cloud Compute window.
        case extended
        /// Long, but no extended window is available, so only the first portion
        /// is used. The UI should say so.
        case truncated
    }

    /// Classifies how text of `chars` characters will be handled right now.
    func contextHandling(forChars chars: Int) -> ContextHandling {
        guard chars > PDFTextExtractor.onDeviceCharBudget else { return .standard }
        if #available(iOS 27.0, *), LectraIntelligence.pccAvailable {
            return .extended
        }
        return .truncated
    }

    // MARK: Session construction

    /// Builds a session for the given instructions. Inputs that overflow the
    /// on-device window are routed to Private Cloud Compute when it's available
    /// (iOS 27+), and otherwise fall back to the on-device model.
    func makeSession(instructions: String, approxTokens: Int = 0) -> LanguageModelSession {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *),
           preferredTier(forApproxTokens: approxTokens) == .privateCloudCompute {
            // Construct once: PCC won't run in the Simulator (FB177684296) and
            // is gated on the managed private-cloud-compute entitlement, so we
            // confirm availability before binding the session to it.
            let pcc = PrivateCloudComputeLanguageModel()
            if case .available = pcc.availability {
                return LanguageModelSession(model: pcc, instructions: instructions)
            }
        }
        #endif
        return LanguageModelSession(model: .default, instructions: instructions)
    }

    // MARK: One-shot helpers

    /// Single-turn text response with graceful clamping to the active budget.
    func generateText(
        prompt: String,
        instructions: String,
        maxResponseTokens: Int? = nil
    ) async throws -> String {
        let tokens = Self.estimatedTokens(forChars: prompt.count)
        let session = makeSession(instructions: instructions, approxTokens: tokens)
        let options = GenerationOptions(maximumResponseTokens: maxResponseTokens)
        let response = try await session.respond(to: prompt, options: options)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Single-turn structured response using guided generation.
    func generate<Content: Generable>(
        _ type: Content.Type,
        prompt: String,
        instructions: String,
        maxResponseTokens: Int? = nil
    ) async throws -> Content {
        let tokens = Self.estimatedTokens(forChars: prompt.count)
        let session = makeSession(instructions: instructions, approxTokens: tokens)
        let options = GenerationOptions(maximumResponseTokens: maxResponseTokens)
        let response = try await session.respond(to: prompt, generating: type, options: options)
        return response.content
    }
}
