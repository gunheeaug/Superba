import Foundation
import Supabase

final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        let supabaseURL = URL(string: "https://tqugnlmtkvmdzwqskgva.supabase.co")!
        let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRxdWdubG10a3ZtZHp3cXNrZ3ZhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjIxNDYwNzgsImV4cCI6MjA3NzcyMjA3OH0.ObAL7EHHu36vbsjmTV7UexwzuIor6DsQdaRRFNc-EbM"
        self.client = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: supabaseAnonKey)
    }
}


