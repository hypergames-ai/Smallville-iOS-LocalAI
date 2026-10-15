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

    /// Calls charged to each "agent/day". A call made for several agents (a conversation) is
    /// split equally between them, so a share can be fractional.
    public private(set) var callsByAgentDay: [String: Double] = [:]
    public private(set) var callsByKind: [String: Int] = [:]
    public private(set) var totalCalls = 0
    public private(set) var totalInputTokens = 0
    public private(set) var totalOutputTokens = 0
    public private(set) var totalWallSeconds = 0.0
    /// Largest single call, counted as CLAUDE.md defines a prompt: input (instructions, prompt,
    /// schema) plus the response.
    public private(set) var largestPromptTokens = 0
    /// The same peak per `BrainCallKind`, so an oversized call kind is visible in the report.
    public private(set) var largestPromptTokensByKind: [String: Int] = [:]
    /// Calls whose input plus response exceeded `maxPromptTokens`.
    public private(set) var overBudgetPrompts = 0

    public init() {}

    public mutating func record(_ kind: BrainCallKind, agent: AgentID, day: Int, receipt: BrainCallReceipt) {
        record(kind, agents: [agent], day: day, receipt: receipt)
    }

    /// One call on behalf of `agents`: counted once in the totals, an equal share on each
    /// agent's day. The per-agent-day limit is a worst case, and every participant's device
    /// would run the same inference.
    public mutating func record(_ kind: BrainCallKind, agents: [AgentID], day: Int, receipt: BrainCallReceipt) {
        let share = 1 / Double(max(1, agents.count))
        for agent in agents {
            callsByAgentDay["\(agent.rawValue)/\(day)", default: 0] += share
        }
        callsByKind[kind.rawValue, default: 0] += 1
        totalCalls += 1
        totalInputTokens += receipt.inputTokens
        totalOutputTokens += receipt.outputTokens
        totalWallSeconds += receipt.wallSeconds
        let promptTokens = receipt.inputTokens + receipt.outputTokens
        largestPromptTokens = max(largestPromptTokens, promptTokens)
        largestPromptTokensByKind[kind.rawValue] = max(largestPromptTokensByKind[kind.rawValue] ?? 0, promptTokens)
        if promptTokens > Self.maxPromptTokens {
            overBudgetPrompts += 1
        }
    }

    public func summary() -> BudgetSummary {
        let agentDays = callsByAgentDay.count
        // A half share rounds up: the limit is a ceiling, not a target.
        let maxPerAgentDay = Int((callsByAgentDay.values.max() ?? 0).rounded(.up))
        let mean = agentDays == 0 ? 0 : Double(totalCalls) / Double(agentDays)
        return BudgetSummary(
            totalCalls: totalCalls,
            agentDays: agentDays,
            meanCallsPerAgentDay: mean,
            maxCallsPerAgentDay: maxPerAgentDay,
            largestPromptTokens: largestPromptTokens,
            largestPromptTokensByKind: largestPromptTokensByKind,
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
    public var largestPromptTokensByKind: [String: Int]
    public var overBudgetPrompts: Int
    public var callsByKind: [String: Int]
    public var totalInputTokens: Int
    public var totalOutputTokens: Int
    public var totalWallSeconds: Double
    public var withinBudget: Bool
}
