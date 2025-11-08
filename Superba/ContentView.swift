//
//  ContentView.swift
//  Superba
//
//  Created by Gunhee Han on 11/5/25.
//

import SwiftUI
import Supabase

struct ContentView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("pendingInviteCode") private var pendingInviteCode: String = ""
    private var client: SupabaseClient { SupabaseManager.shared.client }

    var body: some View {
        Group {
            if auth.isAuthenticated {
                if hasCompletedOnboarding {
                    RunView(isPresented: .constant(true))
                } else {
                    OnboardingView()
                }
            } else {
                PhoneAuthView()
            }
        }
        .onChange(of: auth.isAuthenticated) { _ in markAcceptedIfPossible() }
        .onChange(of: pendingInviteCode) { _ in markAcceptedIfPossible() }
        .task { markAcceptedIfPossible() }
    }

    private func markAcceptedIfPossible() {
        guard auth.isAuthenticated, !pendingInviteCode.isEmpty else { return }
        let code = pendingInviteCode
        Task {
            do {
                _ = try await client.database
                    .rpc("invites_mark_accepted", params: ["p_code": code])
                    .execute()
            } catch {
                // ignore failures; user may not have the RPC installed yet
            }
            pendingInviteCode = ""
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
