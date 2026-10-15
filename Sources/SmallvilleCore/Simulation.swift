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
        /// Sum of poignancy since the last reflection that triggers one. 60 is a stub-era
        /// default; tune after the first `--fm` run, when real ratings replace the stub's.
        public var reflectionImportanceThreshold = 60
        /// Hard ceiling on reflection calls per agent per day; the threshold decides when, this decides how many.
        public var maxReflectionsPerAgentDay = 3
        /// Two reflections are never closer than this.
        public var reflectionSpacingMinutes = 60
        /// Observations are rated in one batched call every N waking hours.
        public var poignancyBatchHours = 4
        public var retrievalLimit = 8
        public var sleepHour = 22
        /// Most locations listed in a prompt; keeps the hour-plan prompt flat as the town grows.
        public var maxLocationsInContext = 12
        /// Most observations rated in one `ratePoignancy` call; the rest wait for the next batch.
        public var maxPoignancyBatch = 24
        /// An agent's own action or arrival identical to one of its last N memories is not stored again.
        public var perceptionRetention = 5
        /// Most storylines mentioned in a prompt (nearest event first), so whispers can't grow it.
        public var maxStorylinesInContext = 4
        /// Ticks an agent must spend at a storyline's venue around its event time to count as attending.
        public var minimumDwellSamples = 2

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
        /// Where the agent is walking to and when it gets there; nil when settled.
        var travel: (to: LocationID, arrives: SimTime)?
        var lastConversation: SimTime?
        var conversationsToday = 0
        var lastReflection: SimTime?
        var reflectionsToday = 0
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
            StorylineDetector.detect(
                $0, memories: memories, events: events, positions: positions,
                minimumDwellSamples: configuration.minimumDwellSamples)
        }
    }

    // MARK: - Planning

    private func isAwake(_ runtime: AgentRuntime) -> Bool {
        now.hour >= runtime.profile.wakeHour && now.hour < configuration.sleepHour
    }

    private func makeContext(for runtime: inout AgentRuntime, query: String) -> AgentContext {
        let memories = runtime.memory.retrieve(
            query: embedder.embed(query), now: now, limit: configuration.retrievalLimit)
        // Upcoming events first (soonest first), then past ones (most recent first), then the
        // undated; the cap must never let old events crowd out a new one.
        func rank(_ storyline: Storyline) -> (Int, Int, StorylineID) {
            guard let time = storyline.eventTime else { return (2, 0, storyline.id) }
            return time >= now
                ? (0, time.minutes - now.minutes, storyline.id) : (1, now.minutes - time.minutes, storyline.id)
        }
        let known = Array(
            storylines.values.filter { runtime.memory.knows($0.id) }
                .sorted { rank($0) < rank($1) }
                .prefix(configuration.maxStorylinesInContext))
        let here =
            world.location(runtime.location)
            ?? Location(
                id: runtime.location, name: runtime.location.rawValue, sector: "", arena: "", objects: [],
                isPublic: false)
        return AgentContext(
            profile: runtime.profile, now: now, location: here, relevantMemories: memories,
            knownLocations: knownLocations(for: runtime, storylines: known), activeStorylines: known,
            dayPlan: runtime.dayPlan, currentEntry: runtime.dayPlan?.entry(at: now.hour))
    }

    /// The places an agent may choose from, in a fixed order: workplace, favorite spot, any
    /// storyline venue it knows about, home, then public places by id, capped so the prompt does
    /// not grow with the town. The order is also the hour-plan schema's choice order, so daytime
    /// places come before home.
    private func knownLocations(for runtime: AgentRuntime, storylines: [Storyline]) -> [Location] {
        var ids = [runtime.profile.workplace, runtime.profile.favoriteSpot]
        ids += storylines.compactMap(\.targetLocation)
        ids.append(runtime.profile.home)
        ids += world.publicLocations.map(\.id)
        var seen = Set<LocationID>()
        var result: [Location] = []
        for id in ids where seen.insert(id).inserted {
            guard let location = world.location(id) else { continue }
            result.append(location)
            if result.count == configuration.maxLocationsInContext { break }
        }
        // Venues can fill a tight cap before home is reached; home is never cut, it takes the last slot.
        if let home = world.location(runtime.profile.home), !result.contains(home) {
            if result.count >= configuration.maxLocationsInContext, !result.isEmpty { result.removeLast() }
            result.append(home)
        }
        return result
    }

    private func planDayIfNeeded(_ id: AgentID) async throws {
        guard var runtime = agents[id], runtime.dayPlanDay != now.day, isAwake(runtime) else { return }
        let context = makeContext(for: &runtime, query: "\(runtime.profile.name)'s plan for today")
        runtime.dayPlanDay = now.day
        runtime.conversationsToday = 0
        runtime.reflectionsToday = 0
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
            var plan = response.value.normalized(hour: now.hour)
            // Places are a lookup against the map; an unknown one means "stay where the previous
            // action was", so a bad name never teleports anyone.
            var previous = context.location.id
            plan.actions = plan.actions.map { action in
                var action = action
                action.location = world.resolve(action.location.rawValue) ?? previous
                previous = action.location
                return action
            }
            if plan.actions.isEmpty {
                let activity = context.currentEntry.map { "continuing to \($0.activity)" } ?? "idling"
                plan.actions = [
                    PlannedAction(
                        startMinute: 0, durationMinutes: 60, activity: activity, location: context.location.id,
                        emoji: "🙂", event: EventTriple(subject: context.profile.name, predicate: "is", object: activity)
                    )
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
        if let plan = runtime.hourPlan,
            let action = plan.action(atMinute: now.minuteOfHour) ?? plan.actions.last,
            runtime.currentAction != action
        {
            runtime.currentAction = action
            events.append(.acted(agent: id, action: action, at: now))
            observe(&runtime, "\(action.event.subject) \(action.event.predicate) \(action.event.object)", poignancy: 2)
            if action.location != runtime.location {
                // Travel is abstract: one tick on the way, then arrival. The position log shows
                // the origin until then.
                let minutes = world.travelMinutes(from: runtime.location, to: action.location)
                runtime.travel = (to: action.location, arrives: now.advanced(by: minutes))
            } else {
                runtime.travel = nil
            }
        }
        if let travel = runtime.travel, now >= travel.arrives {
            runtime.travel = nil
            runtime.location = travel.to
            events.append(.moved(agent: id, to: travel.to, at: now))
            let placeName = world.location(travel.to)?.name ?? travel.to.rawValue
            let activity = runtime.currentAction?.activity ?? "be there"
            observe(&runtime, "\(runtime.profile.name) arrived at \(placeName) to \(activity)", poignancy: 3)
        }
    }

    /// Stores an observation with a default score and queues it for the batched rating. With
    /// `retained`, a text stored within the last few memories is skipped (the paper's retention
    /// rule); sightings of others pass `false` because `seen` already dedupes them.
    private func observe(_ runtime: inout AgentRuntime, _ text: String, poignancy: Int, retained: Bool = true) {
        if retained, runtime.memory.recentlyContains(text, within: configuration.perceptionRetention) {
            return
        }
        let node = runtime.memory.append(
            kind: .observation, text: text, poignancy: poignancy, provenance: .observed,
            embedding: embedder.embed(text), at: now)
        runtime.pendingPoignancy.append(node.id)
    }

    // MARK: - Perception and conversation

    /// Who is present where. An agent on the way somewhere is nowhere: still logged at the place
    /// it left (the position log is unchanged), but it neither perceives nor talks there.
    private func groupedByLocation() -> [LocationID: [AgentID]] {
        let present = order.filter { agents[$0]?.travel == nil }
        return Dictionary(grouping: present) { agents[$0]?.location ?? LocationID("unknown") }
    }

    /// Each awake agent notices what co-located agents are doing, once per distinct activity
    /// while they stay together; parting and meeting again makes the same activity new.
    private func perceive() {
        let grouped = groupedByLocation()
        for id in order {
            guard var runtime = agents[id] else { continue }
            let here = runtime.travel == nil ? grouped[runtime.location] ?? [] : []
            runtime.seen = runtime.seen.filter { here.contains($0.key) }
            guard isAwake(runtime) else {
                agents[id] = runtime
                continue
            }
            for other in here where other != id {
                guard let otherRuntime = agents[other], let action = otherRuntime.currentAction else { continue }
                guard runtime.seen[other] != action.activity else { continue }
                runtime.seen[other] = action.activity
                observe(
                    &runtime, "\(runtime.profile.name) saw \(otherRuntime.profile.name) \(action.activity)",
                    poignancy: 2, retained: false)
            }
            agents[id] = runtime
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

    /// Strangers meet in public; at a private place one of the two has to know the other.
    private func mayMeet(_ a: AgentID, _ b: AgentID, at location: LocationID) -> Bool {
        if world.location(location)?.isPublic ?? false { return true }
        guard let profileA = agents[a]?.profile, let profileB = agents[b]?.profile else { return false }
        return profileA.relationships[b] != nil || profileB.relationships[a] != nil
    }

    /// Rules, not a model call: co-located, awake, not in cooldown, under the daily cap, and
    /// allowed to meet there. One pair per place per tick, chosen with the seeded generator.
    private func converseWhereColocated() async throws {
        let grouped = groupedByLocation()
        for location in grouped.keys.sorted() {
            guard let ids = grouped[location], ids.count > 1 else { continue }
            let eligible = ids.filter { canTalk($0) }.shuffled(using: &rng)
            guard eligible.count >= 2 else { continue }
            var pair: (AgentID, AgentID)?
            outer: for (index, a) in eligible.enumerated() {
                for b in eligible[(index + 1)...] where mayMeet(a, b, at: location) {
                    pair = (a, b)
                    break outer
                }
            }
            guard let (a, b) = pair else { continue }
            try await converse(a, b, at: location)
        }
    }

    private func converse(_ a: AgentID, _ b: AgentID, at location: LocationID) async throws {
        guard var runtimeA = agents[a], var runtimeB = agents[b] else { return }
        // The focal point is the other person: what they are about surfaces memories about them.
        let contextA = makeContext(
            for: &runtimeA, query: "talking with \(runtimeB.profile.name). \(runtimeB.profile.currently)")
        let contextB = makeContext(
            for: &runtimeB, query: "talking with \(runtimeA.profile.name). \(runtimeA.profile.currently)")
        runtimeA.lastConversation = now
        runtimeB.lastConversation = now
        runtimeA.conversationsToday += 1
        runtimeB.conversationsToday += 1
        agents[a] = runtimeA
        agents[b] = runtimeB

        let request = ConversationRequest(
            initiator: contextA, partner: contextB, maxTurns: configuration.maxConversationTurns)
        // What each side knew before the conversation; provenance and act checks are judged against it.
        let knewBefore: [AgentID: Set<StorylineID>] = [a: knownStorylines(of: a), b: knownStorylines(of: b)]
        do {
            let response = try await brain.converse(request)
            // One call, half on each participant's day: the budget is a per-agent worst case.
            record(.converse, [a, b], response.receipt)
            var conversation = response.value
            conversation.initiator = a
            conversation.partner = b
            conversation.turns = Array(conversation.turns.prefix(configuration.maxConversationTurns))
            conversation.conveyedStorylines = conversation.conveyedStorylines.filter { storylines[$0] != nil }
            let participants: Set<AgentID> = [a, b]
            conversation.acts = conversation.acts.filter { act in
                guard participants.contains(act.from), participants.contains(act.to), act.from != act.to else {
                    return false
                }
                // Nobody invites to something they had not heard of, and an acceptance answers
                // someone who had; otherwise the model made the act up.
                guard let storyline = act.storyline else { return true }
                switch act.kind {
                case .invite: return knewBefore[act.from]?.contains(storyline) ?? false
                case .accept: return knewBefore[act.to]?.contains(storyline) ?? false
                default: return true
                }
            }
            events.append(.conversed(conversation, at: now, location: location))
            remember(
                conversation, for: a, toldBy: b, summary: conversation.initiatorSummary, knewBefore: knewBefore[a] ?? []
            )
            remember(
                conversation, for: b, toldBy: a, summary: conversation.partnerSummary, knewBefore: knewBefore[b] ?? [])
        } catch let error as BrainError {
            fail(a, .converse, error)
        }
    }

    private func knownStorylines(of id: AgentID) -> Set<StorylineID> {
        guard let memory = agents[id]?.memory else { return [] }
        return Set(storylines.keys.filter { memory.knows($0) })
    }

    /// Stores one side of a conversation. Provenance is judged against `knewBefore`, never
    /// against memory that this conversation has already added to.
    private func remember(
        _ conversation: Conversation, for id: AgentID, toldBy other: AgentID, summary: String,
        knewBefore: Set<StorylineID>
    ) {
        guard var runtime = agents[id] else { return }
        let newToMe = conversation.conveyedStorylines.filter { !knewBefore.contains($0) }
        let provenance: Provenance = newToMe.isEmpty ? .observed : .told(by: other, at: now)
        let node = runtime.memory.append(
            kind: .chat, text: summary, poignancy: 5, provenance: provenance,
            storylines: Set(conversation.conveyedStorylines), embedding: embedder.embed(summary), at: now)
        runtime.pendingPoignancy.append(node.id)

        // Social acts leave traces the agent can act on later: an accepted invitation becomes a
        // plan (so a real model has something to follow), an invitation sent is remembered.
        for act in conversation.acts where act.from == id {
            guard let storylineID = act.storyline, let storyline = storylines[storylineID] else { continue }
            let otherName = agents[act.to]?.profile.name ?? act.to.rawValue
            switch act.kind {
            case .accept:
                guard let time = storyline.eventTime, let venue = storyline.targetLocation else { continue }
                let place = world.location(venue)?.name ?? venue.rawValue
                let text = "\(runtime.profile.name) plans to go to \(storyline.title) at \(place) on \(time)"
                // Accepting is learning only if this storyline itself was new.
                let learned: Provenance = knewBefore.contains(storylineID) ? .observed : .told(by: other, at: now)
                let plan = runtime.memory.append(
                    kind: .plan, text: text, poignancy: 6, provenance: learned,
                    storylines: [storylineID], embedding: embedder.embed(text), at: now)
                runtime.pendingPoignancy.append(plan.id)
            case .invite:
                let text = "\(runtime.profile.name) invited \(otherName) to \(storyline.title)"
                let invite = runtime.memory.append(
                    kind: .observation, text: text, poignancy: 4, provenance: .observed,
                    storylines: [storylineID], embedding: embedder.embed(text), at: now)
                runtime.pendingPoignancy.append(invite.id)
            default:
                break
            }
        }
        agents[id] = runtime
    }

    // MARK: - Poignancy and reflection

    private func ratePendingPoignancyIfDue(_ id: AgentID) async throws {
        guard var runtime = agents[id], !runtime.pendingPoignancy.isEmpty, isAwake(runtime) else { return }
        guard now.isHourBoundary, now.hour % configuration.poignancyBatchHours == 0 else { return }
        let key = now.day * 24 + now.hour
        guard runtime.lastPoignancyKey != key else { return }
        runtime.lastPoignancyKey = key

        let ids = Array(runtime.pendingPoignancy.prefix(configuration.maxPoignancyBatch))
        runtime.pendingPoignancy.removeFirst(ids.count)
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

    /// The paper's trigger (accumulated importance) behind two budget rules: a daily cap and a
    /// minimum spacing. The focal point is what happened recently, so retrieval pulls the
    /// memories those events relate to.
    private func reflectIfDue(_ id: AgentID) async throws {
        guard var runtime = agents[id], isAwake(runtime),
            runtime.memory.importanceSinceReflection >= configuration.reflectionImportanceThreshold,
            runtime.reflectionsToday < configuration.maxReflectionsPerAgentDay
        else { return }
        if let last = runtime.lastReflection, now.minutes - last.minutes < configuration.reflectionSpacingMinutes {
            return
        }
        let focal = runtime.memory.recent(10).map(\.text).joined(separator: " ")
        let context = makeContext(for: &runtime, query: focal)
        runtime.memory.markReflected()
        runtime.lastReflection = now
        runtime.reflectionsToday += 1
        agents[id] = runtime
        do {
            let response = try await brain.reflect(context)
            record(.reflect, id, response.receipt)
            guard var updated = agents[id] else { return }
            for var reflection in response.value {
                // Only memories this agent actually has can be evidence; an insight with none is dropped.
                let cited = reflection.evidence.compactMap { evidenceID in
                    updated.memory.nodes.first { $0.id == evidenceID }
                }
                guard !cited.isEmpty else { continue }
                reflection.evidence = cited.map(\.id)
                let storylines = Set(cited.flatMap(\.storylines))
                let node = updated.memory.append(
                    kind: .reflection, text: reflection.insight, poignancy: 5,
                    provenance: .reflected(from: reflection.evidence), storylines: storylines,
                    embedding: embedder.embed(reflection.insight), at: now)
                updated.pendingPoignancy.append(node.id)
                events.append(.reflected(agent: id, reflection: reflection, at: now))
            }
            agents[id] = updated
        } catch let error as BrainError {
            fail(id, .reflect, error)
        }
    }

    // MARK: - Accounting

    private func record(_ kind: BrainCallKind, _ id: AgentID, _ receipt: BrainCallReceipt) {
        record(kind, [id], receipt)
    }

    /// One call made on behalf of several agents (a conversation), shared across their days.
    private func record(_ kind: BrainCallKind, _ ids: [AgentID], _ receipt: BrainCallReceipt) {
        budget.record(kind, agents: ids, day: now.day, receipt: receipt)
    }

    private func fail(_ id: AgentID, _ kind: BrainCallKind, _ error: BrainError) {
        events.append(.brainFailed(agent: id, kind: kind, reason: String(describing: error), at: now))
    }
}
