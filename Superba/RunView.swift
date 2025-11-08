import SwiftUI
import MapKit
import CoreLocation
import Combine
import UIKit
import SceneKit
import UniformTypeIdentifiers
import WebKit
import ActivityKit
import CoreMotion

struct RunView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var account: AccountManager
    @Binding var isPresented: Bool
    @State private var region: MKCoordinateRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), span: MKCoordinateSpan(latitudeDelta: 0.0008, longitudeDelta: 0.0008))
    @State private var hasCentered: Bool = false
    @StateObject private var tracker = RunTracker()
    @State private var isRunning: Bool = false
    @State private var isPaused: Bool = false
    @State private var isFinished: Bool = false
    @State private var isGeneratingGIF: Bool = false
    @State private var bannerShake: CGFloat = 0

    private let targetZoomLevel: Int = 19
    
    private var isLocationAuthorized: Bool {
        let s = locationManager.authorizationStatus
        return s == .authorizedAlways || s == .authorizedWhenInUse
    }
    
    // Fallback center based on phone country code when location is unavailable
    private func fallbackCenterFromPhone(_ phone: String?) -> CLLocationCoordinate2D {
        guard let p = phone else { return CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194) } // SF default
        func has(_ cc: String) -> Bool { p.trimmingCharacters(in: .whitespaces).hasPrefix(cc) }
        if has("+82") { return CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780) } // Seoul
        if has("+81") { return CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503) } // Tokyo
        if has("+1")  { return CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060) } // New York
        if has("+44") { return CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278) }  // London
        if has("+33") { return CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522) }   // Paris
        if has("+49") { return CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050) }  // Berlin
        if has("+61") { return CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093) } // Sydney
        if has("+65") { return CLLocationCoordinate2D(latitude: 1.3521, longitude: 103.8198) }  // Singapore
        if has("+86") { return CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074) } // Beijing
        return CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    }
    
    private var currentPaceString: String {
        if let cur = tracker.currentPaceMinPerKm, cur.isFinite, cur > 0 {
            let m = Int(cur)
            let s = Int((cur - Double(m)) * 60)
            return String(format: "%d:%02d", m, s)
        }
        // Fallback to average pace if no current pace yet
        let km = tracker.distanceMeters / 1000.0
        guard km >= 0.05 else { return "00:00" }
        let secPerKm = Double(tracker.elapsedSeconds) / km
        let cappedSecPerKm = min(secPerKm, 5999)
        let m = Int(cappedSecPerKm) / 60
        let s = Int(cappedSecPerKm) % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Map with live route polyline and user location
            RunMKMapView(
                region: $region, 
                route: tracker.routeCoordinates, 
                userCoordinate: isFinished ? nil : locationManager.lastCoordinate,  // Hide pulse when finished
                followUser: true,
                profileGIFURL: account.profileGIFURL,
                isRunning: isRunning,
                currentPace: currentPaceString
            )
                .ignoresSafeArea()
                .onAppear { 
                    locationManager.start()
                    centerOnUserIfAvailable() 
                }
                .onReceive(locationManager.$lastCoordinate) { _ in
                    // Always follow user location
                    updateMapToFollowUser()
                }
                .onAppear {
                    // Auto-resume if launched due to ongoing Live Activity
                    if let resumeElapsed = account.liveActivityResumeElapsed {
                        tracker.elapsedSeconds = resumeElapsed
                        tracker.setStartDateForResume(elapsedSeconds: resumeElapsed)
                    }
                    if let resumeDistance = account.liveActivityResumeDistance {
                        tracker.distanceMeters = resumeDistance
                    }
                    if let paused = account.liveActivityResumeIsPaused {
                        if paused {
                            isRunning = true; isPaused = true
                        } else {
                            // Start/Resume tracking immediately
                            tracker.start()
                            isRunning = true; isPaused = false
                        }
                        // clear resume flags so future opens are not affected
                        account.liveActivityResumeElapsed = nil
                        account.liveActivityResumeDistance = nil
                        account.liveActivityResumeIsPaused = nil
                        account.presentRunViewDirect = false
                    }
                }
            
            // Top gradient overlay with same color as MapView
            VStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 250.0/255.0, green: 250.0/255.0, blue: 243.0/255.0).opacity(1.0),
                        Color(red: 250.0/255.0, green: 250.0/255.0, blue: 243.0/255.0).opacity(0.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: UIScreen.main.bounds.height * 0.1)  // Changed from 0.2 to 0.1 (10%)
                Spacer()
            }
            .ignoresSafeArea()

			// Dim gradient overlay when location is disabled (covers everything except the banner)
			if !isLocationAuthorized {
				LinearGradient(
					gradient: Gradient(colors: [
						Color.black.opacity(0.20),
						Color.black.opacity(0.45)
					]),
					startPoint: .top,
					endPoint: .bottom
				)
				.ignoresSafeArea()
				.transition(.opacity)
				.zIndex(1)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Trigger haptic + shake when user taps anywhere on the dim overlay
                    let heavy = UIImpactFeedbackGenerator(style: .heavy)
                    heavy.prepare()
                    heavy.impactOccurred(intensity: 1.0)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        heavy.impactOccurred(intensity: 0.9)
                    }
                    withAnimation(.easeInOut(duration: 0.35)) { bannerShake += 1 }
                }
			}

			// Location disabled banner (for already-onboarded users who denied access)
			if !isLocationAuthorized {
                VStack {
					VStack(alignment: .center, spacing: 16) {
                        // Row 1: Icon + title
                        HStack(spacing: 10) {
                            Image("Location-slash")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 22, height: 22)
                                .foregroundColor(.black)
                            Text("Location is off")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
						// Rows 2-3: Subtext guidance
						VStack(alignment: .center, spacing: 4) {
                            Text("Enable Location and turn Precise on")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                            Text("for Superba in Settings to track your run.")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        Button(action: {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Text("Allow in Settings")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .padding(.horizontal, 16)
                                .padding(.top, 4)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.78, green: 1.00, blue: 0.20),
                                            Color(red: 0.62, green: 0.90, blue: 0.00)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
					}
                    .frame(maxWidth: .infinity, alignment: .center)
					.padding(.horizontal, 18)
					.padding(.vertical, 18) // taller banner
					.background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
					.modifier(ShakeEffect(animatableData: bannerShake))
					.shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
					.padding(.top, 12)
					Spacer()
				}
				.padding(.horizontal, 16)
				.transition(.opacity)
                .zIndex(100)
			}

            // Removed close button per design

            // Stats sheet - always visible until finished
            if !isFinished {
                VStack(spacing: 0) {
                    Spacer()
                    RunStatsSheet(
                        elapsed: tracker.elapsedSeconds,
                        distanceMeters: tracker.distanceMeters,
                        isRunning: isRunning,
                        isPaused: isPaused,
                        currentPace: currentPaceString,
                        cadenceSpm: tracker.cadence,
                        steps: tracker.stepCount,
                        elevationGain: tracker.elevationGainMeters,
                        locationAuthorized: isLocationAuthorized,
                        onStart: {
                            if !isLocationAuthorized {
                                // Longer, heavier haptic + shake
                                let heavy = UIImpactFeedbackGenerator(style: .heavy)
                                heavy.prepare()
                                heavy.impactOccurred(intensity: 1.0)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                    heavy.impactOccurred(intensity: 0.9)
                                }
                                withAnimation(.easeInOut(duration: 0.35)) { bannerShake += 1 }
                            } else {
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.prepare(); generator.impactOccurred()
                                tracker.start()
                                recenterMapForRunning()  // Recenter map to show user at 15% height
                                isRunning = true
                                isPaused = false
                            }
                        },
                        onPauseToggle: {
                            if isPaused { tracker.resume(); isPaused = false } else { tracker.pause(); isPaused = true }
                        },
                        onResume: {
                            tracker.resume()
                            isPaused = false
                        },
                        onFinish: {
                            tracker.stop()
                            tracker.endLiveActivity()
                            
                            // Show loading overlay
                            withAnimation {
                                isGeneratingGIF = true
                            }
                            
                            // Generate combined GIF in background
                            Task {
                                await generateRunAssets()
                                
                                // Hide loading and show final summary
                                await MainActor.run {
                                    withAnimation {
                                        isGeneratingGIF = false
                                    }
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        isRunning = false
                                        isPaused = false
                                    }
                                    // Delay showing final summary slightly for smooth transition
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            isFinished = true
                                        }
                                    }
                                }
                            }
                        }
                    )
                    .frame(height: isRunning ? (isPaused ? UIScreen.main.bounds.height * 0.48 : UIScreen.main.bounds.height * 0.6) : 240)  // Lower height when paused
                    .frame(maxWidth: .infinity)
                    .background(
                        Color.white
                            .cornerRadius(35, corners: [.topLeft, .topRight])
                            .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: -2)
                    )
					.overlay(alignment: .top) {
						// Sheet handle
						Capsule()
							.fill(Color(.systemGray4))
							.frame(width: 44, height: 5)
							.padding(.top, 8)
					}
                    .clipShape(RoundedCorners(radius: 35, corners: [.topLeft, .topRight]))
                    .padding(.horizontal, 0)
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Final summary bottom sheet overlay
            if isFinished {
                ZStack(alignment: .bottom) {
                    // Dimmed background
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation {
                                isFinished = false
                            }
                        }
                    
                    // Custom bottom sheet aligned to bottom
                    RunSummarySheet(
                        elapsed: tracker.elapsedSeconds,
                        distanceMeters: tracker.distanceMeters,
                        routeCoordinates: tracker.routeCoordinates,
                        selfieGIFURL: account.profileGIFURL ?? account.pendingSelfieGIFToAdd,
                        onBack: {
                            withAnimation {
                                isFinished = false
                            }
                        },
                        onAugItHere: { handleAugItHereTapped() }
                    )
                    .environmentObject(account)
                }
                .transition(.opacity)
            }
            
            // Loading overlay while generating GIF
            if isGeneratingGIF {
                ZStack {
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        
                        Text("Creating your run...")
                            .font(.custom("Exq", size: 18))
                            .foregroundColor(.white)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func centerOnUserIfAvailable(atScreenHeightPercent: Double = 0.65) {
        // If location is denied or no coordinate yet, use fallback
        guard let coord = locationManager.lastCoordinate, isLocationAuthorized else {
            let fallback = fallbackCenterFromPhone(account.phoneNumber ?? UserDefaults.standard.string(forKey: "lastPhone"))
            withAnimation(.easeInOut(duration: 0.25)) { region = regionFor(center: fallback, zoom: targetZoomLevel) }
            hasCentered = true
            return
        }
        if !hasCentered {
            withAnimation(.easeInOut(duration: 0.25)) {
                region = regionFor(center: coord, zoom: targetZoomLevel)
            }
            hasCentered = true
        }
    }
    
    private func recenterMapForRunning() {
        guard let coord = locationManager.lastCoordinate else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            var baseRegion = regionFor(center: coord, zoom: targetZoomLevel)
            
            // When running, position user at 85% of screen height
            let offsetRatio = 0.50 - 0.85  // -0.35 offset to move user location to 85% from top
            let latitudeOffset = baseRegion.span.latitudeDelta * offsetRatio
            
            baseRegion.center.latitude += latitudeOffset
            region = baseRegion
        }
    }
    
    private func updateMapToFollowUser() {
        guard let coord = locationManager.lastCoordinate else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            // Always center directly on the user's current coordinate
            region = regionFor(center: coord, zoom: targetZoomLevel)
        }
    }

    // Replace MapViewModel.regionFor with a local helper.
    private func regionFor(center: CLLocationCoordinate2D, zoom: Int) -> MKCoordinateRegion {
        let z = max(0, min(22, zoom))
        // Exponential scale; tuned so at z=19 latDelta ≈ 0.0008 (as used before)
        let latDelta = max(0.0002, 0.0008 * pow(2.0, Double(19 - z)))
        let lonDelta = latDelta
        return MKCoordinateRegion(center: center,
                                  span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
    }

    // Compute a map region that fits the entire route with padding
    private func regionForRoute(coordinates: [CLLocationCoordinate2D], paddingFactor: Double = 1.2) -> MKCoordinateRegion? {
        guard !coordinates.isEmpty else { return nil }
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude
        for c in coordinates {
            if c.latitude < minLat { minLat = c.latitude }
            if c.latitude > maxLat { maxLat = c.latitude }
            if c.longitude < minLon { minLon = c.longitude }
            if c.longitude > maxLon { maxLon = c.longitude }
        }
        var latDelta = max(0.0002, (maxLat - minLat) * paddingFactor)
        var lonDelta = max(0.0002, (maxLon - minLon) * paddingFactor)
        // Ensure non-zero span
        if latDelta == 0 { latDelta = 0.002 }
        if lonDelta == 0 { lonDelta = 0.002 }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2.0,
                                            longitude: (minLon + maxLon) / 2.0)
        return MKCoordinateRegion(center: center,
                                  span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
    }
    
    private func generateRunAssets() async {
        print("🏃 generateRunAssets - tracker.elapsedSeconds: \(tracker.elapsedSeconds)")
        print("🏃 generateRunAssets - tracker.distanceMeters: \(tracker.distanceMeters)")
        print("🏃 generateRunAssets - tracker.routeCoordinates.count: \(tracker.routeCoordinates.count)")
        
        // 1) Render route illustration to an image
        let routeImage = await Task.detached {
            return self.renderRouteIllustrationImage(size: CGSize(width: 600, height: 360))
        }.value
        print("🏃 Route image rendered: \(routeImage.size)")
        
        // 2) Generate combined run selfie GIF (selfie + circle + leaves)
        let selfieGIFURL = account.profileGIFURL ?? account.pendingSelfieGIFToAdd
        print("🏃 Source selfie GIF URL: \(selfieGIFURL?.absoluteString ?? "nil")")
        let combinedGIFURL = account.runProfileURL
        print("🏃 Combined GIF URL: \(combinedGIFURL?.absoluteString ?? "nil")")
        
        // 3) Save route PNG to temp
        var imageURLs: [URL] = []
        if let data = routeImage.pngData() {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("run-route-\(UUID().uuidString).png")
            try? data.write(to: url)
            imageURLs.append(url)
            print("🏃 Route PNG saved to: \(url.path)")
        }
        
        // Build stats text
        let statsText = buildStatsMultilineText()
        print("🏃 Stats text: \(statsText)")
        
        // Use Augboard-style percent positioning for consistent alignment
        let centerX: CGFloat = 0.5
        let textY: CGFloat = 0.5
        let selfieY: CGFloat = 0.7
        let routeY: CGFloat = 0.25
        
        let selfiePercent = CGPoint(x: centerX, y: selfieY)
        let textPercent = CGPoint(x: centerX, y: textY)
        let routePercent = CGPoint(x: centerX, y: routeY)
        
        print("🏃 Selfie percent: \(selfiePercent) (should be above text)")
        print("🏃 Text percent: \(textPercent) (baseline)")
        print("🏃 Route percent: \(routePercent) (should be below text)")
        
        // Store generated assets in AccountManager
        await MainActor.run {
            if let gifURL = combinedGIFURL {
                account.pendingAugboardGIFURLs = [gifURL]
                account.pendingAugboardGIFPercents = [selfiePercent]
                account.pendingAugboardGIFMyAugMetas = [nil]
                print("🏃 Set pendingAugboardGIFURLs: \([gifURL.absoluteString])")
            } else {
                account.pendingAugboardGIFURLs = []
                account.pendingAugboardGIFPercents = []
                account.pendingAugboardGIFMyAugMetas = []
                print("🏃 No combined GIF, cleared pendingAugboardGIFURLs")
            }
            
            // Pass route as static image
            account.pendingAugboardImageFileURLs = imageURLs
            account.pendingAugboardImagePercents = [routePercent]
            print("🏃 Set pendingAugboardImageFileURLs: \(imageURLs.map { $0.path })")
            
            // Provide 3D text for stats
            account.pendingAugboardText = statsText
            account.pendingAugboardTextPercent = textPercent
            account.pendingAugboardOpenKeyboard = false
            account.pendingAugboardFontIndex = 3
            print("🏃 Set pendingAugboardText: \(statsText)")
            print("🏃 Set pendingAugboardFontIndex: 3")
            print("🏃 Assets ready for AR placement")
        }
    }

    
    private func handleAugItHereTapped() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare(); generator.impactOccurred()
        
        // Assets are already generated, just open camera
        account.presentCameraDirect = true
        print("🏃 Opening camera with pre-generated assets...")
    }

    private func renderRouteIllustrationImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            guard !tracker.routeCoordinates.isEmpty else {
                // Draw a dot if no route
                let dotSize: CGFloat = 20
                let dotRect = CGRect(x: (size.width - dotSize) / 2, y: (size.height - dotSize) / 2, width: dotSize, height: dotSize)
                UIColor(red: 0xA9/255.0, green: 0xE4/255.0, blue: 0xFF/255.0, alpha: 1.0).setFill() // start color of gradient
                UIBezierPath(ovalIn: dotRect).fill()
                return
            }
            
            // Calculate bounds
            let lats = tracker.routeCoordinates.map { $0.latitude }
            let lons = tracker.routeCoordinates.map { $0.longitude }
            guard let minLat = lats.min(), let maxLat = lats.max(),
                  let minLon = lons.min(), let maxLon = lons.max() else { return }
            
            let latRange = maxLat - minLat
            let lonRange = maxLon - minLon
            
            // Check if movement is very small (< ~10m radius)
            let isVerySmallMovement = latRange < 0.0001 && lonRange < 0.0001
            
            if isVerySmallMovement {
                // Draw a dot for very small movement
                let dotSize: CGFloat = 20
                let dotRect = CGRect(x: (size.width - dotSize) / 2, y: (size.height - dotSize) / 2, width: dotSize, height: dotSize)
                UIColor(red: 0xA9/255.0, green: 0xE4/255.0, blue: 0xFF/255.0, alpha: 1.0).setFill()
                UIBezierPath(ovalIn: dotRect).fill()
                return
            }
            
            // Add padding
            let padding: CGFloat = 32
            let drawWidth = size.width - padding * 2
            let drawHeight = size.height - padding * 2
            
            let latRangeSafe = max(latRange, 0.0001)
            let lonRangeSafe = max(lonRange, 0.0001)
            
            // Create path from actual route coordinates and collect endpoints
            let path = UIBezierPath()
            var firstPoint: CGPoint? = nil
            var lastPoint: CGPoint? = nil
            for (index, coord) in tracker.routeCoordinates.enumerated() {
                let x = CGFloat((coord.longitude - minLon) / lonRangeSafe) * drawWidth + padding
                let y = CGFloat(1.0 - (coord.latitude - minLat) / latRangeSafe) * drawHeight + padding  // Invert Y for north-up
                let point = CGPoint(x: x, y: y)
                if index == 0 {
                    path.move(to: point)
                    firstPoint = point
                } else {
                    path.addLine(to: point)
                }
                lastPoint = point
            }

            // Stroke with gradient (A9E4FF → 1191E6)
            let cg = ctx.cgContext
            cg.saveGState()
            cg.addPath(path.cgPath)
            cg.setLineWidth(12)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.replacePathWithStrokedPath()
            cg.clip()
            let colors = [
                UIColor(red: 0xA9/255.0, green: 0xE4/255.0, blue: 0xFF/255.0, alpha: 1.0).cgColor,
                UIColor(red: 0x11/255.0, green: 0x91/255.0, blue: 0xE6/255.0, alpha: 1.0).cgColor
            ] as CFArray
            let locations: [CGFloat] = [0, 1]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
                let start = firstPoint ?? CGPoint(x: padding, y: padding)
                let end = lastPoint ?? CGPoint(x: size.width - padding, y: size.height - padding)
                cg.drawLinearGradient(gradient, start: start, end: end, options: [])
            }
            cg.restoreGState()
        }
    }

    private func renderProfileSelfie(diameter: CGFloat = 200) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter), format: format)
        return renderer.image { ctx in
            let rect = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            
            // 1) Draw neon circle background with shadow
            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 0), blur: 6, color: UIColor.black.withAlphaComponent(0.25).cgColor)
            UIColor(red: 0xB8/255.0, green: 0xFF/255.0, blue: 0x1B/255.0, alpha: 1.0).setFill()
            let circlePath = UIBezierPath(ovalIn: rect)
            circlePath.fill()
            
            // 2) Draw white stroke
            ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor.white.setStroke()
            circlePath.lineWidth = 2
            circlePath.stroke()
            
            // 3) Load GIF first frame and apply AspectPreservingGIF clip shape
            if let url = account.profileGIFURL ?? account.pendingSelfieGIFToAdd,
               let data = try? Data(contentsOf: url),
               let src = CGImageSourceCreateWithData(data as CFData, nil),
               let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                
                // Apply the AspectPreservingGIF clip shape (rounded bottom, straight top)
                let gifWidth = diameter - 3
                let gifRect = CGRect(x: 1.5, y: 1.5, width: gifWidth, height: gifWidth)
                let cornerRadius = gifWidth / 2
                
                ctx.cgContext.saveGState()
                let clipPath = UIBezierPath()
                clipPath.move(to: CGPoint(x: gifRect.minX + 8, y: gifRect.minY))
                clipPath.addLine(to: CGPoint(x: gifRect.maxX - 8, y: gifRect.minY))
                clipPath.addQuadCurve(to: CGPoint(x: gifRect.maxX, y: gifRect.minY + 8), controlPoint: CGPoint(x: gifRect.maxX, y: gifRect.minY))
                clipPath.addLine(to: CGPoint(x: gifRect.maxX, y: gifRect.maxY - cornerRadius))
                clipPath.addQuadCurve(to: CGPoint(x: gifRect.maxX - cornerRadius, y: gifRect.maxY), controlPoint: CGPoint(x: gifRect.maxX, y: gifRect.maxY))
                clipPath.addLine(to: CGPoint(x: gifRect.minX + cornerRadius, y: gifRect.maxY))
                clipPath.addQuadCurve(to: CGPoint(x: gifRect.minX, y: gifRect.maxY - cornerRadius), controlPoint: CGPoint(x: gifRect.minX, y: gifRect.maxY))
                clipPath.addLine(to: CGPoint(x: gifRect.minX, y: gifRect.minY + 8))
                clipPath.addQuadCurve(to: CGPoint(x: gifRect.minX + 8, y: gifRect.minY), controlPoint: CGPoint(x: gifRect.minX, y: gifRect.minY))
                clipPath.close()
                clipPath.addClip()
                
                UIImage(cgImage: cg).draw(in: gifRect)
                ctx.cgContext.restoreGState()
            }
        }
    }

    private func buildStatsMultilineText() -> String {
        let timeString: String = {
            let h = tracker.elapsedSeconds / 3600
            let m = (tracker.elapsedSeconds % 3600) / 60
            let s = tracker.elapsedSeconds % 60
            if h > 0 { return String(format: "%02d:%02d:%02d", h, m, s) }
            return String(format: "%02d:%02d", m, s)
        }()
        let distanceString = String(format: "%.2f km", tracker.distanceMeters / 1000.0)
        let km = tracker.distanceMeters / 1000.0
        let paceString: String = {
            guard km > 0.01 else { return "--'-- /km" }
            let secPerKm = Double(tracker.elapsedSeconds) / km
            let m = Int(secPerKm) / 60
            let s = Int(secPerKm) % 60
            return String(format: "%02d:%02d /km", m, s)
        }()
        // Just show values without labels
        return "\(distanceString)\n\(paceString)\n\(timeString)"
    }
}

