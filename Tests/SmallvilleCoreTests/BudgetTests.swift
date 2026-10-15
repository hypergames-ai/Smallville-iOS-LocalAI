import Testing

@testable import SmallvilleCore

@Suite("Call budget")
struct BudgetTests {
    @Test("oversized prompts are counted and fail the budget")
    func oversizedPrompt() {
        var budget = CallBudget()
        budget.record(
            .planHour, agent: AgentID("a"), day: 0,
            receipt: BrainCallReceipt(inputTokens: 3500, outputTokens: 10, wallSeconds: 0.1))
        let summary = budget.summary()
        #expect(summary.overBudgetPrompts == 1)
        #expect(summary.largestPromptTokens == 3500)
        #expect(!summary.withinBudget)
    }

    @Test("too many calls in one agent-day fail the budget")
    func tooManyCalls() {
        var budget = CallBudget()
        for _ in 0...CallBudget.maxCallsPerAgentDay {
            budget.record(
                .converse, agent: AgentID("a"), day: 1,
                receipt: BrainCallReceipt(inputTokens: 100, outputTokens: 10, wallSeconds: 0))
        }
        let summary = budget.summary()
        #expect(summary.maxCallsPerAgentDay == CallBudget.maxCallsPerAgentDay + 1)
        #expect(!summary.withinBudget)
    }

    @Test("a shared call moves both agents' day counts together and counts once in the totals")
    func sharedCall() {
        var budget = CallBudget()
        let receipt = BrainCallReceipt(inputTokens: 500, outputTokens: 200, wallSeconds: 3)
        budget.record(.converse, agents: [AgentID("a"), AgentID("b")], day: 0, receipt: receipt)
        budget.record(.converse, agents: [AgentID("a"), AgentID("b")], day: 0, receipt: receipt)
        #expect(budget.callsByAgentDay["a/0"] == 1)
        #expect(budget.callsByAgentDay["b/0"] == 1)
        #expect(budget.callsByAgentDay["a/0"] == budget.callsByAgentDay["b/0"])

        let summary = budget.summary()
        #expect(summary.totalCalls == 2)
        #expect(summary.callsByKind["converse"] == 2)
        #expect(summary.maxCallsPerAgentDay == 1)
        #expect(summary.totalInputTokens == 1000)

        budget.record(.converse, agents: [AgentID("a"), AgentID("b")], day: 0, receipt: receipt)
        #expect(budget.summary().maxCallsPerAgentDay == 2, "a half share rounds up against the limit")
    }

    @Test("a quiet day is within budget")
    func quietDay() {
        var budget = CallBudget()
        budget.record(
            .planDay, agent: AgentID("a"), day: 0,
            receipt: BrainCallReceipt(inputTokens: 900, outputTokens: 100, wallSeconds: 2))
        let summary = budget.summary()
        #expect(summary.withinBudget)
        #expect(summary.meanCallsPerAgentDay == 1)
        #expect(summary.callsByKind["planDay"] == 1)
    }
}
