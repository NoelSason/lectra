//
//  SupabaseManager.swift
//  Lectra
//
//  Singleton that holds the Supabase client instance.
//  Every other file that needs Supabase access uses SupabaseManager.shared.client
//

import Foundation
import Supabase

/// Central access point for the shared Supabase client.
final class SupabaseManager {

    // MARK: - Singleton
    static let shared = SupabaseManager()

    // MARK: - Client
    let client: SupabaseClient
    let supabaseURL: URL
    let supabaseKey: String

    // MARK: - Init (private – use .shared)
    private init() {
        let bundle = Bundle.main
        let configuredURL = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        let configuredAnonKey = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String

        let fallbackURL = "https://vcadcdgnwxjlgaoqktkd.supabase.co"
        let fallbackAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZjYWRjZGdud3hqbGdhb3FrdGtkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE2MzU4NDQsImV4cCI6MjA4NzIxMTg0NH0.71j6kwkwwSeG9Jppu4IUyHORM033NFyXKemOd5kuDWk"

        supabaseURL = URL(string: configuredURL ?? fallbackURL)!
        supabaseKey = configuredAnonKey ?? fallbackAnonKey

        client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: supabaseKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }
}