// MARK: - Shake effect for banner
private struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amount * sin(animatableData * .pi * shakesPerUnit * 2)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

// MARK: - Stats Sheet
private struct RunStatsSheet: View {
    let elapsed: Int
    let distanceMeters: Double
    let isRunning: Bool
    let isPaused: Bool
    let currentPace: String
    let cadenceSpm: Double
    let steps: Int
    let elevationGain: Double
    let locationAuthorized: Bool
    let onStart: () -> Void
    let onPauseToggle: () -> Void
    let onResume: () -> Void
    let onFinish: () -> Void

    private var timeString: String {
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        if h > 0 { return String(format: "%02d:%02d:%02d", h, m, s) }
        // When hours are zero, show single-digit minutes (e.g., 0:07 instead of 00:07)
        return String(format: "%d:%02d", m, s)
    }

    private var distanceString: String {
        String(format: "%.2f", distanceMeters / 1000.0)  // Removed " km"
    }

    private var paceString: String {
        let km = distanceMeters / 1000.0
        // Return 00:00 for very small distances or when not started
        guard km >= 0.05 else { return "00:00" }  // Increased threshold from 0.01 to 0.05 (50 meters)
        let secPerKm = Double(elapsed) / km
        // Cap pace at 99:59 to avoid unrealistic values
        let cappedSecPerKm = min(secPerKm, 5999) // 99 minutes 59 seconds
        let m = Int(cappedSecPerKm) / 60
        let s = Int(cappedSecPerKm) % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            if isRunning {
                if isPaused {
                    // Paused: center three rows (2 cols each) between top and buttons
                    Spacer(minLength: 0)
                    VStack(spacing: 24) {
                        // Row 1: Time, Avg Pace
                        HStack(spacing: 8) {
                            statBlock(title: "Time", value: timeString, valueSize: 32)
                            statBlock(title: "Avg Pace (/km)", value: paceString, valueSize: 32)
                        }
                        // Row 2: Distance, Cadence
                        HStack(spacing: 8) {
                            statBlock(title: "Distance (km)", value: distanceString, valueSize: 32)
                            statBlock(title: "Cadence (spm)", value: String(format: "%d", Int(cadenceSpm.rounded())), valueSize: 32)
                        }
                        // Row 3: Steps, Max Elevation
                        HStack(spacing: 8) {
                            statBlock(title: "Steps", value: String(steps), valueSize: 32)
                            statBlock(title: "Elevation Gain (m)", value: String(format: "%.0f", elevationGain), valueSize: 32)
                        }
                    }
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity, alignment: .center)
                } else {
                // Vertical layout when running
                VStack(spacing: 32) {
                    // Time
                    VStack(spacing: 8) {
                        Text("Time")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.gray)
                        Text(timeString)
                            .font(.system(size: 36, weight: .bold))  // Reduced from 42 to 36
                            .foregroundColor(.black)
                    }
                    
                    // Pace (current while running)
                    VStack(spacing: 8) {
                        Text("Current Pace (/km)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.gray)
                        Text(currentPace)
                            .font(.system(size: 64, weight: .bold))  // Increased from 56 to 64
                            .foregroundColor(.black)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                    
                    // Distance
                    VStack(spacing: 8) {
                        Text("Distance (km)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.gray)
                        HStack(spacing: 4) {
                            Text(distanceString)
                                .font(.system(size: 36, weight: .bold))  // Reduced from 42 to 36
                                .foregroundColor(.black)
                        }
                    }
                }
                .padding(.top, 48)
                }
            } else {
                // Horizontal layout when not started
                VStack(spacing: 8) {
                    // Labels row
                    HStack(spacing: 24) {
                        Text("Time")
                            .font(.system(size: 12, weight: .semibold))  // Reduced from 14 to 12
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                        Text("Pace (/km)")
                            .font(.system(size: 12, weight: .semibold))  // Reduced from 14 to 12
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                        Text("Distance (km)")
                            .font(.system(size: 12, weight: .semibold))  // Reduced from 14 to 12
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                    }
                    
                    // Values row
                    HStack(spacing: 24) {
                        Text(timeString)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                        Text(paceString)
                            .font(.system(size: 36, weight: .bold))  // Increased from 32 to 36
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .minimumScaleFactor(0.5)  // Allow text to scale down to fit
                            .lineLimit(1)  // Keep on one line
                        Text(distanceString)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 36)  // Changed from 16 to 36
                .padding(.horizontal, 24)  // Added horizontal padding
            }
            Spacer()
            
            // Button layout based on running state
            if !isRunning {
                // Not started - show Start button
                Button(action: onStart) {
                    Text("Start")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(locationAuthorized ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(locationAuthorized ? Color.neon : Color(.systemGray4))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!locationAuthorized)
                .padding(.horizontal, 20)
                .padding(.bottom, 36)  // Changed from 16 to 36
            } else if !isPaused {
                // Running - show Pause button
                Button(action: onPauseToggle) {
                    HStack(spacing: 8) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Pause")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(Color.black)  // Changed to black
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 36)  // Changed from 16 to 36
            } else {
                // Paused - show Resume and Finish buttons
                HStack(spacing: 12) {
                    Button(action: onResume) {
                        Text("Resume")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(Color(white: 0.95))
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onFinish) {
                        Text("Finish")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(Color.neon)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)  // Changed from 16 to 36
            }
        }
    }

    private func statBlock(title: String, value: String, valueSize: CGFloat = 28) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundColor(.gray)
            Text(value).font(.system(size: valueSize, weight: .bold)).foregroundColor(.black)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Tracking
final class RunTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let motionManager = CMMotionActivityManager()
    private let pedometer = CMPedometer()
    private let altimeter = CMAltimeter()
    
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var distanceMeters: Double = 0
    @Published var elapsedSeconds: Int = 0
    @Published var latestCoordinate: CLLocationCoordinate2D? = nil
    @Published var stepCount: Int = 0
    @Published var cadence: Double = 0  // steps per minute
    @Published var floorsAscended: Int = 0
    @Published var floorsDescended: Int = 0
    // Current pace in minutes per kilometer (nil if unavailable)
    @Published var currentPaceMinPerKm: Double? = nil
    // Elevation gain/loss (meters) from altimeter
    @Published var elevationGainMeters: Double = 0
    @Published var elevationLossMeters: Double = 0
    // Max elevation relative to start (meters)
    @Published var maxElevationMeters: Double = 0

    private var lastLocation: CLLocation? = nil
    private var timer: Timer?
    private var startDate: Date?
    
    // Live Activity support
    private var currentActivity: Activity<RunActivityAttributes>?
    private var latestPlaceLine: String? = nil
    private var lastGeocodeDate: Date? = nil
    private var lastGeocodedCoordinate: CLLocationCoordinate2D? = nil
    
    // Motion & Fitness tracking
    private var pedometerStartDate: Date?
    private var recentLocationsForPace: [CLLocation] = []
    private var lastRelativeAltitude: Double? = nil
    private var lastStepChangeAt: Date? = nil
    private var lastReportedStepCount: Int = 0
    private var pedometerActive: Bool = false
    private var isMotionStationary: Bool = false
    private var lastRouteAppendAt: Date? = nil

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        
        // Configure background behavior safely (avoid crash if app isn't backgroundable)
        manager.pausesLocationUpdatesAutomatically = false
        configureBackgroundLocationBehavior()
        
        if CLLocationManager.authorizationStatus() == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        
        // Request Motion & Fitness permission
        requestMotionPermission()
    }
    
    private func requestMotionPermission() {
        // Check if motion tracking is available
        guard CMPedometer.isStepCountingAvailable() else {
            print("⚠️ Step counting not available on this device")
            return
        }
        
        // Request permission by starting pedometer (permission will be requested automatically)
        print("📱 Motion & Fitness permission will be requested when run starts")
    }

    // Only allow background location if app has UIBackgroundModes: location AND Always auth granted
    private func appSupportsBackgroundLocation() -> Bool {
        if let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] {
            return modes.contains("location")
        }
        return false
    }

    private func configureBackgroundLocationBehavior() {
        let status = CLLocationManager.authorizationStatus()
        let canBackground = appSupportsBackgroundLocation() && status == .authorizedAlways
        if manager.responds(to: #selector(getter: CLLocationManager.allowsBackgroundLocationUpdates)) {
            manager.allowsBackgroundLocationUpdates = canBackground
        }
        if #available(iOS 11.0, *) {
            manager.showsBackgroundLocationIndicator = canBackground
        }
    }

