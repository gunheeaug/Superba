//
//  RunWidgetLiveActivity.swift
//  RunWidget
//
//  Created by Gunhee Han on 11/8/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Color Extension
extension Color {
    static let neon = Color(red: 0xB0/255.0, green: 0xF6/255.0, blue: 0x00/255.0)
}

// MARK: - Helpers
extension View {
    @ViewBuilder
    func numericTransitionIfAvailable() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.contentTransition(.identity)
        } else {
            self
        }
    }
}

// MARK: - Live Activity widget driven by the shared RunActivityAttributes
struct RunWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            // Lock Screen UI (white background, black text)
            LockScreenLiveActivityView(context: context, textColor: .black)
                .activityBackgroundTint(Color.white)
                .activitySystemActionForegroundColor(Color.black)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        // Address row
                        HStack(spacing: 6) {
                            Image("SuperbaLogoNeon")
                                .renderingMode(.original)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                                .numericTransitionIfAvailable()
                            Text(context.state.placeLine ?? "Neighborhood, City")
                                .font(.footnote)
                                .fontWeight(.bold)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundColor(.white)
                                .numericTransitionIfAvailable()
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .center)
                        
                        // Values row (Time | Current Pace | Distance)
                        HStack(spacing: 0) {
                            Text(formatTimeShort(context.state.elapsedTime))
                                .font(.title2)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .foregroundColor(.white)
                                .numericTransitionIfAvailable()
                                .transaction { $0.animation = nil }
                            VStack(spacing: 4) {
                                Text(formatPace(context.state.currentPaceMinPerKm))
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .numericTransitionIfAvailable()
                            }
                            .frame(maxWidth: .infinity)
                            Text(formatDistance(context.state.distanceMeters))
                                .font(.title2)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .foregroundColor(.white)
                                .numericTransitionIfAvailable()
                        }
                        // Labels row
                        HStack(spacing: 0) {
                            Text("Time")
                                .font(.footnote)
                                .fontWeight(.bold)
                                .foregroundColor(.white.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .center)
                            Text("Current Pace")
                                .font(.footnote)
                                .fontWeight(.bold)
                                .foregroundColor(.white.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .center)
                            Text("Distance")
                                .font(.footnote)
                                .fontWeight(.bold)
                                .foregroundColor(.white.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding()
                }
            } compactLeading: {
                // Compact UI - Left side of notch
                Image("SuperbaLogoNeon")
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            } compactTrailing: {
                // Compact UI - Right side of notch
                Text(formatTimeShort(context.state.elapsedTime))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .numericTransitionIfAvailable()
            } minimal: {
                // Minimal UI
                Image("SuperbaLogoNeon")
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            }
            .contentMargins(.all, 6, for: .expanded)
        }
    }
}

// MARK: - Lock Screen View
struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<RunActivityAttributes>
    var textColor: Color = .black
    
    var body: some View {
        VStack(spacing: 2) {
            // Top row icon + place
            HStack(spacing: 6) {
                Image("SuperbaLogoNeon")
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .numericTransitionIfAvailable()
                Text(context.state.placeLine ?? "Neighborhood, City")
                    .font(.footnote)
                    .fontWeight(.bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundColor(textColor)
                    .numericTransitionIfAvailable()
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .center)
            
            // Values row: three equal columns centered
            HStack(spacing: 0) {
                Text(formatTime(context.state.elapsedTime))
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundColor(textColor)
                    .numericTransitionIfAvailable()
                VStack(spacing: 4) {
                    Text(formatPace(context.state.currentPaceMinPerKm))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(textColor)
                        .numericTransitionIfAvailable()
                }
                .frame(maxWidth: .infinity)
                Text(formatDistance(context.state.distanceMeters))
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundColor(textColor)
                    .numericTransitionIfAvailable()
            }
            // Labels row
            HStack(spacing: 0) {
                Text("Time")
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundColor(textColor.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("Current Pace")
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundColor(textColor.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("Distance")
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundColor(textColor.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding()
    }
}

// MARK: - Formatting Helpers (match reference)
private func formatTime(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 {
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
    return String(format: "%02d:%02d", m, s)
}

// No leading zero for minutes when under 1 hour (e.g., 0:07, 5:36)
private func formatTimeShort(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 {
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
    return String(format: "%d:%02d", m, s)
}

private func formatDistance(_ meters: Double) -> String {
    let km = meters / 1000.0
    return String(format: "%.2f", km)
}

private func formatPace(_ minPerKm: Double) -> String {
    if minPerKm <= 0 || minPerKm.isInfinite || minPerKm.isNaN {
        return "00:00"
    }
    let min = Int(minPerKm)
    let sec = Int((minPerKm - Double(min)) * 60)
    return String(format: "%d:%02d", min, sec)
}
