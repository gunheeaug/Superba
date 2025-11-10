import SwiftUI
import CoreLocation
import UserNotifications
import Photos
import Contacts
import AVFoundation

struct SettingsSheet: View {
    @EnvironmentObject var account: AccountManager
    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var permissionLocation: String = "Unknown"
    @State private var permissionContacts: String = "Unknown"
    @State private var permissionCamera: String = "Unknown"
    @State private var permissionNotifications: String = "Unknown"
    @State private var permissionPhotos: String = "Unknown"
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Spacer()
                Text("Settings")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 8)
            
            ScrollView {
                VStack(spacing: 16) {
                    // About
                    VStack(spacing: 8) {
                        Text("About")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 14)
                            .padding(.top, 6)
                        settingsRow(label: "App Version", value: appVersionText(), iconName: "Settings")
                    }
                    
                    // Device Permissions
                    VStack(spacing: 8) {
                        Text("Device Permissions")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 14)
                            .padding(.top, 6)
                        settingsRow(label: "Location Services", value: permissionLocation, iconName: "Location Services")
                            .contentShape(Rectangle())
                            .onTapGesture { openAppSettings() }
                        settingsRow(label: "Contacts", value: permissionContacts, iconName: "Contacts")
                            .contentShape(Rectangle())
                            .onTapGesture { openAppSettings() }
                        settingsRow(label: "Camera", value: permissionCamera, iconName: "camera-white", iconTint: Color(red: 0x29/255.0, green: 0x2D/255.0, blue: 0x32/255.0))
                            .contentShape(Rectangle())
                            .onTapGesture { openAppSettings() }
                        settingsRow(label: "Notifications", value: permissionNotifications, iconName: "Notifications")
                            .contentShape(Rectangle())
                            .onTapGesture { openAppSettings() }
                        settingsRow(label: "Photos", value: permissionPhotos, iconName: "photo-library-white", iconTint: Color(red: 0x29/255.0, green: 0x2D/255.0, blue: 0x32/255.0))
                            .contentShape(Rectangle())
                            .onTapGesture { openAppSettings() }
                    }
                    
                    // Help
                    VStack(spacing: 8) {
                        Text("Help")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 14)
                            .padding(.top, 16)
                        settingsButtonRow(title: "Feedback / Report", iconName: "error") {
                            if let url = URL(string: "https://pbdteam.notion.site/2481607e212c8165a117cf4ecb293cbb?pvs=105") {
                                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                            }
                        }
                        settingsButtonRow(title: "Terms and Privacy Policy", iconName: "Terms") {
                            if let url = URL(string: "https://www.augaugaug.com/terms-and-privacy") {
                                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                            }
                        }
                    }
                    
                    // Account
                    VStack(spacing: 8) {
                        Text("Account")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 14)
                            .padding(.top, 16)
                        settingsButtonRow(title: "Logout", iconName: "Logout") {
                            Task {
                                await auth.signOut()
                                dismiss()
                            }
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .onAppear { Task { await refreshPermissions() } }
    }
}

// MARK: - Helpers
private extension SettingsSheet {
    func settingsRow(label: String, value: String, iconName: String? = nil, iconTint: Color? = nil) -> some View {
        HStack(spacing: 10) {
            if let icon = iconName {
                if let tint = iconTint {
                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(tint)
                        .frame(width: 20, height: 20)
                } else {
                    Image(icon)
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
            }
            Text(label)
                .foregroundColor(.black)
            Spacer()
            Text(value)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(Color.clear)
    }
    
    func settingsButtonRow(title: String, titleColor: Color = .black, iconName: String? = nil, iconTint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
            action()
        }) {
            HStack(spacing: 10) {
                if let icon = iconName {
                    if let tint = iconTint {
                        Image(icon)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(tint)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(icon)
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                }
                Text(title)
                    .foregroundColor(titleColor)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .buttonStyle(.plain)
    }
    
    func appVersionText() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(v) (\(b))"
    }
    
    func permissionString(for status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Ask"
        case .restricted, .denied: return "Denied"
        case .authorizedAlways, .authorizedWhenInUse: return "Allowed"
        @unknown default: return "Unknown"
        }
    }
    
    func permissionString(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Ask"
        case .denied: return "Denied"
        case .authorized, .provisional, .ephemeral: return "Allowed"
        @unknown default: return "Unknown"
        }
    }
    
    func permissionString(for status: PHAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Ask"
        case .denied, .restricted, .limited: return "Denied"
        case .authorized: return "Allowed"
        @unknown default: return "Unknown"
        }
    }
    
    func permissionString(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Ask"
        case .denied, .restricted: return "Denied"
        case .authorized: return "Allowed"
        @unknown default: return "Unknown"
        }
    }
    
    func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    
    func refreshPermissions() async {
        // Location
        let locStatus = CLLocationManager.authorizationStatus()
        await MainActor.run { permissionLocation = permissionString(for: locStatus) }
        // Contacts
        let contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
        await MainActor.run {
            switch contactsStatus {
            case .notDetermined: permissionContacts = "Ask"
            case .denied, .restricted: permissionContacts = "Denied"
            case .authorized: permissionContacts = "Allowed"
            @unknown default: permissionContacts = "Unknown"
            }
        }
        // Camera
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        await MainActor.run { permissionCamera = permissionString(for: cameraStatus) }
        // Photos
        let photosStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        await MainActor.run { permissionPhotos = permissionString(for: photosStatus) }
        // Notifications
        let notif = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run { permissionNotifications = permissionString(for: notif.authorizationStatus) }
    }
}


