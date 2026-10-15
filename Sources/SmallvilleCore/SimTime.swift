import Foundation

/// A point in simulated time, measured in game-minutes since the simulation started.
public struct SimTime: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public static let minutesPerTick = 10
    public static let minutesPerDay = 24 * 60

    public var minutes: Int

    public init(minutes: Int) {
        self.minutes = minutes
    }

    /// Zero-based day index.
    public var day: Int { minutes / Self.minutesPerDay }
    public var minuteOfDay: Int { minutes % Self.minutesPerDay }
    public var hour: Int { minuteOfDay / 60 }
    public var minuteOfHour: Int { minuteOfDay % 60 }
    public var isHourBoundary: Bool { minuteOfHour == 0 }
    public var isDayBoundary: Bool { minuteOfDay == 0 }

    public func advanced(by minutes: Int) -> SimTime {
        SimTime(minutes: self.minutes + minutes)
    }

    public static func < (lhs: SimTime, rhs: SimTime) -> Bool {
        lhs.minutes < rhs.minutes
    }

    public var description: String {
        String(format: "Day %d %02d:%02d", day + 1, hour, minuteOfHour)
    }
}
