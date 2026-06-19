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

    /// Which tier *would* serve an input of this size. Drives UI hints and,
    /// once PCC ships, actual routing.
    func preferredTier(forApproxTokens tokens: Int) -> Tier {
        tokens > onDeviceTokenBudget ? .privateCloudCompute : .onDevice
    }

    // MARK: Session construction

    /// Builds a session for the given instructions. Long inputs are flagged for
    /// PCC but currently fall back to on-device (see seam).
    func makeSession(instructions: String, approxTokens: Int = 0) -> LanguageModelSession {
        // ── PCC SEAM ──────────────────────────────────────────────────────
        // if #available(iOS 27.0, *),
        //    preferredTier(forApproxTokens: approxTokens) == .privateCloudCompute,
        //    case .available = PrivateCloudComputeLanguageModel().availability {
        //     return LanguageModelSession(model: PrivateCloudComputeLanguageModel(),
        //                                 instructions: instructions)
        // }
        // ──────────────────────────────────────────────────────────────────
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
