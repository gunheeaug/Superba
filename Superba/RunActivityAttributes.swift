import Foundation
import ActivityKit

// MARK: - Live Activity Attributes for Run Tracking
public struct RunActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic state that updates during the run
        public var elapsedTime: Int           // seconds
        public var distanceMeters: Double     // meters
        public var paceMinPerKm: Double      // average minutes per kilometer
        public var currentPaceMinPerKm: Double // instantaneous minutes per kilometer
        public var isRunning: Bool           // true if running, false if paused
        public var placeLine: String?        // "Neighborhood, City"
        
        public init(elapsedTime: Int, distanceMeters: Double, paceMinPerKm: Double, currentPaceMinPerKm: Double, isRunning: Bool, placeLine: String? = nil) {
            self.elapsedTime = elapsedTime
            self.distanceMeters = distanceMeters
            self.paceMinPerKm = paceMinPerKm
            self.currentPaceMinPerKm = currentPaceMinPerKm
            self.isRunning = isRunning
            self.placeLine = placeLine
        }
    }
    
    // Static data that doesn't change during the activity
    public var startTime: Date
    
    public init(startTime: Date) {
        self.startTime = startTime
    }
}

