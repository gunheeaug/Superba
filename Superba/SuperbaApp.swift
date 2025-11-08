//
//  SuperbaApp.swift
//  Superba
//
//  Created by Gunhee Han on 11/5/25.
//

import SwiftUI

@main
struct SuperbaApp: App {
    @StateObject private var auth = AuthViewModel()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var account = AccountManager()
    @AppStorage("pendingInviteCode") private var pendingInviteCode: String = ""
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(locationManager)
                .environmentObject(account)
                .onOpenURL { url in
                    // Expecting: https://superba.me/i/<code>
                    guard let host = url.host, host.hasSuffix("superba.me") || host == "superba.me" else { return }
                    let parts = url.pathComponents.filter { $0 != "/" }
                    if parts.count >= 2, parts[0] == "i" {
                        pendingInviteCode = parts[1]
                    }
                }
        }
    }
}
