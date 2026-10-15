import Foundation

/// The whole town. Owns every agent's memory and state, advances time one tick at a time,
/// asks the brain for a bounded number of decisions, and records everything in `events`.
public actor Simulation {
    /// Knobs that shape the call budget. Change them here, not inline.
    public struct Configuration: Sendable {
        public var seed: UInt64 = 42
        public var maxConversationTurns = 6
        public var conversationCooldownMinutes = 120
        public var maxConversationsPerAgentDay = 4
        /// Sum of poignancy since the last reflection that triggers one.
        public var reflectionImportanceThreshold = 40
        /// Observations are rated in one batched call every N waking hours.
        public var poignancyBatchHours = 4
        public var retrievalLimit = 8
        public var sleepHour = 22

        public init() {}
    }

    /// A read-only view of one agent for the UI.
    public struct AgentSnapshot: Hashable, Sendable, Identifiable {
        public var id: AgentID
        public var name: String
        public var location: LocationID
        public var activity: String
        public var emoji: String
        public var memoryCount: Int
    }

    /// A read-only view of the town for the UI.
    public struct Snapshot: Sendable {
        public var now: SimTime
        public var agents: [AgentSnapshot]
        public var eventCount: Int
        public var brainFailures: Int
        public var budget: BudgetSummary
    }

    struct AgentRuntime {
        var profile: AgentProfile
        var memory = MemoryStream()
        var location: LocationID
        var dayPlan: DayPlan?
        var dayPlanDay: Int?
        var hourPlan: HourPlan?
        var hourPlanKey: Int?
        var currentAction: PlannedAction?
        var lastConversation: SimTime?
        var conversationsToday = 0
        var pendingPoignancy: [Int] = []
        var lastPoignancyKey: Int?
        var seen: [AgentID: String] = [:]

        init(profile: AgentProfile) {
            self.profile = profile
            self.location = profile.home
        }
    }

    public let world: WorldMap
    public let configuration: Configuration
    public private(set) var now: SimTime
    public private(set) var events: [SimEvent] = []
    public private(set) var positions: [PositionSample] = []
    public private(set) var budget = CallBudget()
    public private(set) var storylines: [StorylineID: Storyline] = [:]

    private var agents: [AgentID: AgentRuntime] = [:]
    /// Agents in a fixed order so every loop is deterministic.
    private let order: [AgentID]
    private let brain: any AgentBrain
    private let embedder: any Embedder
    private var rng: SeededRandom

    public init(
        world: WorldMap, profiles: [AgentProfile], brain: any AgentBrain, embedder: any Embedder = HashingEmbedder(),
        configuration: Configuration = Configuration(), startingAt start: SimTime = SimTime(minutes: 7 * 60)
    ) {
        self.world = world
        self.configuration = configuration
        self.now = start
        self.brain = brain
        self.embedder = embedder
        self.rng = SeededRandom(seed: configuration.seed)
        self.order = profiles.map(\.id).sorted()
        var runtimes: [AgentID: AgentRuntime] = [:]
        for profile in profiles {
            runtimes[profile.id] = AgentRuntime(profile: profile)
        }
        self.agents = runtimes
    }

    // MARK: - Player input

    /// Plants a thought in an agent. The memory is tagged with the storyline so it can be traced.
    public func whisper(_ storyline: Storyline, text: String? = nil) {
        storylines[storyline.id] = storyline
        let body = text ?? storyline.seedText
        guard var runtime = agents[storyline.seededIn] else { return }
        runtime.memory.append(
            kind: .whisper, text: body, poignancy: 8, provenance: .whispered, storylines: [storyline.id],
            embedding: embedder.embed(body), at: now)
        agents[storyline.seededIn] = runtime
        events.append(.whispered(agent: storyline.seededIn, storyline: storyline.id, at: now))
    }

    // MARK: - Stepping

    public func run(minutes: Int) async throws {
        let end = now.advanced(by: minutes)
        while now < end {
            try await step()
        }
    }

    /// Advances one tick (10 game-minutes).
    public func step() async throws {
        for id in order {
            try await planDayIfNeeded(id)
            try await planHourIfNeeded(id)
            advanceAction(id)
        }
        perceive()
        try await converseWhereColocated()
        for id in order {
            try await ratePendingPoignancyIfDue(id)
            try await reflectIfDue(id)
        }
        now = now.advanced(by: SimTime.minutesPerTick)
    }

    // MARK: - Reading

    public func snapshot() -> Snapshot {
        let agentSnapshots = order.compactMap { id -> AgentSnapshot? in
            guard let runtime = agents[id] else { return nil }
            return AgentSnapshot(
                id: id, name: runtime.profile.name, location: runtime.location,
                activity: runtime.currentAction?.activity ?? "idle",
                emoji: runtime.currentAction?.emoji ?? "💤", memoryCount: runtime.memory.nodes.count)
        }
        let failures = events.reduce(0) { count, event in
            if case .brainFailed = event { return count + 1 }
            return count
        }
        return Snapshot(
            now: now, agents: agentSnapshots, eventCount: events.count, brainFailures: failures,
            budget: budget.summary())
    }

    public func memories(of agent: AgentID) -> [MemoryNode] {
        agents[agent]?.memory.nodes ?? []
    }

    public func profile(of agent: AgentID) -> AgentProfile? {
        agents[agent]?.profile
    }

    /// Runs the detector over every planted storyline.
    public func discoveries() -> [Discovery] {
        let memories = agents.mapValues(\.memory)
        return storylines.values.sorted { $0.id < $1.id }.map {
            StorylineDetector.detect($0, memories: memories, events: events, positions: positions)
        }
    }

    // MARK: - Planning

    private func isAwake(_ runtime: AgentRuntime) -> Bool {
        now.hour >= runtime.profile.wakeHour && now.hour < configuration.sleepHour
    }

    private func makeContext(for runtime: inout AgentRuntime, query: String) -> AgentContext {
        let memories = runtime.memory.retrieve(
            query: embedder.embed(query), now: now, limit: configuration.retrievalLimit)
        let known = storylines.values.filter { runtime.memory.knows($0.id) }.sorted { $0.id < $1.id }
        let here =
            world.location(runtime.location)
            ?? Location(
                id: runtime.location, name: runtime.location.rawValue, sector: "", arena: "", objects: [],
                isPublic: false)
        var locations = world.publicLocations
        if let home = world.location(runtime.profile.home) {
            locations.append(home)
        }
        return AgentContext(
            profile: runtime.profile, now: now, location: here, relevantMemories: memories,
            knownLocations: locations, activeStorylines: known, dayPlan: runtime.dayPlan)
    }

    private func planDayIfNeeded(_ id: AgentID) async throws {
        guard var runtime = agents[id], runtime.dayPlanDay != now.day, isAwake(runtime) else { return }
        let context = makeContext(for: &runtime, query: "\(runtime.profile.name)'s plan for today")
        runtime.dayPlanDay = now.day
        runtime.conversationsToday = 0
        agents[id] = runtime
        do {
            let response = try await brain.planDay(context)
            record(.planDay, id, response.receipt)
            guard var updated = agents[id] else { return }
            updated.dayPlan = response.value
            let outline = response.value.entries.map { "\($0.hour):00 \($0.activity)" }.joined(separator: "; ")
            let text = "\(updated.profile.name)'s plan for today: \(outline)"
            updated.memory.append(
                kind: .plan, text: text, poignancy: 3, provenance: .observed, embedding: embedder.embed(text),
                at: now)
            agents[id] = updated
        } catch let error as BrainError {
            fail(id, .planDay, error)
        }
    }

    private func planHourIfNeeded(_ id: AgentID) async throws {
        guard var runtime = agents[id] else { return }
        let key = now.day * 24 + now.hour
        guard runtime.hourPlanKey != key else { return }
        runtime.hourPlanKey = key

        guard isAwake(runtime), let dayPlan = runtime.dayPlan else {
            let sleeping = PlannedAction(
                startMinute: 0, durationMinutes: 60, activity: "sleeping", location: runtime.profile.home,
                emoji: "😴", event: EventTriple(subject: runtime.profile.name, predicate: "is", object: "sleeping"))
            runtime.hourPlan = HourPlan(hour: now.hour, actions: [sleeping])
            agents[id] = runtime
            return
        }

        let context = makeContext(for: &runtime, query: "what \(runtime.profile.name) should do at \(now.hour):00")
        agents[id] = runtime
        do {
            let response = try await brain.planHour(context, dayPlan: dayPlan)
            record(.planHour, id, response.receipt)
            var plan = response.value
            plan.hour = now.hour
            plan.actions = plan.actions.map { action in
                var action = action
                if !world.contains(action.location) {
                    action.location = context.location.id
                }
                return action
            }
            if plan.actions.isEmpty {
                plan.actions = [
                    PlannedAction(
                        startMinute: 0, durationMinutes: 60, activity: "idling", location: context.location.id,
                        emoji: "🙂", event: EventTriple(subject: context.profile.name, predicate: "is", object: "idle"))
                ]
            }
            agents[id]?.hourPlan = plan
        } catch let error as BrainError {
            fail(id, .planHour, error)
        }
    }

    private func advanceAction(_ id: AgentID) {
        guard var runtime = agents[id] else { return }
        defer {
            positions.append(PositionSample(agent: id, location: runtime.location, at: now))
            agents[id] = runtime
        }
        guard let plan = runtime.hourPlan,
            let action = plan.action(atMinute: now.minuteOfHour) ?? plan.actions.last
        else { return }
        guard runtime.currentAction != action else { return }

        runtime.currentAction = action
        events.append(.acted(agent: id, action: action, at: now))
        if action.location != runtime.location {
            runtime.location = action.location
            events.append(.moved(agent: id, to: action.location, at: now))
            let placeName = world.location(action.location)?.name ?? action.location.rawValue
            let text = "\(runtime.profile.name) arrived at \(placeName) to \(action.activity)"
            let node = runtime.memory.append(
                kind: .observation, text: text, poignancy: 3, provenance: .observed,
                embedding: embedder.embed(text), at: now)
            runtime.pendingPoignancy.append(node.id)
        }
    }

    // MARK: - Perception and conversation

    private func groupedByLocation() -> [LocationID: [AgentID]] {
        Dictionary(grouping: order) { agents[$0]?.location ?? LocationID("unknown") }
    }

    /// Each agent notices what co-located agents are doing, once per distinct activity.
    private func perceive() {
        let grouped = groupedByLocation()
        for location in grouped.keys.sorted() {
            guard let ids = grouped[location], ids.count > 1 else { continue }
            for id in ids {
                guard var runtime = agents[id] else { continue }
                for other in ids where other != id {
                    guard let otherRuntime = agents[other], let action = otherRuntime.currentAction else { continue }
                    guard runtime.seen[other] != action.activity else { continue }
                    runtime.seen[other] = action.activity
                    let text = "\(runtime.profile.name) saw \(otherRuntime.profile.name) \(action.activity)"
                    let node = runtime.memory.append(
                        kind: .observation, text: text, poignancy: 2, provenance: .observed,
                        embedding: embedder.embed(text), at: now)
                    runtime.pendingPoignancy.append(node.id)
                }
                agents[id] = runtime
            }
        }
    }

    private func canTalk(_ id: AgentID) -> Bool {
        guard let runtime = agents[id], isAwake(runtime) else { return false }
        guard runtime.conversationsToday < configuration.maxConversationsPerAgentDay else { return false }
        if let last = runtime.lastConversation,
            now.minutes - last.minutes < configuration.conversationCooldownMinutes
        {
            return false
        }
        return true
    }

    /// Rules, not a model call: co-located, awake, not in cooldown, under the daily cap.
    private func converseWhereColocated() async throws {
        let grouped = groupedByLocation()
        for location in grouped.keys.sorted() {
            guard let ids = grouped[location], ids.count > 1 else { continue }
            let eligible = ids.filter { canTalk($0) }
            guard eligible.count >= 2 else { continue }
            try await converse(eligible[0], eligible[1], at: location)
        }
    }

    private func converse(_ a: AgentID, _ b: AgentID, at location: LocationID) async throws {
        guard var runtimeA = agents[a], var runtimeB = agents[b] else { return }
        let contextA = makeContext(for: &runtimeA, query: "talking with \(runtimeB.profile.name)")
        let contextB = makeContext(for: &runtimeB, query: "talking with \(runtimeA.profile.name)")
        runtimeA.lastConversation = now
        runtimeB.lastConversation = now
        runtimeA.conversationsToday += 1
        runtimeB.conversationsToday += 1
        agents[a] = runtimeA
        agents[b] = runtimeB

        let request = ConversationRequest(
            initiator: contextA, partner: contextB, maxTurns: configuration.maxConversationTurns)
        do {
            let response = try await brain.converse(request)
            record(.converse, a, response.receipt)
            var conversation = response.value
            conversation.initiator = a
            conversation.partner = b
            conversation.turns = Array(conversation.turns.prefix(configuration.maxConversationTurns))
            conversation.conveyedStorylines = conversation.conveyedStorylines.filter { storylines[$0] != nil }
            conversation.acts = conversation.acts.filter { ($0.from == a || $0.from == b) && $0.from != $0.to }
            events.append(.conversed(conversation, at: now, location: location))
            remember(conversation, for: a, toldBy: b, summary: conversation.initiatorSummary)
            remember(conversation, for: b, toldBy: a, summary: conversation.partnerSummary)
        } catch let error as BrainError {
            fail(a, .converse, error)
        }
    }

    private func remember(_ conversation: Conversation, for id: AgentID, toldBy other: AgentID, summary: String) {
        guard var runtime = agents[id] else { return }
        let newToMe = conversation.conveyedStorylines.filter { !runtime.memory.knows($0) }
        let provenance: Provenance = newToMe.isEmpty ? .observed : .told(by: other, at: now)
        let node = runtime.memory.append(
            kind: .chat, text: summary, poignancy: 5, provenance: provenance,
            storylines: Set(conversation.conveyedStorylines), embedding: embedder.embed(summary), at: now)
        runtime.pendingPoignancy.append(node.id)
        agents[id] = runtime
    }

    // MARK: - Poignancy and reflection

    private func ratePendingPoignancyIfDue(_ id: AgentID) async throws {
        guard var runtime = agents[id], !runtime.pendingPoignancy.isEmpty, isAwake(runtime) else { return }
        guard now.isHourBoundary, now.hour % configuration.poignancyBatchHours == 0 else { return }
        let key = now.day * 24 + now.hour
        guard runtime.lastPoignancyKey != key else { return }
        runtime.lastPoignancyKey = key

        let ids = runtime.pendingPoignancy
        runtime.pendingPoignancy = []
        let texts = ids.compactMap { memoryID in runtime.memory.nodes.first { $0.id == memoryID }?.text }
        agents[id] = runtime
        do {
            let response = try await brain.ratePoignancy(texts, for: runtime.profile)
            record(.ratePoignancy, id, response.receipt)
            agents[id]?.memory.setPoignancy(zip(ids, response.value))
        } catch let error as BrainError {
            fail(id, .ratePoignancy, error)
        }
    }

    private func reflectIfDue(_ id: AgentID) async throws {
        guard var runtime = agents[id], isAwake(runtime),
            runtime.memory.importanceSinceReflection >= configuration.reflectionImportanceThreshold
        else { return }
        let context = makeContext(for: &runtime, query: "what \(runtime.profile.name) has learned recently")
        runtime.memory.markReflected()
        agents[id] = runtime
        do {
            let response = try await brain.reflect(context)
            record(.reflect, id, response.receipt)
            guard var updated = agents[id] else { return }
            for reflection in response.value {
                let storylines = Set(
                    reflection.evidence.compactMap { evidenceID in
                        updated.memory.nodes.first { $0.id == evidenceID }?.storylines
                    }.flatMap { $0 })
                updated.memory.append(
                    kind: .reflection, text: reflection.insight, poignancy: 6,
                    provenance: .reflected(from: reflection.evidence), storylines: storylines,
                    embedding: embedder.embed(reflection.insight), at: now)
                events.append(.reflected(agent: id, reflection: reflection, at: now))
            }
            agents[id] = updated
        } catch let error as BrainError {
            fail(id, .reflect, error)
        }
    }

    // MARK: - Accounting

    private func record(_ kind: BrainCallKind, _ id: AgentID, _ receipt: BrainCallReceipt) {
        budget.record(kind, agent: id, day: now.day, receipt: receipt)
    }

    private func fail(_ id: AgentID, _ kind: BrainCallKind, _ error: BrainError) {
        events.append(.brainFailed(agent: id, kind: kind, reason: String(describing: error), at: now))
    }
}
