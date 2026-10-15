import Foundation

/// The kinds of brain call the simulation makes. Adding a case is a budget decision.
public enum BrainCallKind: String, Hashable, Sendable, Codable, CaseIterable {
    case planDay
    case planHour
    case converse
    case reflect
    case ratePoignancy
}

/// Counts brain calls and tokens per agent per game-day. The numbers in CLAUDE.md live here.
public struct CallBudget: Sendable, Codable {
    public static let maxCallsPerAgentDay = 45
    public static let maxPromptTokens = 3000

    public private(set) var callsByAgentDay: [String: Int] = [:]
    public private(set) var callsByKind: [String: Int] = [:]
    public private(set) var totalInputTokens = 0
    public private(set) var totalOutputTokens = 0
    public private(set) var totalWallSeconds = 0.0
    public private(set) var largestPromptTokens = 0
    public private(set) var overBudgetPrompts = 0

    public init() {}

    public mutating func record(_ kind: BrainCallKind, agent: AgentID, day: Int, receipt: BrainCallReceipt) {
        callsByAgentDay["\(agent.rawValue)/\(day)", default: 0] += 1
        callsByKind[kind.rawValue, default: 0] += 1
        totalInputTokens += receipt.inputTokens
        totalOutputTokens += receipt.outputTokens
        totalWallSeconds += receipt.wallSeconds
        largestPromptTokens = max(largestPromptTokens, receipt.inputTokens)
        if receipt.inputTokens > Self.maxPromptTokens {
            overBudgetPrompts += 1
        }
    }

    public func summary() -> BudgetSummary {
        let totalCalls = callsByAgentDay.values.reduce(0, +)
        let agentDays = callsByAgentDay.count
        let maxPerAgentDay = callsByAgentDay.values.max() ?? 0
        let mean = agentDays == 0 ? 0 : Double(totalCalls) / Double(agentDays)
        return BudgetSummary(
            totalCalls: totalCalls,
            agentDays: agentDays,
            meanCallsPerAgentDay: mean,
            maxCallsPerAgentDay: maxPerAgentDay,
            largestPromptTokens: largestPromptTokens,
            overBudgetPrompts: overBudgetPrompts,
            callsByKind: callsByKind,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            totalWallSeconds: totalWallSeconds,
            withinBudget: overBudgetPrompts == 0 && maxPerAgentDay <= Self.maxCallsPerAgentDay)
    }
}

/// The JSON block the runner prints and the agent pastes into its reports.
public struct BudgetSummary: Sendable, Codable {
    public var totalCalls: Int
    public var agentDays: Int
    public var meanCallsPerAgentDay: Double
    public var maxCallsPerAgentDay: Int
    public var largestPromptTokens: Int
    public var overBudgetPrompts: Int
    public var callsByKind: [String: Int]
    public var totalInputTokens: Int
    public var totalOutputTokens: Int
    public var totalWallSeconds: Double
    public var withinBudget: Bool
}