    func start() {
        routeCoordinates.removeAll()
        distanceMeters = 0
        elapsedSeconds = 0
        stepCount = 0
        cadence = 0
        floorsAscended = 0
        floorsDescended = 0
        lastLocation = nil
        startDate = Date()
        pedometerStartDate = Date()
        
        // Start location tracking
        // Re-evaluate background flags right before starting updates to avoid CoreLocation assertion
        configureBackgroundLocationBehavior()
        manager.startUpdatingLocation()
        
        // Start pedometer tracking
        startPedometerTracking()
        // Start altimeter tracking
        startAltimeterTracking()
        // Start motion activity for stationary detection
        if CMMotionActivityManager.isActivityAvailable() {
            motionManager.startActivityUpdates(to: .main) { [weak self] activity in
                guard let self = self else { return }
                self.isMotionStationary = (activity?.stationary ?? false)
            }
        }
        
        // Start timer
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let start = self.startDate else { return }
            self.elapsedSeconds = Int(Date().timeIntervalSince(start))
            self.updateLiveActivity()  // Update Live Activity every second
        }
        
        // Start Live Activity
        if #available(iOS 16.1, *) {
            startLiveActivity()
        }
    }
    
    private func startPedometerTracking() {
        guard CMPedometer.isStepCountingAvailable() else {
            print("⚠️ Step counting not available")
            return
        }
        
        guard let startDate = pedometerStartDate else { return }
        
        pedometer.startUpdates(from: startDate) { [weak self] pedometerData, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Pedometer error: \(error.localizedDescription)")
                return
            }
            
            guard let data = pedometerData else { return }
            
            DispatchQueue.main.async {
                // Mark pedometer as active once we receive any data
                self.pedometerActive = true
                // Update step count
                if let steps = data.numberOfSteps as? Int {
                    if steps != self.lastReportedStepCount {
                        self.lastReportedStepCount = steps
                        self.lastStepChangeAt = Date()
                    } else if self.lastStepChangeAt == nil {
                        self.lastStepChangeAt = Date()
                    }
                    self.stepCount = steps
                }
                
                // Update cadence (steps per minute)
                if let cadence = data.currentCadence as? Double {
                    self.cadence = cadence * 60.0  // Convert to steps per minute
                }
                
                // Update floors
                if let floorsUp = data.floorsAscended as? Int {
                    self.floorsAscended = floorsUp
                }
                if let floorsDown = data.floorsDescended as? Int {
                    self.floorsDescended = floorsDown
                }
                
                // Use pedometer distance if available (more accurate than GPS for running)
                if let pedometerDistance = data.distance as? Double {
                    // Blend GPS and pedometer distance for best accuracy
                    // Pedometer is more accurate for steps, GPS is better for overall route
                    self.distanceMeters = max(self.distanceMeters, pedometerDistance)
                }
                // Current pace (seconds per meter) → minutes per km
                if let secPerMeter = data.currentPace?.doubleValue, secPerMeter > 0 {
                    let minPerKm = secPerMeter * 1000.0 / 60.0
                    if minPerKm.isFinite, minPerKm > 0, minPerKm < 20 {
                        self.currentPaceMinPerKm = minPerKm
                    }
                }
                
                print("🏃 Steps: \(self.stepCount), Cadence: \(Int(self.cadence)) spm, Distance: \(self.distanceMeters)m")
            }
        }
    }

    // React to authorization changes to toggle background behavior safely
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        configureBackgroundLocationBehavior()
        let status = manager.authorizationStatus
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
        }
    }

    // MARK: - Altimeter (Relative elevation gain/loss)
    private func startAltimeterTracking() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        lastRelativeAltitude = nil
        elevationGainMeters = 0
        elevationLossMeters = 0
        maxElevationMeters = 0
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            guard let self = self, error == nil, let rel = data?.relativeAltitude.doubleValue else { return }
            if let last = self.lastRelativeAltitude {
                let delta = rel - last
                if delta > 0 { self.elevationGainMeters += delta }
                if delta < 0 { self.elevationLossMeters += -delta }
            }
            // Track maximum relative altitude reached during this session
            if rel > self.maxElevationMeters { self.maxElevationMeters = rel }
            self.lastRelativeAltitude = rel
        }
    }

    private func stopAltimeterTracking() {
        altimeter.stopRelativeAltitudeUpdates()
    }

    func stop() {
        // Ensure we capture the final position in the route before stopping
        if let latest = latestCoordinate {
            if let lastCoord = routeCoordinates.last {
                let lastCL = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
                let gap = CLLocation(latitude: latest.latitude, longitude: latest.longitude).distance(from: lastCL)
                if gap >= 3 {
                    routeCoordinates.append(latest)
                }
            } else {
                routeCoordinates.append(latest)
            }
        }

        manager.stopUpdatingLocation()
        pedometer.stopUpdates()
        pedometerActive = false
        stopAltimeterTracking()
        if CMMotionActivityManager.isActivityAvailable() {
            motionManager.stopActivityUpdates()
        }
        timer?.invalidate()
        timer = nil
        
        // End Live Activity
        endLiveActivity()
    }

    func pause() {
        manager.stopUpdatingLocation()
        pedometer.stopUpdates()
        pedometerActive = false
        stopAltimeterTracking()
        if CMMotionActivityManager.isActivityAvailable() {
            motionManager.stopActivityUpdates()
        }
        timer?.invalidate()
        timer = nil
        
        // Update Live Activity to paused state
        updateLiveActivity(isPaused: true)
    }

    func resume() {
        manager.startUpdatingLocation()
        
        // Resume pedometer from current state
        if let startDate = pedometerStartDate {
            startPedometerTracking()
        }
        startAltimeterTracking()
        
        guard let start = startDate else { startDate = Date(); return }
        // Adjust startDate so elapsed continues from previous value
        let already = elapsedSeconds
        startDate = Date(timeIntervalSinceNow: -TimeInterval(already))
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let start = self.startDate else { return }
            self.elapsedSeconds = Int(Date().timeIntervalSince(start))
            self.updateLiveActivity()  // Update Live Activity every second
        }
        
        // Update Live Activity to running state
        updateLiveActivity(isPaused: false)
    }

    // Allow external restore to set the internal start date based on known elapsed seconds
    func setStartDateForResume(elapsedSeconds: Int) {
        self.startDate = Date(timeIntervalSinceNow: -TimeInterval(elapsedSeconds))
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        latestCoordinate = loc.coordinate
        // Accumulate distance conservatively using previous GPS sample (keeps anti-drift behavior)
        if let prev = lastLocation {
            let step = loc.distance(from: prev)
            let goodAccuracy = (loc.horizontalAccuracy > 0 && prev.horizontalAccuracy > 0 && loc.horizontalAccuracy <= 25 && prev.horizontalAccuracy <= 25)
            let minStepThreshold = max(5.0, (loc.horizontalAccuracy + prev.horizontalAccuracy) / 2.0)
            let noRecentSteps = {
                guard let t = self.lastStepChangeAt else { return true }
                return Date().timeIntervalSince(t) > 3.0
            }()
            let veryLowCadence = self.cadence < 3.0
            let canTrustStationary = self.pedometerActive || CMMotionActivityManager.isActivityAvailable()
            let stationary = canTrustStationary && (self.isMotionStationary || (noRecentSteps && veryLowCadence))
            let speedOk = (loc.speed > 0.5) || !loc.speed.isFinite
            if !stationary && goodAccuracy && step >= minStepThreshold && step < 100 && speedOk {
                distanceMeters += step
                updateLiveActivity()  // Update when distance changes
            }
        }

        // Sample route polyline more permissively using last appended point
        let now = Date()
        let accuracyOkForRoute = (loc.horizontalAccuracy > 0 && loc.horizontalAccuracy <= 50)
        if let lastCoord = routeCoordinates.last {
            let lastCL = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
            let gap = loc.distance(from: lastCL)
            let timeSince = lastRouteAppendAt.map { now.timeIntervalSince($0) } ?? .greatestFiniteMagnitude
            // Append if moved ≥3m with OK accuracy, or at least every 10s with OK accuracy
            if (accuracyOkForRoute && gap >= 3) || (accuracyOkForRoute && timeSince >= 10) {
                routeCoordinates.append(loc.coordinate)
                lastRouteAppendAt = now
            }
        } else {
            // First point
            routeCoordinates.append(loc.coordinate)
            lastRouteAppendAt = now
        }
        lastLocation = loc

        // Update place line occasionally
        maybeReverseGeocode(for: loc)

        // Maintain short window for GPS-derived current pace (~12s)
        do {
            let goodAccuracy = (loc.horizontalAccuracy > 0 && loc.horizontalAccuracy <= 25)
            let noRecentSteps = {
                guard let t = self.lastStepChangeAt else { return true }
                return Date().timeIntervalSince(t) > 3.0
            }()
            let veryLowCadence = self.cadence < 3.0
            let canTrustStationary = self.pedometerActive || CMMotionActivityManager.isActivityAvailable()
            let stationary = canTrustStationary && (self.isMotionStationary || (noRecentSteps && veryLowCadence))
            if !stationary && goodAccuracy {
                recentLocationsForPace.append(loc)
            }
        }
        let cutoff = Date().addingTimeInterval(-12)
        recentLocationsForPace.removeAll { $0.timestamp < cutoff }
        if let first = recentLocationsForPace.first {
            let dt = loc.timestamp.timeIntervalSince(first.timestamp)
            let dist = loc.distance(from: first)
            if dt > 3, dist > 5 {
                let pace = (dt / 60.0) / (dist / 1000.0) // minutes per km
                if pace.isFinite, pace > 0, pace < 20 {
                    currentPaceMinPerKm = pace
                }
            }
        }
    }
    
    // MARK: - Live Activity Management
    
    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("❌ Live Activities are not enabled")
            return
        }
        
        print("🔵 Starting Live Activity...")
        print("🔵 ActivityKit version available: \(ActivityAuthorizationInfo().areActivitiesEnabled)")
        
        let attributes = RunActivityAttributes(startTime: Date())
        let contentState = RunActivityAttributes.ContentState(
            elapsedTime: 0,
            distanceMeters: 0,
            paceMinPerKm: 0,
            currentPaceMinPerKm: 0,
            isRunning: true,
            placeLine: latestPlaceLine
        )
        
        print("🔵 Created attributes: startTime=\(attributes.startTime)")
        print("🔵 Created contentState: \(contentState)")
        
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(
                    state: contentState,
                    staleDate: Date().addingTimeInterval(60),
                    relevanceScore: 100
                ),
                pushType: nil
            )
            currentActivity = activity
            
            print("✅ Live Activity started successfully!")
            print("✅ Activity ID: \(activity.id)")
            print("✅ Activity state: \(activity.activityState)")
            print("✅ Activity content: \(activity.content)")
            
            // Enable frequent updates for real-time tracking
            Task {
                for await _ in activity.activityStateUpdates {
                    // Activity state changed
                    print("🔄 Activity state updated: \(activity.activityState)")
                }
            }
            
            print("✅ Frequent updates enabled for real-time tracking")
        } catch {
            print("❌ Failed to start Live Activity: \(error)")
            print("❌ Error type: \(type(of: error))")
            print("❌ Error localized description: \(error.localizedDescription)")
        }
    }
    
    private func updateLiveActivity(isPaused: Bool = false) {
        guard let activity = currentActivity else { return }
        
        // Compute current pace and average pace separately
        let currentPaceValue: Double = {
            if let cur = currentPaceMinPerKm, cur.isFinite, cur > 0 { return cur }
            return 0
        }()
        let avgPaceValue: Double = {
            guard distanceMeters > 0 && elapsedSeconds > 0 else { return 0 }
            let distanceKm = distanceMeters / 1000.0
            let timeMin = Double(elapsedSeconds) / 60.0
            return timeMin / distanceKm
        }()
        
        let contentState = RunActivityAttributes.ContentState(
            elapsedTime: elapsedSeconds,
            distanceMeters: distanceMeters,
            paceMinPerKm: avgPaceValue,
            currentPaceMinPerKm: currentPaceValue,
            isRunning: !isPaused,
            placeLine: latestPlaceLine
        )
        
        Task {
            await activity.update(
                ActivityContent(
                    state: contentState,
                    staleDate: Date().addingTimeInterval(60),
                    relevanceScore: isPaused ? 60 : 100
                ),
                alertConfiguration: nil
            )
        }
    }

    // MARK: - Reverse Geocoding for "Neighborhood, City"
    private func maybeReverseGeocode(for location: CLLocation) {
        let now = Date()
        if let lastTime = lastGeocodeDate, now.timeIntervalSince(lastTime) < 60 { return }
        if let lastCoord = lastGeocodedCoordinate {
            let lastLoc = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
            if location.distance(from: lastLoc) < 100 { return }
        }
        lastGeocodeDate = now
        lastGeocodedCoordinate = location.coordinate
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self else { return }
            if let pm = placemarks?.first {
                var parts: [String] = []
                if let nb = pm.subLocality, !nb.isEmpty { parts.append(nb) }
                if let city = pm.locality, !city.isEmpty {
                    parts.append(city)
                } else if let admin = pm.administrativeArea, !admin.isEmpty {
                    parts.append(admin)
                }
                let line = parts.isEmpty ? (pm.name ?? "") : parts.joined(separator: ", ")
                DispatchQueue.main.async {
                    self.latestPlaceLine = line.isEmpty ? nil : line
                    // Push a lightweight update to Live Activity with the new place
                    self.updateLiveActivity()
                }
            }
        }
    }
    
    func endLiveActivity() {
        guard let activity = currentActivity else { return }
        
        Task {
            // Show final state briefly with relevance 0 before dismissing
            await activity.end(
                .init(
                    state: activity.content.state,
                    staleDate: Date().addingTimeInterval(60),
                    relevanceScore: 0
                ),
                dismissalPolicy: .after(.now + 3)
            )
            print("✅ Live Activity ended")
        }
        
        currentActivity = nil
    }
}

