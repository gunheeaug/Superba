import SwiftUI
import UIKit

private struct DialCountry: Identifiable, Hashable {
    let id: String
    let iso2: String
    let name: String
    let dial: String
    let flag: String
}

// Standard corner radius for bottom sheets and buttons
private let sheetCornerRadius: CGFloat = 22

private let dialCountries: [DialCountry] = [
    .init(id: "US", iso2: "US", name: "United States", dial: "+1", flag: "🇺🇸"),
    .init(id: "CA", iso2: "CA", name: "Canada", dial: "+1", flag: "🇨🇦"),
    .init(id: "GB", iso2: "GB", name: "United Kingdom", dial: "+44", flag: "🇬🇧"),
    .init(id: "AU", iso2: "AU", name: "Australia", dial: "+61", flag: "🇦🇺"),
    .init(id: "NZ", iso2: "NZ", name: "New Zealand", dial: "+64", flag: "🇳🇿"),
    .init(id: "DE", iso2: "DE", name: "Germany", dial: "+49", flag: "🇩🇪"),
    .init(id: "FR", iso2: "FR", name: "France", dial: "+33", flag: "🇫🇷"),
    .init(id: "ES", iso2: "ES", name: "Spain", dial: "+34", flag: "🇪🇸"),
    .init(id: "IT", iso2: "IT", name: "Italy", dial: "+39", flag: "🇮🇹"),
    .init(id: "NL", iso2: "NL", name: "Netherlands", dial: "+31", flag: "🇳🇱"),
    .init(id: "SE", iso2: "SE", name: "Sweden", dial: "+46", flag: "🇸🇪"),
    .init(id: "NO", iso2: "NO", name: "Norway", dial: "+47", flag: "🇳🇴"),
    .init(id: "DK", iso2: "DK", name: "Denmark", dial: "+45", flag: "🇩🇰"),
    .init(id: "FI", iso2: "FI", name: "Finland", dial: "+358", flag: "🇫🇮"),
    .init(id: "IE", iso2: "IE", name: "Ireland", dial: "+353", flag: "🇮🇪"),
    .init(id: "CH", iso2: "CH", name: "Switzerland", dial: "+41", flag: "🇨🇭"),
    .init(id: "AT", iso2: "AT", name: "Austria", dial: "+43", flag: "🇦🇹"),
    .init(id: "BE", iso2: "BE", name: "Belgium", dial: "+32", flag: "🇧🇪"),
    .init(id: "PT", iso2: "PT", name: "Portugal", dial: "+351", flag: "🇵🇹"),
    .init(id: "GR", iso2: "GR", name: "Greece", dial: "+30", flag: "🇬🇷"),
    .init(id: "TR", iso2: "TR", name: "Türkiye", dial: "+90", flag: "🇹🇷"),
    .init(id: "IL", iso2: "IL", name: "Israel", dial: "+972", flag: "🇮🇱"),
    .init(id: "AE", iso2: "AE", name: "United Arab Emirates", dial: "+971", flag: "🇦🇪"),
    .init(id: "IN", iso2: "IN", name: "India", dial: "+91", flag: "🇮🇳"),
    .init(id: "JP", iso2: "JP", name: "Japan", dial: "+81", flag: "🇯🇵"),
    .init(id: "KR", iso2: "KR", name: "South Korea", dial: "+82", flag: "🇰🇷"),
    .init(id: "CN", iso2: "CN", name: "China", dial: "+86", flag: "🇨🇳"),
    .init(id: "HK", iso2: "HK", name: "Hong Kong", dial: "+852", flag: "🇭🇰"),
    .init(id: "SG", iso2: "SG", name: "Singapore", dial: "+65", flag: "🇸🇬"),
    .init(id: "MY", iso2: "MY", name: "Malaysia", dial: "+60", flag: "🇲🇾"),
    .init(id: "ID", iso2: "ID", name: "Indonesia", dial: "+62", flag: "🇮🇩"),
    .init(id: "PH", iso2: "PH", name: "Philippines", dial: "+63", flag: "🇵🇭"),
    .init(id: "TH", iso2: "TH", name: "Thailand", dial: "+66", flag: "🇹🇭"),
    .init(id: "VN", iso2: "VN", name: "Vietnam", dial: "+84", flag: "🇻🇳"),
    .init(id: "MX", iso2: "MX", name: "Mexico", dial: "+52", flag: "🇲🇽"),
    .init(id: "BR", iso2: "BR", name: "Brazil", dial: "+55", flag: "🇧🇷"),
    .init(id: "AR", iso2: "AR", name: "Argentina", dial: "+54", flag: "🇦🇷"),
    .init(id: "CL", iso2: "CL", name: "Chile", dial: "+56", flag: "🇨🇱"),
    .init(id: "CO", iso2: "CO", name: "Colombia", dial: "+57", flag: "🇨🇴"),
    .init(id: "ZA", iso2: "ZA", name: "South Africa", dial: "+27", flag: "🇿🇦"),
]

