import SwiftUI
import Combine
import Contacts
import CoreLocation
import Supabase
import UIKit
import MessageUI

private struct BottomInsetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

enum OnboardingStep: String, Hashable {
    case name
    case selfie
    case contacts
    case location
}

final class ContactsFetcher: NSObject, ObservableObject {
    @Published var authorization: CNAuthorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    @Published var contacts: [CNContact] = []

    private let store = CNContactStore()

    func requestAccess() {
        store.requestAccess(for: .contacts) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.authorization = CNContactStore.authorizationStatus(for: .contacts)
                if granted {
                    self?.loadContacts()
                }
            }
        }
    }

    func loadContacts() {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var fetched: [CNContact] = []
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                if !contact.phoneNumbers.isEmpty {
                    fetched.append(contact)
                }
            }
            DispatchQueue.main.async { self.contacts = fetched }
        } catch {
            // ignore for now
        }
    }
}

final class LocationRequester: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        authorization = manager.authorizationStatus
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var account: AccountManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("onboardingStep") private var onboardingStepStored: String = OnboardingStep.name.rawValue

    @State private var step: OnboardingStep = .name
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @FocusState private var firstFieldFocused: Bool
    @FocusState private var lastFieldFocused: Bool
    @FocusState private var searchFocused: Bool
    @State private var bottomInsetHeight: CGFloat = 0
    @State private var selfiePulse: Bool = false
    @State private var showSelfieCamera: Bool = false
    @State private var contactsSearch: String = ""
    @State private var selfieGIFURL: URL? = nil
    @State private var selfieGIFHeight: CGFloat = 120

    @StateObject private var contactsFetcher = ContactsFetcher()
    @State private var selectedContactIndices: Set<Int> = []
    @State private var requestedLocationPermission: Bool = false
    @State private var showMessagesSheet: Bool = false
    @State private var messageRecipients: [String] = []
    @State private var messageBody: String = ""
    @State private var pendingInviteIndex: Int?
    @State private var pendingInviteCode: String?
    @State private var messageDraft: MessageDraft?

    @StateObject private var locationRequester = LocationRequester()

    private var client: SupabaseClient { SupabaseManager.shared.client }

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
            switch step {
            case .name:
                nameStep
            case .selfie:
                selfieStep
            case .contacts:
                contactsStep
            case .location:
                locationStep
            }

            if let error = errorMessage, !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            }
            .animation(.easeInOut, value: step)
            .padding(24)
        }
        .onPreferenceChange(BottomInsetHeightKey.self) { value in
            bottomInsetHeight = value
        }
        .onChange(of: searchFocused) { isFocused in
            if isFocused {
                bottomInsetHeight = 0
            }
        }
        .onAppear {
            if let stored = OnboardingStep(rawValue: onboardingStepStored) {
                step = stored
            }
        }
        .onChange(of: step) { newValue in
            onboardingStepStored = newValue.rawValue
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if step == .name {
                let firstOK = !firstName.trimmingCharacters(in: .whitespaces).isEmpty
                let lastOK = !lastName.trimmingCharacters(in: .whitespaces).isEmpty
                VStack(spacing: 16) {
                    Button(action: { Task { await saveNameAndContinue() } }) {
                        Group {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.black)
                            } else {
                                Text("Continue")
                                    .font(.system(size: 20, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .padding(.vertical, 2)
                        .foregroundStyle((firstOK && lastOK) ? Color.black : Color.white)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(
                                    (firstOK && lastOK)
                                    ? AnyShapeStyle(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.78, green: 1.00, blue: 0.20),
                                                Color(red: 0.62, green: 0.90, blue: 0.00)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                      )
                                    : AnyShapeStyle(Color(.systemGray4))
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving || !(firstOK && lastOK))
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: BottomInsetHeightKey.self, value: proxy.size.height)
                    }
                )
            } else if step == .selfie {
                VStack(spacing: 16) {
                    Text("You can always change this later")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

                    HStack(spacing: 12) {
                        Button(action: { step = .contacts }) {
                            Text("Skip")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 58)
                                .foregroundStyle(Color.white)
                                .background(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .fill(Color(.systemGray4))
                                )
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            if selfieGIFURL != nil {
                                step = .contacts
                            } else {
                                showSelfieCamera = true
                            }
                        }) {
                            Text("Continue")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 58)
                                .foregroundStyle(Color.black)
                                .background(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .fill(
                                            AnyShapeStyle(
                                                LinearGradient(
                                                    colors: [
                                                        Color(red: 0.78, green: 1.00, blue: 0.20),
                                                        Color(red: 0.62, green: 0.90, blue: 0.00)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: BottomInsetHeightKey.self, value: proxy.size.height)
                    }
                )
            } else if step == .contacts {
                if !searchFocused {
                    VStack(spacing: 16) {
                        let status = contactsFetcher.authorization
                        if status == .authorized {
                            Button(action: { step = .location }) {
                                let hasInvited = !selectedContactIndices.isEmpty
                                Text(hasInvited ? "Continue" : "Skip for later")
                                    .font(.system(size: 20, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 58)
                                    .padding(.vertical, 2)
                                    .foregroundStyle(hasInvited ? Color.black : Color.white)
                                    .background(
                                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                                            .fill(
                                                hasInvited
                                                ? AnyShapeStyle(
                                                    LinearGradient(
                                                        colors: [
                                                            Color(red: 0.78, green: 1.00, blue: 0.20),
                                                            Color(red: 0.62, green: 0.90, blue: 0.00)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                  )
                                                : AnyShapeStyle(Color(.systemGray4))
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        } else if status != .notDetermined { // denied/restricted
                            Text("Contacts access denied.\nYou can enable contacts in Settings.")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                            HStack(spacing: 12) {
                                Button(action: { step = .location }) {
                                    Text("Skip")
                                        .font(.system(size: 20, weight: .semibold))
                                        .frame(maxWidth: .infinity, minHeight: 58)
                                        .foregroundStyle(Color.white)
                                        .background(
                                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                                .fill(Color(.systemGray4))
                                        )
                                }
                                .buttonStyle(.plain)
                                Button(action: {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    Text("Settings")
                                        .font(.system(size: 20, weight: .semibold))
                                        .frame(maxWidth: .infinity, minHeight: 58)
                                        .foregroundStyle(Color.black)
                                        .background(
                                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                                .fill(
                                                    AnyShapeStyle(
                                                        LinearGradient(
                                                            colors: [
                                                                Color(red: 0.78, green: 1.00, blue: 0.20),
                                                                Color(red: 0.62, green: 0.90, blue: 0.00)
                                                            ],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        )
                                                    )
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: BottomInsetHeightKey.self, value: proxy.size.height)
                        }
                    )
                    .ignoresSafeArea(.keyboard)
                }
            } else if step == .location {
                // No bottom action for location; request will fire automatically after delay
                EmptyView()
                    .background(
                        GeometryReader { _ in
                            Color.clear.preference(key: BottomInsetHeightKey.self, value: 0)
                        }
                    )
            }
        }
        .sheet(isPresented: $showSelfieCamera) {
            SelfieCameraSheet(isPresented: $showSelfieCamera) { videoURL in
                // Convert to GIF and show in place; do not auto-advance
                Task {
                    if let gif = await PhotoLibraryStickerService.shared.processSelfieVideoAsAnimatedSticker(videoURL: videoURL) {
                        await MainActor.run {
                            self.selfieGIFURL = gif
                            if let size = SelfieCameraSheet.getGIFPixelSize(from: gif), size.width > 0 {
                                self.selfieGIFHeight = 74 * (size.height / size.width)
                            } else {
                                self.selfieGIFHeight = 120
                            }
                        }
                        // Upload to Supabase Storage and save to profile
                        if let publicURL = await account.uploadProfileGIFToSupabase(gifURL: gif) {
                            await MainActor.run {
                                self.account.profileGIFURL = publicURL
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $messageDraft) { draft in
            MessageComposeView(recipients: draft.recipients, body: draft.body) { result in
                if result == .sent {
                    selectedContactIndices.insert(draft.index)
                    Task {
                        do {
                            _ = try await client.database
                                .rpc("invites_mark_sent", params: ["p_code": draft.code])
                                .execute()
                        } catch { /* optional */ }
                    }
                }
                messageDraft = nil
            }
        }
    }

    private var nameStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 24) {
                Text("What’s your name?")
                    .font(.system(size: 17, weight: .regular))
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
					TextField("", text: $firstName, prompt: Text("First").font(.system(size: 34, weight: .semibold)).foregroundStyle(firstFieldFocused ? Color(.tertiaryLabel) : Color(.secondaryLabel)))
						.textContentType(.givenName)
						.font(.system(size: 34, weight: .semibold))
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: true, vertical: false)
						.focused($firstFieldFocused)
						.submitLabel(.next)
						.onSubmit { lastFieldFocused = true }
						.onTapGesture { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
						.onChange(of: firstName) { newValue in
							if newValue.count > 12 {
								firstName = String(newValue.prefix(12))
								return
							}
							if newValue.contains(" ") {
								let parts = newValue.split(separator: " ", omittingEmptySubsequences: true)
								if let first = parts.first {
									firstName = String(first.prefix(12))
									let remainder = parts.dropFirst().joined(separator: " ")
									if lastName.isEmpty {
										lastName = String(remainder.prefix(12))
									}
									lastFieldFocused = true
								}
							}
						}
					TextField("", text: $lastName, prompt: Text("Last").font(.system(size: 34, weight: .semibold)).foregroundStyle(lastFieldFocused ? Color(.tertiaryLabel) : Color(.secondaryLabel)))
						.textContentType(.familyName)
						.font(.system(size: 34, weight: .semibold))
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: true, vertical: false)
						.focused($lastFieldFocused)
						.submitLabel(.done)
						.onTapGesture { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
						.onChange(of: lastName) { newValue in
							if newValue.count > 12 {
								lastName = String(newValue.prefix(12))
							}
						}
				}
                .frame(maxWidth: .infinity, alignment: .center)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        firstFieldFocused = true
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, bottomInsetHeight)
    }

    private var selfieStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
		VStack(spacing: 28) {
                if let gif = selfieGIFURL {
                    ZStack(alignment: .bottom) {
                        Circle()
                            .fill(Color.white)
							.frame(width: 86, height: 86)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.neon, lineWidth: 6) // inward stroke
                            )
                            .offset(y: 6)
                        GIFWebView(url: gif, objectFit: "contain")
                            .frame(width: 74, height: selfieGIFHeight)
							.clipShape(RoundedRectangle(cornerRadius: 37, style: .circular))
                    }
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showSelfieCamera = true
                    }) {
                        HStack(spacing: 6) {
                            Image("Retake")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                                .foregroundStyle(.secondary)
                            Text("Retake")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                } else {
                    Image("selfie-white")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 64)
                        .foregroundStyle(Color(red: 0.69, green: 0.965, blue: 0.0))
                        .scaleEffect(selfiePulse ? 1.08 : 0.92)
                        .opacity(selfiePulse ? 1.0 : 0.9)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                                selfiePulse.toggle()
                            }
                        }
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showSelfieCamera = true
                        }
                }
				
				if selfieGIFURL == nil {
					Text("Setup a quick selfie clip")
						.font(.system(size: 17, weight: .regular))
						.multilineTextAlignment(.center)
				}
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, bottomInsetHeight)
    }

    private var contactsStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 24) {
                Image("Friends")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 50)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                
                Text("Let's run together!")
                    .font(.system(size: 17, weight: .regular))
                    .multilineTextAlignment(.center)

                switch contactsFetcher.authorization {
                case .notDetermined:
                    ProgressView().progressViewStyle(.circular)
                case .authorized:
                    contactsList
                default:
                    EmptyView()
                }
            }
            .padding(.top, 12)
            Spacer(minLength: 0)
        }
        .padding(.bottom, bottomInsetHeight)
        .onAppear {
            if contactsFetcher.authorization == .notDetermined {
                contactsFetcher.requestAccess()
            } else if contactsFetcher.authorization == .authorized && contactsFetcher.contacts.isEmpty {
                contactsFetcher.loadContacts()
            }
        }
    }

    private var contactsList: some View {
        VStack(alignment: .leading, spacing: 16) {
            if contactsFetcher.contacts.isEmpty {
                Text("No contacts with phone numbers found.")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    TextField("Search", text: $contactsSearch)
                        .focused($searchFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(.systemGray6))
                        )
                    if searchFocused || !contactsSearch.isEmpty {
                        Button(action: { contactsSearch = ""; searchFocused = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)

                let all = Array(contactsFetcher.contacts.enumerated())
                let filtered = contactsSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? all : all.filter { (_, c) in
                    let name = "\(c.givenName) \(c.familyName)"
                    return name.range(of: contactsSearch, options: .caseInsensitive) != nil
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(filtered, id: \.0) { idx, c in
                            let fullName = "\(c.givenName) \(c.familyName)".trimmingCharacters(in: .whitespaces)
                            HStack(spacing: 10) {
                                ZStack(alignment: .bottomTrailing) {
                                    Circle()
                                        .fill(Color(.systemGray6))
                                        .frame(width: 44, height: 44)
                                    let initials = (String(c.givenName.first ?? Character(" ")) + String(c.familyName.first ?? Character(" "))).trimmingCharacters(in: .whitespaces)
                                    Text(initials.isEmpty ? "?" : initials)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.black)
                                        .frame(width: 44, height: 44)
                                    ZStack {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 14, height: 14)
                                        Image(systemName: "message.fill")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 8, height: 8)
                                            .foregroundStyle(Color.white)
                                    }
                                    .offset(x: -2, y: -2)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fullName.isEmpty ? "(No Name)" : fullName)
                                        .font(.system(size: 15, weight: .regular))
                                    let knows = max(1, min(5, (fullName.count % 5) + 1))
                                    Text("KNOWS \(knows) FRIENDS")
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()

                                Button(action: {
                                    if selectedContactIndices.contains(idx) {
                                        return
                                    } else {
                                        if let raw = c.phoneNumbers.first?.value.stringValue, !raw.isEmpty {
                                            let code = generateInviteCode()
                                            let link = "https://superba.me/i/\(code)"
                                            let digits = raw.filter { $0.isNumber || $0 == "+" }
                                            if MFMessageComposeViewController.canSendText() {
                                                messageDraft = MessageDraft(recipients: [digits], body: link, code: code, index: idx)
                                            } else {
                                                UIPasteboard.general.string = link
                                            }
                                            // Try to store invite in Supabase (best-effort)
                                            Task {
                                                do {
                                                    _ = try await client.database
                                                        .from("invites")
                                                        .insert([
                                                            "code": code,
                                                            "inviter_phone": auth.phoneNumber,
                                                            "recipient_phone": raw
                                                        ])
                                                        .execute()
                                                } catch {
                                                    // ignore if table doesn't exist yet
                                                }
                                            }
                                        }
                                    }
                                }) {
                                    Group {
                                        if selectedContactIndices.contains(idx) {
                                            Text("Invited")
                                                .font(.system(size: 12, weight: .semibold))
                                        } else {
                                            Text("Invite")
                                                .font(.system(size: 12, weight: .semibold))
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(height: 38)
                                    .foregroundStyle(selectedContactIndices.contains(idx) ? Color.white : Color.black)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(
                                                selectedContactIndices.contains(idx)
                                                ? AnyShapeStyle(Color(.systemGray3))
                                                : AnyShapeStyle(
                                                    LinearGradient(
                                                        colors: [
                                                            Color(red: 0.78, green: 1.00, blue: 0.20),
                                                            Color(red: 0.62, green: 0.90, blue: 0.00)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.trailing, 4)
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 440)
            }
        }
    }

    private func inviteMessage() -> String {
        let link = "https://superba.me/i/\(generateInviteCode())"
        return link
    }

    private func generateInviteCode(length: Int = 10) -> String {
        let symbols = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in symbols.randomElement(using: &rng)! })
    }

    private var locationStep: some View {
        ZStack {
            VStack(spacing: 16) {
                Text("Ready.")
                    .font(.custom("Knewave", size: 40))
                    .foregroundStyle(.black)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                locationRequester.request()
            }
        }
        .onChange(of: locationRequester.authorization) { _ in
            // Once the system resolves (authorized/denied/restricted), proceed into the app
            // We don't care which choice here; the app handles denied state in RunView
            hasCompletedOnboarding = true
        }
    }

    private func saveNameAndContinue() async {
        errorMessage = nil
        let f = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty, !l.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            // Save by user id when available (UPDATE only to respect RLS)
            if let session = try? await client.auth.session {
                let uid = session.user.id
                _ = try await client.database
                    .from("profiles")
                    .update(["first_name": f, "last_name": l])
                    .eq("id", value: uid.uuidString)
                    .execute()
                // Reflect immediately in app state
                await MainActor.run {
                    account.firstName = f
                    account.lastName = l
                }
            } else {
                // Fallback to UPDATE by phone (no insert)
                let phone = auth.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try await client.database
                    .from("profiles")
                    .update(["first_name": f, "last_name": l])
                    .eq("phone", value: phone)
                    .execute()
                await MainActor.run {
                    account.firstName = f
                    account.lastName = l
                }
            }
            step = .selfie
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AuthViewModel())
}


// MARK: - Models
struct MessageDraft: Identifiable, Equatable {
    let id = UUID()
    let recipients: [String]
    let body: String
    let code: String
    let index: Int
}

// MARK: - Message composer wrapper
struct MessageComposeView: UIViewControllerRepresentable {
    var recipients: [String]
    var body: String
    var onFinish: (MessageComposeResult) -> Void

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let parent: MessageComposeView
        init(parent: MessageComposeView) { self.parent = parent }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            parent.onFinish(result)
            controller.dismiss(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.messageComposeDelegate = context.coordinator
        vc.recipients = recipients
        vc.body = body
        vc.modalPresentationStyle = .pageSheet
        if let sheet = vc.sheetPresentationController {
            if #available(iOS 16.0, *) {
                let sixty = UISheetPresentationController.Detent.custom(identifier: .init("sixty")) { _ in
                    UIScreen.main.bounds.height * 0.60
                }
                sheet.detents = [sixty]
                sheet.preferredCornerRadius = 22
                sheet.largestUndimmedDetentIdentifier = nil
                sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            } else if #available(iOS 15.0, *) {
                sheet.detents = [.medium(), .large()]
                sheet.selectedDetentIdentifier = .medium
            }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}
}