// MARK: - MKMapView wrapper
private struct RunMKMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var route: [CLLocationCoordinate2D]
    var userCoordinate: CLLocationCoordinate2D?
    var followUser: Bool
    var profileGIFURL: URL?
    var isRunning: Bool
    var currentPace: String

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.mapType = .standard
        map.isRotateEnabled = true
        map.showsUserLocation = false  // Disable default blue dot
        map.setRegion(region, animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Update region if changed (only update if there's a significant difference)
        let latDiff = abs(map.region.center.latitude - region.center.latitude)
        let lonDiff = abs(map.region.center.longitude - region.center.longitude)
        if latDiff > 0.00001 || lonDiff > 0.00001 {
            map.setRegion(region, animated: true)
        }
        
        // Update route overlay
        let existing = map.overlays
        let polylines = existing.compactMap { $0 as? MKPolyline }
        if !polylines.isEmpty { map.removeOverlays(polylines) }
        if route.count >= 2 {
            let poly = MKPolyline(coordinates: route, count: route.count)
            map.addOverlay(poly)
        }
        
        // Update custom user location annotation
        context.coordinator.updateUserLocation(map: map, coordinate: userCoordinate, gifURL: profileGIFURL, isRunning: isRunning, pace: currentPace)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var userLocationAnnotation: MyLocationPulseAnnotation?
        
        func updateUserLocation(map: MKMapView, coordinate: CLLocationCoordinate2D?, gifURL: URL?, isRunning: Bool, pace: String) {
            if let coord = coordinate {
                if let existing = userLocationAnnotation {
                    // Update existing annotation position and pace
                    existing.coordinate = coord
                    existing.isRunning = isRunning
                    existing.pace = pace
                    // Update the view if it exists
                    if let view = map.view(for: existing) as? MyLocationPulseAnnotationView {
                        view.updatePace(pace: pace, isRunning: isRunning)
                    }
                } else {
                    // Create new annotation with profile URL
                    let profileURLString = gifURL?.absoluteString
                    let annotation = MyLocationPulseAnnotation(coordinate: coord, profileURLString: profileURLString, fallbackGIFURL: gifURL, isRunning: isRunning, pace: pace)
                    userLocationAnnotation = annotation
                    map.addAnnotation(annotation)
                    
                    // Trigger animation after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let view = map.view(for: annotation) as? MyLocationPulseAnnotationView {
                            view.animateIn()
                        }
                    }
                }
            } else if let existing = userLocationAnnotation {
                // Remove annotation if no coordinate
                map.removeAnnotation(existing)
                userLocationAnnotation = nil
            }
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let userAnnotation = annotation as? MyLocationPulseAnnotation {
                let identifier = "MyLocationPulse"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MyLocationPulseAnnotationView
                    ?? MyLocationPulseAnnotationView(annotation: userAnnotation, reuseIdentifier: identifier)
                view.configure(with: userAnnotation)
                return view
            }
            return nil
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let poly = overlay as? MKPolyline {
                // Gradient route renderer from #A9E4FF to #1191E6
                let renderer = GradientPolylineRenderer(polyline: poly,
                                                        startColor: UIColor(red: 0xA9/255.0, green: 0xE4/255.0, blue: 0xFF/255.0, alpha: 1.0),
                                                        endColor: UIColor(red: 0x11/255.0, green: 0x91/255.0, blue: 0xE6/255.0, alpha: 1.0))
                renderer.lineWidth = 6
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - My Location Pulse Annotation (from MapView)
private class MyLocationPulseAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let profileURLString: String?
    let fallbackGIFURL: URL?
    var isRunning: Bool
    var pace: String
    
    init(coordinate: CLLocationCoordinate2D, profileURLString: String?, fallbackGIFURL: URL?, isRunning: Bool, pace: String) {
        self.coordinate = coordinate
        self.profileURLString = profileURLString
        self.fallbackGIFURL = fallbackGIFURL
        self.isRunning = isRunning
        self.pace = pace
        super.init()
    }
}

private class MyLocationPulseAnnotationView: MKAnnotationView, WKNavigationDelegate, WKScriptMessageHandler {
    private let container = UIView()
    private let webContainer = UIView()
    private var webView: WKWebView?
    private var messageController: WKUserContentController?
    private var hostingController: UIHostingController<AnyView>? = nil
    private let stickerInset: CGFloat = 1.5
    private let stickerHeightMultiplier: CGFloat = 1.8
    private var didAnimateIn: Bool = false
    private var isContentLoaded: Bool = false
    private var didRunContainerAppearAnimation: Bool = false
    private var shouldAnimateContainerOnLoad: Bool = false
    private var lastAppliedHeight: CGFloat = 0  // Track last applied height to prevent duplicate calls
    
    // Pace banner
    private let paceBanner = UIView()
    private let paceLabel = UILabel()
    
    // Font registration
    private static var didRegisterExqFont = false
    
    private static func registerExqFontIfNeeded() {
        guard !didRegisterExqFont else { return }
        didRegisterExqFont = true
        
        guard let fontPath = Bundle.main.path(forResource: "exqt", ofType: "ttf"),
              let fontURL = URL(string: "file://\(fontPath)"),
              let dataProvider = CGDataProvider(url: fontURL as CFURL),
              let font = CGFont(dataProvider) else {
            print("❌ Failed to load exqt font")
            return
        }
        
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterGraphicsFont(font, &error) {
            print("✅ Registered exqt font")
        } else {
            print("⚠️ Font already registered or error: \(error.debugDescription)")
        }
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
        
        // Listen for aspect ratio updates from AspectPreservingGIFView
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAspectRatioUpdate),
            name: NSNotification.Name("AspectRatioUpdated"),
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleAspectRatioUpdate(notification: Notification) {
        DispatchQueue.main.async {
            if let actualHeight = notification.userInfo?["actualHeight"] as? CGFloat {
                // Prevent duplicate layout calls
                if self.lastAppliedHeight != actualHeight {
                    self.lastAppliedHeight = actualHeight
                    self.applyStickerLayoutWithHeight(actualHeight)
                }
            } else {
                self.applyStickerLayout()
            }
        }
    }
    
    private func applyStickerLayoutWithHeight(_ imageHeight: CGFloat) {
        let size = container.bounds.width  // Container size is always 40
        guard size > 0 else { return }
        
        let maxAllowedHeight = size * 3.0
        let stickerHeight = min(imageHeight, maxAllowedHeight)
        let stickerWidth = size
        let originX: CGFloat = 0
        let originY = size - stickerHeight
        
        // CRITICAL: Keep container at 40x40 (for the circle)
        // Only adjust annotation view bounds for proper positioning
        let newBoundsHeight = max(stickerHeight, size)
        self.bounds = CGRect(x: 0, y: 0, width: size, height: newBoundsHeight)
        
        // centerOffset: Keep circle (at container bottom = y:40) at the coordinate point
        // annotation view center is at bounds.height/2
        // We want: center + centerOffset.y = 40
        // So: centerOffset.y = 40 - bounds.height/2
        self.centerOffset = CGPoint(x: 0, y: size - newBoundsHeight / 2)
        
        // CRITICAL: Force MapKit to recalculate frame immediately
        self.setNeedsLayout()
        self.superview?.layoutIfNeeded()
        
        webContainer.frame = CGRect(x: originX, y: originY, width: stickerWidth, height: stickerHeight)
        webView?.frame = webContainer.bounds
        
        if let hcView = hostingController?.view {
            UIView.performWithoutAnimation {
                hcView.frame = webContainer.bounds
                hcView.layoutIfNeeded()
            }
        }
        
        applyUnevenMask(to: webContainer, topRadius: 8, bottomRadius: size / 2.0)
        
        // Ensure consistent visual state (no animation)
        container.alpha = 1.0
        webContainer.alpha = 1.0
        container.transform = .identity
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isUserInteractionEnabled = false
        canShowCallout = false
        clipsToBounds = false
        
        // Register Exq font if needed
        Self.registerExqFontIfNeeded()
        
        let size: CGFloat = 40
        container.frame = CGRect(x: 0, y: 0, width: size, height: size)
        container.backgroundColor = .clear
        container.clipsToBounds = false
        // Show immediately (no animation)
        container.alpha = 1.0
        container.transform = .identity

        let circle = UIView(frame: container.bounds)
        circle.backgroundColor = UIColor(red: 0x5C/255.0, green: 0xBA/255.0, blue: 0xF2/255.0, alpha: 1.0)  // Changed from iosBlue to #5CBAF2
        circle.layer.cornerRadius = size / 2
        circle.layer.masksToBounds = true
        circle.layer.shadowColor = UIColor.black.cgColor
        circle.layer.shadowOpacity = 0.25
        circle.layer.shadowRadius = 8
        container.addSubview(circle)

        // Outer white stroke: draw outside the blue circle with 3pt thickness
        let stroke = UIView(frame: container.bounds.insetBy(dx: -3, dy: -3))
        stroke.backgroundColor = .clear
        stroke.layer.cornerRadius = (size / 2) + 3
        stroke.layer.borderColor = UIColor.white.cgColor
        stroke.layer.borderWidth = 3
        // Add subtle shadow behind the white stroke
        stroke.layer.masksToBounds = false
        stroke.layer.shadowColor = UIColor.black.cgColor
        stroke.layer.shadowOpacity = 0.22
        stroke.layer.shadowRadius = 6
        stroke.layer.shadowOffset = CGSize(width: 0, height: 2)
        stroke.layer.shadowPath = UIBezierPath(roundedRect: stroke.bounds, cornerRadius: stroke.layer.cornerRadius).cgPath
        container.addSubview(stroke)

        webContainer.frame = .zero
        webContainer.layer.masksToBounds = false  // CRITICAL: Allow overflow for negative originY
        container.addSubview(webContainer)
        webContainer.alpha = 1.0  // Show immediately
        
        // Setup pace banner
        paceBanner.backgroundColor = UIColor(Color.neon)
        paceBanner.layer.cornerRadius = 8
        paceBanner.alpha = 0  // Hidden by default
        
        // Try both "Exq" and fallback to "exqt" at the same size
        if let exqFont = UIFont(name: "Exq", size: 14) {
            paceLabel.font = exqFont
        } else if let exqtFont = UIFont(name: "exqt", size: 14) {
            paceLabel.font = exqtFont
        } else {
            print("⚠️ Exq font not found, using system font. Available fonts: \(UIFont.familyNames)")
            paceLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        }
        paceLabel.textColor = .black
        paceLabel.textAlignment = .center
        paceBanner.addSubview(paceLabel)

        addSubview(container)
        addSubview(paceBanner)
        
        // CRITICAL: Set bounds large enough to accommodate sticker that extends upward
        // Do NOT set frame - MapKit manages it automatically
        let initialHeight = size * 2.5
        bounds = CGRect(x: 0, y: 0, width: size, height: initialHeight)
        // Keep circle bottom (y=40) at coordinate point
        centerOffset = CGPoint(x: 0, y: size - initialHeight / 2)
        
        displayPriority = .required
        zPriority = .max
    }
    
    func updatePace(pace: String, isRunning: Bool) {
        paceLabel.text = pace
        
        // Size the label to fit content
        paceLabel.sizeToFit()
        let bannerWidth = paceLabel.frame.width + 16  // Add padding
        let bannerHeight: CGFloat = 22
        
        // Position banner to overlay the bottom of the pulse circle
        let size = container.bounds.width
        paceBanner.frame = CGRect(
            x: -bannerWidth / 2 + size / 2,
            y: size - bannerHeight / 2,  // Changed from size + 6 to overlay the bottom
            width: bannerWidth,
            height: bannerHeight
        )
        paceLabel.frame = CGRect(x: 8, y: 0, width: bannerWidth - 16, height: bannerHeight)
        
        // Show/hide based on running state
        UIView.animate(withDuration: 0.2) {
            self.paceBanner.alpha = isRunning ? 1.0 : 0.0
        }
    }

    func configure(with annotation: MyLocationPulseAnnotation) {
        if webView == nil {
            // Configure message bridge to know when the <img> fully loads
            let controller = WKUserContentController()
            controller.add(self, name: "mediaLoaded")
            let config = WKWebViewConfiguration()
            config.userContentController = controller
            let wv = WKWebView(frame: webContainer.bounds, configuration: config)
            wv.isOpaque = false
            wv.backgroundColor = .clear
            wv.scrollView.isScrollEnabled = false
            wv.isUserInteractionEnabled = false // prevent context menu on long-press
            wv.layer.masksToBounds = true
            wv.navigationDelegate = self
            webContainer.addSubview(wv)
            webView = wv
            messageController = controller
        } else if messageController == nil, let wv = webView {
            // Reattach message handler on reuse
            let controller = wv.configuration.userContentController
            controller.add(self, name: "mediaLoaded")
            messageController = controller
        }

        // Load either profileURL or fallback GIF using SwiftUI AspectPreservingGIFView hosted inside webContainer
        let urlStr = annotation.profileURLString ?? annotation.fallbackGIFURL?.absoluteString
        let size = container.bounds.width
        if let urlStr, let u = URL(string: urlStr) {
            // CRITICAL: Set webContainer size FIRST before creating SwiftUI view
            let initialStickerHeight = size * 2.5
            let initialOriginY = size - initialStickerHeight
            webContainer.frame = CGRect(x: 0, y: initialOriginY, width: size, height: initialStickerHeight)
            
            // Always create a fresh view to ensure consistent rendering
            // CRITICAL: Use .bottom alignment to match webContainer's bottom-aligned positioning
            let root = AnyView(
                ZStack(alignment: .bottom) {
                    AspectPreservingGIFView(url: u, width: size, maxHeight: size * 3.0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .background(Color.clear)
            )
            
            // Always recreate hostingController for consistent state
            hostingController?.view.removeFromSuperview()
            hostingController = nil
            
            let hc = UIHostingController(rootView: root)
            hc.view.backgroundColor = .clear
            hc.view.isUserInteractionEnabled = false
            hc.sizingOptions = []
            
            // Apply initial layout WITHOUT triggering animation
            let size = container.bounds.width
            let stickerHeight = size * 2.5
            let originY = size - stickerHeight
            webContainer.frame = CGRect(x: 0, y: originY, width: size, height: stickerHeight)
            webView?.frame = webContainer.bounds
            applyUnevenMask(to: webContainer, topRadius: 8, bottomRadius: size / 2.0)
            
            // Set frame BEFORE adding to hierarchy
            hc.view.frame = webContainer.bounds
            hc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            
            webContainer.addSubview(hc.view)
            hostingController = hc
            hc.view.layoutIfNeeded()
            
            // Async layout update
            DispatchQueue.main.async {
                hc.view.frame = self.webContainer.bounds
            }
            // Hide legacy webView if present
            webView?.isHidden = true
            
            // Treat as loaded and show immediately (no animation)
            isContentLoaded = true
            container.alpha = 1.0
            container.transform = .identity
        } else {
            // No content to load; clear hosted view
            hostingController?.view.removeFromSuperview()
            hostingController = nil
            webView?.isHidden = true
            applyStickerLayout()
        }
        
        // Update pace banner
        updatePace(pace: annotation.pace, isRunning: annotation.isRunning)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        didAnimateIn = false
        isContentLoaded = false
        didRunContainerAppearAnimation = false
        shouldAnimateContainerOnLoad = false
        lastAppliedHeight = 0
        
        // Reset bounds and centerOffset to initial values
        let size: CGFloat = 40
        let initialHeight = size * 2.5
        bounds = CGRect(x: 0, y: 0, width: size, height: initialHeight)
        centerOffset = CGPoint(x: 0, y: size - initialHeight / 2)
        
        // Reset container to initial size (no animation, just show)
        container.frame = CGRect(x: 0, y: 0, width: size, height: size)
        container.alpha = 1.0
        container.transform = .identity
        webContainer.alpha = 1.0
        
        messageController?.removeScriptMessageHandler(forName: "mediaLoaded")
        messageController = nil
        hostingController?.view.removeFromSuperview()
        hostingController = nil
    }

    private func applyStickerLayout() {
        let size = container.bounds.width
        guard size > 0 else { return }
        let stickerWidth = size
        let stickerHeight = stickerWidth * 2.5
        let originX: CGFloat = 0
        let originY = size - stickerHeight
        
        webContainer.frame = CGRect(x: originX, y: originY, width: stickerWidth, height: stickerHeight)
        webView?.frame = webContainer.bounds
        
        if let hcView = hostingController?.view, hcView.frame != webContainer.bounds {
            hcView.frame = webContainer.bounds
        }
        
        applyUnevenMask(to: webContainer, topRadius: 8, bottomRadius: size / 2.0)
    }

    private func applyUnevenMask(to view: UIView, topRadius: CGFloat, bottomRadius: CGFloat) {
        let rect = view.bounds
        let path = UIBezierPath()

        let tl = max(0, topRadius)
        let tr = max(0, topRadius)
        let br = max(0, bottomRadius)
        let bl = max(0, bottomRadius)

        // Precompute angles to avoid ambiguous '.pi' references
        let zero = CGFloat(0)
        let halfPi = CGFloat(Double.pi / 2.0)
        let pi = CGFloat(Double.pi)
        let threeHalfPi = CGFloat(3.0 * Double.pi / 2.0)
        let negHalfPi = -halfPi

        // Start at top-left corner
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        // Top edge to top-right arc start
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        // Top-right corner arc
        path.addArc(withCenter: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: negHalfPi, endAngle: zero, clockwise: true)
        // Right edge to bottom-right arc start
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        // Bottom-right corner arc
        path.addArc(withCenter: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: zero, endAngle: halfPi, clockwise: true)
        // Bottom edge to bottom-left arc start
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        // Bottom-left corner arc
        path.addArc(withCenter: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: halfPi, endAngle: pi, clockwise: true)
        // Left edge to top-left arc start
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        // Top-left corner arc
        path.addArc(withCenter: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: pi, endAngle: threeHalfPi, clockwise: true)
        path.close()

        let mask = CAShapeLayer()
        mask.path = path.cgPath
        view.layer.mask = mask
    }

    // MARK: - Appear / Disappear animations
    func animateIn() {
        // Defer container pop-in until content is loaded
        if !isContentLoaded {
            shouldAnimateContainerOnLoad = true
            return
        }
        guard !didRunContainerAppearAnimation else { return }
        didRunContainerAppearAnimation = true
        
        // CRITICAL: Don't call applyStickerLayout() here!
        // Layout is already set by applyStickerLayoutWithHeight with correct bounds/centerOffset
        // Just animate the visual appearance
        container.alpha = 0
        container.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
            self.container.alpha = 1
            self.container.transform = .identity
        }
    }

    private func animateInIfNeeded() {
        guard !didAnimateIn else { return }
        didAnimateIn = true
        // Ensure final layout before reveal; fade in web content only to avoid offset/scale flash
        applyStickerLayout()
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
            self.webContainer.alpha = 1
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseIn]) {
            self.container.alpha = 0
            self.container.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
        } completion: { _ in
            completion()
        }
    }

    // WKNavigationDelegate: do not animate on document finish; wait for <img> onload
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // no-op; image onload will trigger via message handler
    }

    // WKScriptMessageHandler
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "mediaLoaded" {
            isContentLoaded = true
            // Compute final frame before revealing and avoid re-layout during fade
            applyStickerLayout()
            // If we deferred container pop-in, do it now
            if shouldAnimateContainerOnLoad || self.container.alpha == 0 {
                shouldAnimateContainerOnLoad = false
                animateIn()
            }
            animateInIfNeeded()
        }
    }
}

