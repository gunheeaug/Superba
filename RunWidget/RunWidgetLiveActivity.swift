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
            // Lock Screen UI (system background tint; thin-material look handled inside view)
            LockScreenLiveActivityView(context: context, textColor: .black)
                .activityBackgroundTint(Color(.systemBackground).opacity(0.8))
                .activitySystemActionForegroundColor(Color.black)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        // Address row when running; "Paused" row when paused
                        Group {
                            if context.state.isRunning {
                                HStack(spacing: 4) {
                                    Image("SuperbaWidgetNeon")
                                        .renderingMode(.original)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 20, height: 20)
                                    Text(context.state.placeLine ?? "Neighborhood, City")
                                        .font(.footnote)
                                        .fontWeight(.semibold)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .foregroundColor(.white)
                                        .numericTransitionIfAvailable()
                                }
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "pause.fill")
                                    Text("Paused")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .numericTransitionIfAvailable()
                                }
                                .foregroundColor(Color.neon)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        
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
                                    .foregroundColor(context.state.isRunning ? .neon : .white)
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
                                .fontWeight(.semibold)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .center)
                            Text("Current Pace")
                                .fontWeight(.semibold)
                                .font(.caption)
                                .foregroundColor(context.state.isRunning ? .neon : .white)
                                .frame(maxWidth: .infinity, alignment: .center)
                            Text("Distance")
                                .fontWeight(.semibold)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding()
                }
            } compactLeading: {
                // Compact UI - Left side of notch
                Image("WidgetAppIconSuperba")
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            } compactTrailing: {
                // Compact UI - Right side of notch
                Group {
                    if context.state.isRunning {
                        Text(formatTimeShort(context.state.elapsedTime))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .monospacedDigit()
                            .numericTransitionIfAvailable()
                    } else {
                        Image("PausedDynamicIsland")
                            .renderingMode(.original)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                    }
                }
            } minimal: {
                // Minimal UI - show pause icon when paused, app icon when running
                Group {
                    if context.state.isRunning {
                        Image("WidgetAppIconSuperba")
                            .renderingMode(.original)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                    }
                }
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
        ZStack(alignment: .top) {
            // Top 54pt background:
            // - Running: full neon gradient
            // - Paused: ultra-thin material with dark tint
            Group {
                if context.state.isRunning {
                    LinearGradient(
                        colors: [
                            Color(red: 0.78, green: 1.00, blue: 0.20),
                            Color(red: 0.62, green: 0.90, blue: 0.00)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 54)
                    .frame(maxWidth: .infinity, alignment: .top)
                } else {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .frame(height: 54)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .overlay(
                            Rectangle()
                                .fill(Color.black.opacity(0.2))
                                .frame(height: 54)
                                .frame(maxWidth: .infinity, alignment: .top)
                        )
                }
            }
                        
            VStack(spacing: 10) {
                // Top bar: place when running; centered pause row when paused
                Group {
                    if context.state.isRunning {
                        HStack(spacing: 4) {
                            Image("SuperbaStart")
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18, height: 18)
                                .foregroundColor(.black)
                                .numericTransitionIfAvailable()
                            Text(context.state.placeLine ?? "Neighborhood, City")
                                .font(.footnote)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundColor(.black) // black text over neon header
                                .numericTransitionIfAvailable()
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "pause.fill")
                                .foregroundColor(.white)
                            Text("Paused")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .trailing) {
                            Image("SuperbaWidgetNeon")
                                .renderingMode(.original)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                                .padding(.trailing, 14)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                // Extra breathing room between header and values
                .padding(.bottom, 8)
                
                // Values + labels with tighter spacing between them
                VStack(spacing: 2) {
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
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(textColor.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .center)
                        Text("Current Pace")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(textColor.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .center)
                        Text("Distance")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(textColor.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .padding()
        }
        // Ensure the black band respects the widget's rounded corners
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
