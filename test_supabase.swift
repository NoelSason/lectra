import Foundation
import Supabase

let options = SupabaseClientOptions(
    auth: AuthClientOptions(
        emitLocalSessionAsInitialSession: true
    )
)