// MARK: - Final Summary View
private struct FinalRunSummaryView: View {
    let elapsed: Int
    let distanceMeters: Double
    let routeCoordinates: [CLLocationCoordinate2D]
    @EnvironmentObject var account: AccountManager

    private var timeString: String {
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        if h > 0 { return String(format: "%02d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    private var distanceString: String { String(format: "%.2fkm", distanceMeters / 1000.0) }

    private var paceString: String {
        let km = distanceMeters / 1000.0
        guard km > 0.01 else { return "00'00/km" }
        let secPerKm = Double(elapsed) / km
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%02d:%02d/km", m, s)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Add space above the text
            Spacer()
                .frame(height: 40)
            
            // 3D rotating stats text (use actual route for 3D illustration)
            Rotating3DStatsView(text: buildStatsMultilineText(), routeCoordinates: routeCoordinates)
                .frame(height: 300)
            
            // 2D route illustration below
            routeIllustration()
                .frame(height: 130)  // Slightly smaller height
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }
    
    private func buildStatsMultilineText() -> String {
        return "\(distanceString)\n\(paceString)\n\(timeString)"
    }

    private func labeledBigMetric(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.black)
        }
    }


    @ViewBuilder
    private func routeIllustration() -> some View {
        GeometryReader { geo in
            ZStack {
                if !routeCoordinates.isEmpty {
                    // Calculate bounding box of route to check distance
                    let lats = routeCoordinates.map { $0.latitude }
                    let lons = routeCoordinates.map { $0.longitude }
                    
                    if let minLat = lats.min(), let maxLat = lats.max(),
                       let minLon = lons.min(), let maxLon = lons.max() {
                        
                        let latRange = maxLat - minLat
                        let lonRange = maxLon - minLon
                        
                        // Rough estimate: 1 degree latitude ≈ 111km, check if movement is very small (< ~10m)
                        let isVerySmallMovement = latRange < 0.0001 && lonRange < 0.0001
                        
                        if isVerySmallMovement {
                            // Show a dot for very small movement (less than ~10m)
                            Circle()
                                .fill(Color(red: 0x5C/255.0, green: 0xBA/255.0, blue: 0xF2/255.0))
                                .frame(width: 12, height: 12)
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        } else {
                            // Draw actual route from coordinates with gradient (A9E4FF → 1191E6)
                            let latRangeSafe = max(maxLat - minLat, 0.0001)
                            let lonRangeSafe = max(maxLon - minLon, 0.0001)
                            let strokeWidth: CGFloat = 8
                            let padding: CGFloat = 32 + strokeWidth / 2
                            let availableWidth = geo.size.width - padding * 2
                            let availableHeight = geo.size.height - padding * 2
                            let routeAspectRatio = lonRangeSafe / latRangeSafe
                            let fitToWidth = routeAspectRatio > (availableWidth / availableHeight)
                            let w: CGFloat = fitToWidth ? availableWidth : (availableHeight * routeAspectRatio)
                            let h: CGFloat = fitToWidth ? (availableWidth / routeAspectRatio) : availableHeight
                            let xOffset = padding + (availableWidth - w) / 2
                            let yOffset = padding + (availableHeight - h) / 2

                            // Build route path (outside of ViewBuilder control flow)
                            let routePath: Path = {
                                var p = Path()
                                for (index, coord) in routeCoordinates.enumerated() {
                                    let x = xOffset + CGFloat((coord.longitude - minLon) / lonRangeSafe) * w
                                    let y = yOffset + CGFloat((maxLat - coord.latitude) / latRangeSafe) * h
                                    let pt = CGPoint(x: x, y: y)
                                    if index == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                                }
                                return p
                            }()

                            // Compute gradient start/end in unit coordinates
                            let firstCoord = routeCoordinates.first!
                            let lastCoord = routeCoordinates.last!
                            let sx = xOffset + CGFloat((firstCoord.longitude - minLon) / lonRangeSafe) * w
                            let sy = yOffset + CGFloat((maxLat - firstCoord.latitude) / latRangeSafe) * h
                            let ex = xOffset + CGFloat((lastCoord.longitude - minLon) / lonRangeSafe) * w
                            let ey = yOffset + CGFloat((maxLat - lastCoord.latitude) / latRangeSafe) * h
                            let startUnit = UnitPoint(x: max(0, min(1, sx / max(geo.size.width, 1))), y: max(0, min(1, sy / max(geo.size.height, 1))))
                            let endUnit = UnitPoint(x: max(0, min(1, ex / max(geo.size.width, 1))), y: max(0, min(1, ey / max(geo.size.height, 1))))
                            let gradient = LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0xA9/255.0, green: 0xE4/255.0, blue: 0xFF/255.0),
                                    Color(red: 0x11/255.0, green: 0x91/255.0, blue: 0xE6/255.0)
                                ]),
                                startPoint: startUnit,
                                endPoint: endUnit
                            )

                            routePath
                                .stroke(style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
                                .foregroundStyle(gradient)
                        }
                    }
                } else {
                    // Fallback placeholder if no route data
                    Path { p in
                        let strokeWidth: CGFloat = 8
                        let padding: CGFloat = 32 + strokeWidth / 2
                        let w = geo.size.width - padding * 2
                        let h = geo.size.height - padding * 2
                        let origin = CGPoint(x: padding, y: padding)
                        p.move(to: CGPoint(x: origin.x, y: origin.y + h * 0.1))
                        p.addCurve(to: CGPoint(x: origin.x + w * 0.9, y: origin.y + h * 0.8), control1: CGPoint(x: origin.x + w * 0.2, y: origin.y + h * 0.0), control2: CGPoint(x: origin.x + w * 0.6, y: origin.y + h * 1.0))
                    }
                    .stroke(Color(red: 0x5C/255.0, green: 0xBA/255.0, blue: 0xF2/255.0), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(height: 130)
    }
}

// Custom shape for rounding specific corners
struct RoundedCorners: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// Extension to apply corner radius to specific corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorners(radius: radius, corners: corners))
    }
}

