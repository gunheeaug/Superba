import Foundation
import Combine
import Supabase

@MainActor
final class AuthViewModel: ObservableObject {
    enum Step {
        case enterPhone
        case enterCode
    }

    @Published var phoneNumber: String = ""
    @Published var otpCode: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var step: Step = .enterPhone
    @Published var isAuthenticated: Bool = false {
        didSet {
            UserDefaults.standard.set(isAuthenticated, forKey: "isAuthenticated")
        }
    }

    private var client: SupabaseClient { SupabaseManager.shared.client }

    init() {
        // Restore persisted auth state so we don't drop back to phone auth on resume/relaunch
        self.isAuthenticated = UserDefaults.standard.bool(forKey: "isAuthenticated")
    }

    func sendOTP() async {
        errorMessage = nil
        let trimmed = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter your phone number."
            return
        }
        isLoading = true
        do {
            try await client.auth.signInWithOTP(phone: trimmed, shouldCreateUser: true)
            step = .enterCode
        } catch {
            errorMessage = "Error sending a code.\nPlease check your phone number or try again later."
        }
        isLoading = false
    }

    func verifyOTP() async {
        errorMessage = nil
        let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = otpCode.filter({ $0.isNumber })
        guard !trimmedPhone.isEmpty, !trimmedCode.isEmpty else {
            errorMessage = "Enter the verification code."
            return
        }
        isLoading = true
        do {
            try await client.auth.verifyOTP(phone: trimmedPhone, token: trimmedCode, type: .sms)
            otpCode = ""
            isAuthenticated = true
            UserDefaults.standard.set(trimmedPhone, forKey: "lastPhone")
            UserDefaults.standard.set(true, forKey: "isAuthenticated")
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func reset() {
        errorMessage = nil
        otpCode = ""
        step = .enterPhone
    }

    func signOut() async {
        errorMessage = nil
        isLoading = true
        do {
            try await client.auth.signOut()
            isAuthenticated = false
            UserDefaults.standard.set(false, forKey: "isAuthenticated")
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}


