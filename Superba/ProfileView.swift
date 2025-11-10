import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var account: AccountManager
    @EnvironmentObject var auth: AuthViewModel
    @Binding var isPresented: Bool
    @State private var showSettings: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                HStack {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(8)
                    }
                    Spacer()
                    Text("Profile")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black)
                    Spacer()
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                
                // Basic info
                VStack(spacing: 8) {
                    Text(fullName())
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.black)
                    if let phone = account.phoneNumber, !phone.isEmpty {
                        Text(phone)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.gray)
                    }
                    
                    // First / Last name rows
                    VStack(spacing: 6) {
                        HStack {
                            Text("First")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.gray)
                            Spacer()
                            Text((account.firstName ?? "").isEmpty ? "-" : (account.firstName ?? ""))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.black)
                        }
                        HStack {
                            Text("Last")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.gray)
                            Spacer()
                            Text((account.lastName ?? "").isEmpty ? "-" : (account.lastName ?? ""))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.black)
                        }
                    }
                    .padding(.top, 6)
                }
                .padding(.top, 8)
                
                Spacer()
            }
            .task {
                await account.loadProfileFromSupabase()
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
    
    private func fullName() -> String {
        let first = (account.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (account.lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let space = (!first.isEmpty && !last.isEmpty) ? " " : ""
        return "\(first)\(space)\(last)".isEmpty ? "Me" : "\(first)\(space)\(last)"
    }
}