// MARK: - Gradient Polyline Renderer
fileprivate final class GradientPolylineRenderer: MKOverlayPathRenderer {
    private let polyline: MKPolyline
    private let startColor: UIColor
    private let endColor: UIColor
    override var lineWidth: CGFloat {
        didSet { setNeedsDisplay() }
    }
    override var lineCap: CGLineCap { didSet { setNeedsDisplay() } }
    override var lineJoin: CGLineJoin { didSet { setNeedsDisplay() } }

    init(polyline: MKPolyline, startColor: UIColor, endColor: UIColor) {
        self.polyline = polyline
        self.startColor = startColor
        self.endColor = endColor
        super.init(overlay: polyline)
        self.lineWidth = 6
    }

    override func createPath() {
        let path = CGMutablePath()
        let points = polyline.points()
        guard polyline.pointCount > 0 else { self.path = path; return }
        let first = point(for: points[0])
        path.move(to: first)
        for i in 1..<polyline.pointCount {
            let p = point(for: points[i])
            path.addLine(to: p)
        }
        self.path = path
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let path = self.path else { return }
        context.saveGState()
        context.addPath(path)
        context.setLineCap(lineCap)
        context.setLineJoin(lineJoin)
        let scaledWidth = max(1, self.lineWidth / zoomScale)
        context.setLineWidth(scaledWidth)
        // Stroke path into a clip, then draw gradient through it
        context.replacePathWithStrokedPath()
        context.clip()

        // Gradient from route start to end in view space
        let points = polyline.points()
        let startPt = point(for: points[0])
        let endPt = point(for: points[polyline.pointCount - 1])

        let colors = [startColor.cgColor, endColor.cgColor] as CFArray
        let locations: [CGFloat] = [0, 1]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
            context.drawLinearGradient(gradient, start: startPt, end: endPt, options: [])
        }
        context.restoreGState()
    }
}