// Country-specific phone number examples for placeholder text
// Simplified placeholders per country (no "e.g.")
private func placeholderFor(iso2: String) -> String {
    switch iso2 {
    case "KR":
        // E.164 local part for Korea after +82 drops leading 0: 10-0000-0000
        return "10-0000-0000"
    case "US", "CA":
        return "000-000-0000"
    default:
        // Generic short pattern
        return "0000-0000"
    }
}

private func expectedLocalDigits(for iso2: String) -> Int {
    placeholderFor(iso2: iso2).filter({ "0123456789".contains($0) }).count
}

private func formattingGroups(for iso2: String) -> [Int] {
    switch iso2 {
    case "KR": return [2, 4, 4]
    case "US", "CA": return [3, 3, 4]
    default: return [4, 4]
    }
}

private func formatLocalDigits(_ digits: String, for iso2: String) -> String {
    let groups = formattingGroups(for: iso2)
    var parts: [String] = []
    var start = 0
    let chars = Array(digits)
    for (i, size) in groups.enumerated() {
        guard start < chars.count else { break }
        let end = min(start + size, chars.count)
        let slice = String(chars[start..<end])
        parts.append(slice)
        start = end
        if i == groups.count - 1 && start < chars.count {
            // append any remaining digits to the last part
            parts[parts.count - 1] += String(chars[start..<chars.count])
            start = chars.count
        }
    }
    if parts.isEmpty { return digits }
    return parts.joined(separator: "-")
}

