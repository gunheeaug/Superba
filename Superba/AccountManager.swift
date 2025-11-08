import Foundation
import SwiftUI
import Combine
import Supabase

@MainActor
final class AccountManager: ObservableObject {
    // Profile/media
    @Published var profileGIFURL: URL? = nil
    @Published var pendingSelfieGIFToAdd: URL? = nil
    @Published var runProfileURL: URL? = nil
    @Published var phoneNumber: String? = nil

    // Live activity resume flags
    @Published var liveActivityResumeElapsed: Int? = nil
    @Published var liveActivityResumeDistance: Double? = nil
    @Published var liveActivityResumeIsPaused: Bool? = nil
    @Published var presentRunViewDirect: Bool = false

    // AR composition payloads
    @Published var pendingAugboardGIFURLs: [URL] = []
    @Published var pendingAugboardGIFPercents: [CGPoint] = []
    @Published var pendingAugboardGIFMyAugMetas: [String?] = []
    @Published var pendingAugboardImageFileURLs: [URL] = []
    @Published var pendingAugboardImagePercents: [CGPoint] = []
    @Published var pendingAugboardText: String? = nil
    @Published var pendingAugboardTextPercent: CGPoint? = nil
    @Published var pendingAugboardOpenKeyboard: Bool = false
    @Published var pendingAugboardFontIndex: Int = 0
    @Published var presentCameraDirect: Bool = false

    private var client: SupabaseClient { SupabaseManager.shared.client }

    init() {
        // Try to load profile at app launch
        Task { await loadProfileFromSupabase() }
    }

    struct ProfileRow: Decodable {
        let id: UUID?
        let phone: String?
        let profile_clip_url: String?
        let run_profile_url: String?
    }

    func loadProfileFromSupabase() async {
        // If we have a stored phone from auth, use it
        let phone = UserDefaults.standard.string(forKey: "lastPhone")
        do {
            let response: [ProfileRow]
            if let phone = phone, !phone.isEmpty {
                response = try await client.database
                    .from("profiles")
                    .select()
                    .eq("phone", value: phone)
                    .limit(1)
                    .execute()
                    .value
            } else {
                response = try await client.database
                    .from("profiles")
                    .select()
                    .limit(1)
                    .execute()
                    .value
            }
            if let row = response.first {
                self.phoneNumber = row.phone ?? phone
                if let gif = row.profile_clip_url, let url = URL(string: gif) {
                    self.profileGIFURL = url
                }
                if let runProfile = row.run_profile_url, let url = URL(string: runProfile) {
                    self.runProfileURL = url
                }
            } else {
                self.phoneNumber = phone
            }
        } catch {
            // Non-fatal; keep defaults
            self.phoneNumber = phone
        }
    }
}