// MARK: - Run Summary Sheet
struct RunSummarySheet: View {
    let elapsed: Int
    let distanceMeters: Double
    let routeCoordinates: [CLLocationCoordinate2D]
    let selfieGIFURL: URL?
    let onBack: () -> Void
    let onAugItHere: () -> Void
    
    @EnvironmentObject var account: AccountManager
    @State private var showDiscardConfirm: Bool = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // White background sheet with rounded top corners
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 40)  // Space for selfie GIF that extends above
                
                // Stats and route (no scroll)
                FinalRunSummaryView(elapsed: elapsed, distanceMeters: distanceMeters, routeCoordinates: routeCoordinates)
                
                Spacer(minLength: 12)  // Reduced space between route and buttons
                
                // Buttons at bottom
                HStack(spacing: 12) {
                    // Discard button
                    Button(action: { showDiscardConfirm = true }) {
                        HStack(spacing: 8) {
                            Image("Delete")
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                                .foregroundColor(.white)
                            Text("Discard")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)  // Changed from black to white
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.black)  // Changed from light gray to black
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                    .alert("Discard run?", isPresented: $showDiscardConfirm) {
                        Button("Cancel", role: .cancel) { }
                        Button("Discard", role: .destructive) {
                            onBack()
                        }
                    } message: {
                        Text("This will delete the final stat summary and return to Run View.")
                    }
                    
                    // Aug here button
                    Button(action: {
                        onAugItHere()
                        onBack()
                    }) {
                        HStack(spacing: 8) {
                            Image("sticker-white")
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                                .foregroundColor(.black)
                            Text("aug here")
                                .font(.system(size: 20, weight: .semibold))  // Add semibold weight
                                .baselineOffset(2)  // Vertically trim and align text
                        }
                        .foregroundColor(.black)  // Change text to black
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.neon)  // Change background to neon
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)  // Reduced from 36 to ignore bottom safe area
            }
            .frame(height: UIScreen.main.bounds.height * 0.72)  // Increased from 0.65 to 0.72
            .frame(maxWidth: .infinity)
            .background(
                // Checkerboard background that extends to bottom
                CheckerboardBackground()
                    .cornerRadius(35, corners: [.topLeft, .topRight])
                    .edgesIgnoringSafeArea(.bottom)
            )
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: -10)
            
            // Selfie GIF positioned at the bottom, extending above the sheet
            selfieGifCluster()
                .offset(y: -(UIScreen.main.bounds.height * 0.72) + 45)  // Match new sheet height
        }
    }
    
    @ViewBuilder
    private func selfieGifCluster() -> some View {
        // Match previous visual scale:
        // - Previous circle diameter was `diameter`
        // - In composed GIF, canvasWidth = 1.8 * diameter and circle diameter = canvasWidth / 1.8
        //   => To render the composed GIF so that its internal circle appears at `diameter`,
        //      set display width to `diameter * 1.8`.
        let diameter: CGFloat = 55
        let gifWidth = diameter - 5
        let gifHeight = gifWidth * 1.33
        let displayWidth = diameter * 2.5
        if let url = account.runProfileURL ?? selfieGIFURL {
            let isRunProfile = (account.runProfileURL != nil)
            ZStack(alignment: .bottom) {
                AspectPreservingGIFView(url: url, width: displayWidth, maxHeight: gifHeight * 2)
                    .offset(y: isRunProfile ? 5 : 0)
            }
            // Keep the same outer container sizing as before for layout consistency
            .frame(width: diameter * 4, height: gifHeight * 2)
        } else {
            EmptyView()
        }
    }
}

