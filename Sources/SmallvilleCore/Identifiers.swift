import Foundation

/// Stable identifier for an agent (a lowercase slug such as `isabella`).
public struct AgentID: RawRepresentable, Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func < (lhs: AgentID, rhs: AgentID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Stable identifier for a place an agent can be (`the_ville:hobbs_cafe`).
public struct LocationID: RawRepresentable, Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func < (lhs: LocationID, rhs: LocationID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Stable identifier for a planted storyline (`valentines-party`).
public struct StorylineID: RawRepresentable, Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func < (lhs: StorylineID, rhs: StorylineID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