struct PhoneAuthView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var selectedCountryIndex: Int = 0
    @State private var localNumber: String = ""
    @State private var showingDialPicker: Bool = false
    @FocusState private var numberFieldFocused: Bool
    @FocusState private var codeFieldFocused: Bool
    @State private var showUseDifferentNumber: Bool = false
    @State private var delayedButtonTask: Task<Void, Never>? = nil

    // Countries sorted alphabetically by name, with United States pinned to the top
    private var countries: [DialCountry] {
        var list = dialCountries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if let idx = list.firstIndex(where: { $0.iso2 == "US" }) {
            let us = list.remove(at: idx)
            list.insert(us, at: 0)
        }
        return list
    }

    private var currentISO2: String { countries[selectedCountryIndex].iso2 }
    private var enteredDigitsCount: Int { localNumber.filter({ "0123456789".contains($0) }).count }
    private var expectedDigits: Int { expectedLocalDigits(for: currentISO2) }
    private var activationThreshold: Int { max(1, expectedDigits / 2) }
    private var isSendActive: Bool { enteredDigitsCount >= activationThreshold }
    private var otpDigitsCount: Int { auth.otpCode.filter({ "0123456789".contains($0) }).count }

    private var numberPlaceholder: String {
        placeholderFor(iso2: countries[selectedCountryIndex].iso2)
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 24) {
                    Text(auth.step == .enterPhone ? "What’s your phone number?" : "Enter the verification code")
                        .font(.system(size: 17, weight: .regular))
                        .multilineTextAlignment(.center)

                    switch auth.step {
                    case .enterPhone:
                        phoneEntry
                    case .enterCode:
                        codeEntry
                    }

                    if let error = auth.errorMessage, !error.isEmpty {
                        Text(error)
                            .font(.footnote.weight(.regular))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
                Spacer(minLength: 0)
            }
        }
        .onAppear {
            if let region = Locale.current.regionCode,
               let idx = countries.firstIndex(where: { $0.iso2 == region }) {
                selectedCountryIndex = idx
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                numberFieldFocused = true
            }
        }
        .onChange(of: auth.step) { newStep in
            if newStep == .enterCode {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    codeFieldFocused = true
                }
                showUseDifferentNumber = false
                delayedButtonTask?.cancel()
                delayedButtonTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    if Task.isCancelled { return }
                    showUseDifferentNumber = true
                }
            }
            if newStep == .enterPhone {
                delayedButtonTask?.cancel()
                showUseDifferentNumber = false
            }
        }
        .sheet(isPresented: $showingDialPicker) {
            dialPickerSheet
                .presentationDetents([.fraction(0.35)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(sheetCornerRadius)
        }
        .onChange(of: showingDialPicker) { isPresented in
            if !isPresented, auth.step == .enterPhone {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    numberFieldFocused = true
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if auth.step == .enterPhone {
                // Transparent background accessory above the keyboard
                VStack(spacing: 20) {
                    Text("We’ll text you a code to verify")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    Button(action: {
                        let dial = countries[selectedCountryIndex].dial
                        let digits = localNumber.filter({ "0123456789".contains($0) })
                        // Secret bypass: +1 8888888888 → skip verification
                        if dial == "+1" && digits == "8888888888" {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            auth.phoneNumber = dial + digits
                            hasCompletedOnboarding = false
                            auth.isAuthenticated = true
                            return
                        }
                        auth.phoneNumber = dial + digits
                        Task { await auth.sendOTP() }
                    }) {
                        Group {
                            if auth.isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.black)
                            } else {
                                Text("Send Code")
                                    .font(.system(size: 20, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .padding(.vertical, 2)
                        .foregroundStyle(isSendActive ? Color.black : Color.white)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(
                                    isSendActive
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
                    .disabled(!isSendActive || auth.isLoading)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .background(Color.clear)
            } else if auth.step == .enterCode {
                VStack(spacing: 16) {
                    Button(action: {
                        Task { await auth.verifyOTP() }
                    }) {
                        Group {
                            if auth.isLoading {
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
                        .foregroundStyle(otpDigitsCount >= 6 ? Color.black : Color.white)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(
                                    otpDigitsCount >= 6
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
                    .disabled(otpDigitsCount < 6 || auth.isLoading)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .background(Color.clear)
            }
        }
    }

    private var phoneEntry: some View {
        VStack(spacing: 24) {
            HStack(spacing: 10) {
                Button(action: { showingDialPicker = true }) {
                    Text(countries[selectedCountryIndex].dial)
                        .font(.system(size: 34, weight: .semibold, design: .default))
                        .underline()
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                TextField("", text: $localNumber, prompt: Text(numberPlaceholder).font(.system(size: 34, weight: .semibold)))
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .font(.system(size: 34, weight: .semibold, design: .default))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: true, vertical: false)
                    .focused($numberFieldFocused)
                    .onTapGesture { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                    .onChange(of: localNumber) { newValue in
                        let digitsOnly = newValue.filter({ "0123456789".contains($0) })
                        let maxDigits = expectedLocalDigits(for: currentISO2)
                        let clipped = String(digitsOnly.prefix(maxDigits))
                        let formatted = formatLocalDigits(clipped, for: currentISO2)
                        if formatted != newValue { localNumber = formatted }
                    }
                    .onChange(of: selectedCountryIndex) { _ in
                        let digitsOnly = localNumber.filter({ "0123456789".contains($0) })
                        let maxDigits = expectedLocalDigits(for: currentISO2)
                        let clipped = String(digitsOnly.prefix(maxDigits))
                        localNumber = formatLocalDigits(clipped, for: currentISO2)
                    }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var codeEntry: some View {
        VStack(spacing: 24) {
            HStack(spacing: 10) {
                TextField("", text: $auth.otpCode, prompt: Text("_ _ _   _ _ _").font(.system(size: 34, weight: .semibold)))
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(size: 34, weight: .semibold, design: .default))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: true, vertical: false)
                    .focused($codeFieldFocused)
                    .onTapGesture { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                    .onChange(of: auth.otpCode) { newValue in
                        let digits = newValue.filter({ "0123456789".contains($0) })
                        let clipped = String(digits.prefix(6))
                        let formatted: String
                        if clipped.count <= 3 {
                            formatted = clipped
                        } else {
                            let first = String(clipped.prefix(3))
                            let rest = String(clipped.suffix(clipped.count - 3))
                            formatted = first + "   " + rest
                        }
                        if formatted != newValue { auth.otpCode = formatted }
                    }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if showUseDifferentNumber {
                Button("Use a different number") {
                    delayedButtonTask?.cancel()
                    auth.reset()
                }
                .font(.system(size: 13, weight: .regular))
                .underline(true)
                .foregroundStyle(.secondary)
                .padding(.top, 40)
                .buttonStyle(.borderless)
            }
        }
    }
}

// Bottom sheet dial code picker
extension PhoneAuthView {
    @ViewBuilder
    private var dialPickerSheet: some View {
        VStack(spacing: 6) {
            Picker("Country code", selection: $selectedCountryIndex) {
                ForEach(0..<countries.count, id: \.self) { idx in
                    let c = countries[idx]
                    Text("\(c.flag)  \(c.name)  (\(c.dial))")
                        .font(.system(size: 22, weight: .semibold))
                        .tag(idx)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 290)
            .padding(.top, 6)
        }
        .padding(.horizontal, 16)
    }
}

#Preview {
    PhoneAuthView()
        .environmentObject(AuthViewModel())
}