// MARK: - 3D Rotating Stats Text View
struct Rotating3DStatsView: UIViewRepresentable {
    let text: String
    let routeCoordinates: [CLLocationCoordinate2D]
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = false
        
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        
        // Add camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = true  // Zero perspective (orthographic)
        cameraNode.camera?.orthographicScale = 4.5  // Reduced from 6.0 to zoom in closer
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 18)  // Move camera further back (was 15)
        scene.rootNode.addChildNode(cameraNode)
        
        // Add directional light
        let directional = SCNLight()
        directional.type = .directional
        directional.color = UIColor.white
        directional.intensity = 1000
        let directionalNode = SCNNode()
        directionalNode.light = directional
        directionalNode.eulerAngles = SCNVector3(-Float.pi/6, Float.pi/6, 0)
        scene.rootNode.addChildNode(directionalNode)
        
        // 3D Text with Exqt font
        let textGeo = SCNText(string: text, extrusionDepth: 2)
        textGeo.font = UIFont(name: "exqt", size: 18) ?? UIFont.systemFont(ofSize: 22, weight: .regular)
        textGeo.flatness = 0.2
        textGeo.isWrapped = true
        textGeo.containerFrame = CGRect(x: 0, y: 0, width: 300, height: 300)
        textGeo.alignmentMode = CATextLayerAlignmentMode.center.rawValue
        
        // Apply paragraph style for line height
        if let font = textGeo.font as? UIFont {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineSpacing = -3
            let attr = NSAttributedString(string: text, attributes: [
                .font: font,
                .paragraphStyle: style
            ])
            textGeo.string = attr
        }
        
        // Materials with neon green color (B0F600)
        let frontMat = SCNMaterial()
        frontMat.diffuse.contents = UIColor(red: 0xB0/255.0, green: 0xF6/255.0, blue: 0x00/255.0, alpha: 1.0)
        frontMat.specular.contents = UIColor.black
        frontMat.shininess = 0
        frontMat.lightingModel = .constant
        
        let backMat = SCNMaterial()
        backMat.diffuse.contents = UIColor(red: 0x88/255.0, green: 0xBB/255.0, blue: 0x00/255.0, alpha: 1.0) // Darker green
        backMat.specular.contents = UIColor.black
        backMat.shininess = 0
        backMat.lightingModel = .constant
        
        let sideMat = SCNMaterial()
        sideMat.diffuse.contents = UIColor(red: 0x7D/255.0, green: 0xAB/255.0, blue: 0x00/255.0, alpha: 1.0) // Slightly darker green
        sideMat.specular.contents = UIColor.black
        sideMat.shininess = 0
        sideMat.lightingModel = .constant
        
        textGeo.materials = [frontMat, backMat, sideMat]
        let textNode = SCNNode(geometry: textGeo)
        
        // Center the pivot
        let (minB, maxB) = textNode.boundingBox
        textNode.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x)/2, (minB.y + maxB.y)/2, (minB.z + maxB.z)/2)
        textNode.scale = SCNVector3(0.15, 0.15, 0.15)  // Increased from 0.12 to make text bigger
        textNode.position = SCNVector3(x: 0, y: 0, z: 0)  // Center the text at origin (0, 0, 0)
        
        // Create a container node to hold both text and route so they rotate together
        let containerNode = SCNNode()
        containerNode.addChildNode(textNode)
        
        // Create 3D route illustration below the text
        if !routeCoordinates.isEmpty {
            let routeNode = create3DRoute(from: routeCoordinates)
            routeNode.position = SCNVector3(x: 0, y: -2, z: 0)  // Position below text
            containerNode.addChildNode(routeNode)
        }
        
        scene.rootNode.addChildNode(containerNode)
        
        // Rotate the entire container (text + route together) to -30° around Y with animation
        let rotateOnce = SCNAction.rotateTo(x: 0, y: -(30 * .pi / 180), z: 0, duration: 3.0, usesShortestUnitArc: true)
        rotateOnce.timingMode = .easeInEaseOut
        containerNode.runAction(rotateOnce) {
            // After rotation completes, start floating animation
            let floatUp = SCNAction.moveBy(x: 0, y: 0.15, z: 0, duration: 1.0)
            floatUp.timingMode = .easeInEaseOut
            let floatDown = SCNAction.moveBy(x: 0, y: -0.15, z: 0, duration: 1.0)
            floatDown.timingMode = .easeInEaseOut
            let floatSequence = SCNAction.sequence([floatUp, floatDown])
            let floatLoop = SCNAction.repeatForever(floatSequence)
            containerNode.runAction(floatLoop, forKey: "floating")
        }
        
        scnView.scene = scene
        scnView.isPlaying = true
        scnView.antialiasingMode = .multisampling4X
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) { }
    
    private func create3DRoute(from coordinates: [CLLocationCoordinate2D]) -> SCNNode {
        let containerNode = SCNNode()
        
        guard coordinates.count > 1 else {
            // Create a small dot for very short routes
            let sphere = SCNSphere(radius: 0.3)
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(red: 0x5C/255.0, green: 0xBA/255.0, blue: 0xF2/255.0, alpha: 1.0)
            material.lightingModel = .constant
            sphere.materials = [material]
            let dotNode = SCNNode(geometry: sphere)
            containerNode.addChildNode(dotNode)
            return containerNode
        }
        
        // Calculate bounds
        let lats = coordinates.map { $0.latitude }
        let lons = coordinates.map { $0.longitude }
        let minLat = lats.min()!
        let maxLat = lats.max()!
        let minLon = lons.min()!
        let maxLon = lons.max()!
        let latRange = maxLat - minLat
        let lonRange = maxLon - minLon
        
        // Normalize coordinates to fit in a box
        let scale: CGFloat = 3.0  // Size of the route box
        
        // Create a UIBezierPath for the route with stroke
        let path = UIBezierPath()
        path.lineWidth = 0.15  // Width of the route line
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        
        for (index, coord) in coordinates.enumerated() {
            let x = CGFloat((coord.longitude - minLon) / max(lonRange, 0.0001)) * scale - scale / 2
            let z = CGFloat((coord.latitude - minLat) / max(latRange, 0.0001)) * scale - scale / 2
            
            let point = CGPoint(x: x, y: -z)  // Invert Z for north-up
            
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        
        // Convert stroked path to filled shape using CGPath
        let strokedPath = path.cgPath.copy(strokingWithWidth: 0.15, lineCap: .round, lineJoin: .round, miterLimit: 10)
        let strokedBezierPath = UIBezierPath(cgPath: strokedPath)
        
        // Create an extruded 3D shape from the stroked path
        let shape = SCNShape(path: strokedBezierPath, extrusionDepth: 0.3)
        
        // Front face material (5CBAF2)
        let frontMaterial = SCNMaterial()
        frontMaterial.diffuse.contents = UIColor(red: 0x5C/255.0, green: 0xBA/255.0, blue: 0xF2/255.0, alpha: 1.0)
        frontMaterial.lightingModel = .constant
        
        // Side (extrusion) material (046DB3)
        let sideMaterial = SCNMaterial()
        sideMaterial.diffuse.contents = UIColor(red: 0x04/255.0, green: 0x6D/255.0, blue: 0xB3/255.0, alpha: 1.0)
        sideMaterial.lightingModel = .constant
        
        // Back face material
        let backMaterial = SCNMaterial()
        backMaterial.diffuse.contents = UIColor(red: 0x88/255.0, green: 0xBB/255.0, blue: 0x00/255.0, alpha: 1.0)
        backMaterial.lightingModel = .constant
        
        shape.materials = [frontMaterial, sideMaterial, sideMaterial, sideMaterial, sideMaterial, backMaterial]
        
        let shapeNode = SCNNode(geometry: shape)
        
        // Rotate to make it face the camera (path is in XY plane, rotate to XZ plane)
        shapeNode.eulerAngles = SCNVector3(x: -Float.pi / 2, y: 0, z: 0)
        
        containerNode.addChildNode(shapeNode)
        
        return containerNode
    }
}

// MARK: - Checkerboard Background
struct CheckerboardBackground: View {
    let squareSize: CGFloat = 20
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let columns = Int(ceil(size.width / squareSize))
                let rows = Int(ceil(size.height / squareSize))
                
                for row in 0..<rows {
                    for col in 0..<columns {
                        let isEven = (row + col) % 2 == 0
                        let rect = CGRect(
                            x: CGFloat(col) * squareSize,
                            y: CGFloat(row) * squareSize,
                            width: squareSize,
                            height: squareSize
                        )
                        context.fill(
                            Path(rect),
                            with: .color(isEven ? Color(white: 0.95) : .white)
                        )
                    }
                }
            }
        }
    }
}

// MARK: - AspectPreservingGIFView (used in MyLocationPulseAnnotationView)
// Renders a GIF with fixed width and preserves original aspect ratio by probing GIF header.
// Clip shape matches the profile pulse visual used on the map.
private struct AspectPreservingGIFView: View {
    let url: URL
    let width: CGFloat
    let maxHeight: CGFloat?
    @State private var aspectHeightOverWidth: CGFloat? = nil

    var body: some View {
        // CRITICAL FIX: Always use maxHeight if available, never shrink below initial size
        // Let UIKit container control the actual displayed size
        // SwiftUI just provides a large canvas, GIF uses objectFit:contain to scale down
        let ar = aspectHeightOverWidth ?? 2.5  // Conservative fallback (matches applyStickerLayout)
        let calculatedHeight = width * ar
        
        // Always use the larger of calculated height or initial height (width * 2.5)
        // This prevents SwiftUI from shrinking before UIKit container is ready
        let conservativeHeight = max(calculatedHeight, width * 2.5)
        let finalHeight = maxHeight != nil ? min(conservativeHeight, maxHeight!) : conservativeHeight
        let displayHeight = finalHeight
        
        Color.clear
            .frame(width: width, height: displayHeight)
            .overlay(
                GIFWebView(url: url, objectFit: "contain")
                    .clipShape(
                        UnevenRoundedRectangle(
                            cornerRadii: .init(
                                topLeading: 8,
                                bottomLeading: width / 2,
                                bottomTrailing: width / 2,
                                topTrailing: 8
                            ),
                            style: .continuous
                        )
                    ),
                alignment: .bottom
            )
        .task(id: url) {
            if aspectHeightOverWidth == nil, let size = await Self.fetchGIFLogicalScreenSize(url: url) {
                let hOverW = max(1, size.height) / max(1, size.width)
                let actualHeight = width * hOverW
                let finalHeight = maxHeight != nil ? min(actualHeight, maxHeight!) : actualHeight
                
                await MainActor.run {
                    aspectHeightOverWidth = hOverW
                }
                
                await Task.yield()
                
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("AspectRatioUpdated"), 
                        object: nil,
                        userInfo: ["actualHeight": finalHeight]
                    )
                }
            }
        }
    }

    // MARK: - Header probe helpers (scoped to avoid global symbol collisions)
    private static func fetchGIFLogicalScreenSize(url: URL) async -> CGSize? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-9", forHTTPHeaderField: "Range")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return parseGIFHeaderLogicalScreenSize(from: data)
        } catch {
            return nil
        }
    }

    private static func parseGIFHeaderLogicalScreenSize(from data: Data) -> CGSize? {
        guard data.count >= 10 else { return nil }
        // Header starts with GIF87a or GIF89a
        if !(data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x38) { return nil }
        // Little-endian width/height at bytes 6-9
        let w = UInt16(data[6]) | (UInt16(data[7]) << 8)
        let h = UInt16(data[8]) | (UInt16(data[9]) << 8)
        return CGSize(width: Int(w), height: Int(h))
    }
}

