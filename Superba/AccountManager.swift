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
    @Published var firstName: String? = nil
    @Published var lastName: String? = nil
    @Published var userId: UUID? = nil

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
        let profile_clip_path: String?
        let run_profile_url: String?
        let first_name: String?
        let last_name: String?
    }

    func loadProfileFromSupabase() async {
        // Prefer fetching by current authed user id (works best with RLS)
        let phone = UserDefaults.standard.string(forKey: "lastPhone")
        do {
            let response: [ProfileRow]
            if let session = try? await client.auth.session {
                let uid = session.user.id.uuidString
                response = try await client.database
                    .from("profiles")
                    .select()
                    .eq("id", value: uid)
                    .limit(1)
                    .execute()
                    .value
            } else if let phone = phone, !phone.isEmpty {
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
                self.userId = row.id
                self.phoneNumber = row.phone ?? phone
                self.firstName = row.first_name
                self.lastName = row.last_name
                if let path = row.profile_clip_path, !path.isEmpty {
                    do {
                        let url = try client.storage.from("profile-clips").getPublicURL(path: path)
                        self.profileGIFURL = url
                    } catch {
                        // ignore URL resolution failure
                    }
                }
                if let runProfile = row.run_profile_url, let url = URL(string: runProfile) {
                    self.runProfileURL = url
                }
            } else {
                self.phoneNumber = phone
                self.firstName = self.firstName
                self.lastName = self.lastName
            }
        } catch {
            // Non-fatal; keep defaults
            self.phoneNumber = phone
            // keep existing names if any
        }
    }
    
    // Upload a local GIF file to Supabase Storage and save path into profiles.profile_clip_path
    func uploadProfileGIFToSupabase(gifURL: URL) async -> URL? {
        do {
            let data = try Data(contentsOf: gifURL)
            // Resolve user id: prefer loaded profile id, else from current auth session
            let userId: UUID
            if let existing = self.userId {
                userId = existing
            } else if let session = try? await client.auth.session {
                userId = session.user.id
            } else {
                return nil
            }
            let path = "\(userId.uuidString)/profile_\(Int(Date().timeIntervalSince1970)).gif"
            // Upload (upsert to overwrite if name collides)
            _ = try await client.storage
                .from("profile-clips")
                .upload(path: path, file: data)
            // Persist path on profile
            _ = try await client.database
                .from("profiles")
                .update(["profile_clip_path": path])
                .eq("id", value: userId.uuidString)
                .execute()
            // Best-effort fallback: update by phone if id-based update did not apply
            if let phone = self.phoneNumber, !phone.isEmpty {
                _ = try? await client.database
                    .from("profiles")
                    .update(["profile_clip_path": path])
                    .eq("phone", value: phone)
                    .execute()
            }
            // Resolve public URL for immediate display
            do {
                let publicURL = try client.storage.from("profile-clips").getPublicURL(path: path)
                await MainActor.run { self.profileGIFURL = publicURL }
                return publicURL
            } catch {
                return nil
            }
        } catch {
            return nil
        }
    }
}


