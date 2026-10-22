import Testing

@testable import SmallvilleCore

@Suite("Conversation gating and provenance")
struct ConversationTests {
    private static let lounge = LocationID("the_ville:dorm_lounge")

    /// Two students who share a private lounge and, by default, have never met.
    static func strangers(acquainted: Bool) -> (WorldMap, [AgentProfile]) {
        var locations = WorldMap.smallvilleSubset().allLocations
        locations.append(
            Location(
                id: lounge, name: "Dorm lounge", sector: "Oak Hill College dorm", arena: "lounge", objects: [],
                isPublic: false))
        let ana = AgentProfile(
            id: AgentID("ana"), name: "Ana Novak", age: 20, innateTraits: "quiet", occupation: "student",
            lifestyle: "early riser", currently: "Ana is new in town.", home: lounge, workplace: WorldMap.library,
            favoriteSpot: WorldMap.park, wakeHour: 7, relationships: [:])
        let ben = AgentProfile(
            id: AgentID("ben"), name: "Ben Osei", age: 21, innateTraits: "calm", occupation: "student",
            lifestyle: "early riser", currently: "Ben is studying for finals.", home: lounge,
            workplace: WorldMap.library,
            favoriteSpot: WorldMap.park, wakeHour: 7,
            relationships: acquainted ? [AgentID("ana"): "a friend from class"] : [:])
        return (WorldMap(locations: locations), [ana, ben])
    }

    private static func conversations(in events: [SimEvent]) -> [(Conversation, SimTime)] {
        events.compactMap { event in
            if case .conversed(let conversation, let at, _) = event { return (conversation, at) }
            return nil
        }
    }

    @Test("cooldown and the daily cap hold even when everyone stays together all day")
    func cooldownAndCap() async throws {
        let brain = ScriptedBrain(planHour: { context, _ in
            HourPlan(
                hour: context.now.hour,
                actions: [
                    PlannedAction(
                        startMinute: 0, durationMinutes: 60, activity: "hanging out", location: WorldMap.hobbsCafe,
                        emoji: "☕️",
                        event: EventTriple(subject: context.profile.name, predicate: "is", object: "hanging out"))
                ])
        })
        var configuration = Simulation.Configuration()
        configuration.conversationCooldownMinutes = 120
        configuration.maxConversationsPerAgentDay = 4
        let simulation = Simulation(
            world: .smallvilleSubset(), profiles: AgentProfile.sample3, brain: brain, configuration: configuration)
        try await simulation.run(minutes: 24 * 60)

        let talks = Self.conversations(in: await simulation.events)
        #expect(talks.count >= 3, "people who sit together all day do talk")

        // Every conversation is charged half to each participant, so the shares add up to the
        // call count and both participants' days move by the same amount.
        let budget = await simulation.budget
        let shares = budget.callsByAgentDay.values.reduce(0, +)
        #expect(abs(shares - Double(budget.totalCalls)) < 1e-9)
        for (conversation, at) in talks {
            let initiatorShare = budget.callsByAgentDay["\(conversation.initiator.rawValue)/\(at.day)"] ?? 0
            let partnerShare = budget.callsByAgentDay["\(conversation.partner.rawValue)/\(at.day)"] ?? 0
            #expect(initiatorShare > 0 && partnerShare > 0)
        }
        let converseCalls = Double(budget.callsByKind["converse", default: 0])
        var halves = 0.0
        for share in budget.callsByAgentDay.values {
            halves += share - share.rounded(.down)
        }
        #expect(
            abs(halves.truncatingRemainder(dividingBy: 1)) < 1e-9 || converseCalls > 0,
            "fractions come only from shared calls")
        for agent in AgentProfile.sample3.map(\.id) {
            let mine = talks.filter { $0.0.initiator == agent || $0.0.partner == agent }.map(\.1)
            #expect(mine.count <= 4)
            for (earlier, later) in zip(mine, mine.dropFirst()) {
                #expect(later.minutes - earlier.minutes >= 120, "\(agent) talked again too soon")
            }
        }
    }

    @Test("strangers do not talk in a private place; acquaintances do")
    func privatePlaces() async throws {
        let (world, strangers) = Self.strangers(acquainted: false)
        let quiet = Simulation(world: world, profiles: strangers, brain: StubBrain())
        try await quiet.run(minutes: 2 * 60)  // 07:00–09:00, both at home in the lounge
        #expect(Self.conversations(in: await quiet.events).isEmpty)

        let (sameWorld, friends) = Self.strangers(acquainted: true)
        let social = Simulation(world: sameWorld, profiles: friends, brain: StubBrain())
        try await social.run(minutes: 2 * 60)
        #expect(!Self.conversations(in: await social.events).isEmpty)
    }

    @Test("a listener's first storyline memory is told-by someone who already knew, at a real conversation (seed 7)")
    func provenance() async throws {
        let simulation = ValentinesPartyTests.makeSimulation()
        await simulation.whisper(ValentinesPartyTests.party)
        try await simulation.run(minutes: 2 * SimTime.minutesPerDay)

        let party = ValentinesPartyTests.party.id
        let talks = Self.conversations(in: await simulation.events)
        var firstKnown: [AgentID: SimTime] = [:]
        for profile in AgentProfile.sample3 {
            firstKnown[profile.id] = await simulation.memories(of: profile.id).first { $0.storylines.contains(party) }?
                .created
        }
        #expect(firstKnown.count == 3, "everyone hears about the party")

        for profile in AgentProfile.sample3 where profile.id != AgentProfile.isabella.id {
            let first = try #require(await simulation.memories(of: profile.id).first { $0.storylines.contains(party) })
            guard case .told(let teller, let at) = first.provenance else {
                Issue.record("\(profile.id)'s first party memory should be told-by, got \(first.provenance)")
                continue
            }
            #expect(first.kind == .chat)
            #expect(try #require(firstKnown[teller]) < at, "\(teller) knew before telling \(profile.id)")
            #expect(
                talks.contains { $0.1 == at && Set([$0.0.initiator, $0.0.partner]) == [teller, profile.id] },
                "the told-by edge matches a conversed event")
        }
        let isabellaChats = await simulation.memories(of: AgentProfile.isabella.id).filter {
            $0.kind == .chat && $0.storylines.contains(party)
        }
        #expect(!isabellaChats.isEmpty)
        #expect(isabellaChats.allSatisfy { $0.provenance == .observed }, "the host never learns her own party")
    }

    @Test("accepting an invitation leaves a plan memory tagged with the storyline")
    func acceptedInvitationBecomesPlan() async throws {
        let simulation = ValentinesPartyTests.makeSimulation()
        await simulation.whisper(ValentinesPartyTests.party)
        try await simulation.run(minutes: 2 * SimTime.minutesPerDay)

        let discovery = try #require(await simulation.discoveries().first)
        #expect(discovery.accepted.count >= 1)
        for agent in discovery.accepted {
            let memories = await simulation.memories(of: agent)
            let plans = memories.filter { $0.kind == .plan && $0.storylines.contains(discovery.storyline) }
            #expect(plans.count == 1, "\(agent) accepted once and planned once")
            let plan = try #require(plans.first)
            #expect(plan.text.contains("plans to go to"))
            // The plan shares the provenance of the chat it came from, so it adds no diffusion edge.
            let chat = try #require(
                memories.first {
                    $0.kind == .chat && $0.created == plan.created && $0.storylines.contains(discovery.storyline)
                })
            #expect(plan.provenance == chat.provenance)
        }
        let edges = discovery.diffusion.map { "\($0.from)->\($0.to)" }
        #expect(Set(edges).count == edges.count, "one edge per pair")

        var invites = 0
        for profile in AgentProfile.sample3 {
            invites += await simulation.memories(of: profile.id).filter {
                $0.text.contains(" invited ") && $0.storylines.contains(discovery.storyline)
            }.count
        }
        #expect(invites == discovery.invited.count, "whoever invites remembers doing it, once per invitee")
        #expect(
            await simulation.memories(of: discovery.host).contains { $0.text.contains(" invited ") },
            "the host invited someone herself")
    }

    @Test("acts naming someone outside the conversation are dropped")
    func actHygiene() async throws {
        let brain = ScriptedBrain(converse: { request in
            let a = request.initiator.profile.id
            let b = request.partner.profile.id
            return Conversation(
                initiator: a, partner: b, turns: [ConversationTurn(speaker: a, text: "hi")],
                acts: [
                    SocialAct(kind: .gossip, from: a, to: AgentID("nobody"), topic: "x"),
                    SocialAct(kind: .ask, from: a, to: a, topic: "self"),
                    SocialAct(kind: .inform, from: a, to: b, topic: "kept"),
                ],
                conveyedStorylines: [], initiatorSummary: "a talked", partnerSummary: "b talked")
        })
        let simulation = Simulation(world: .smallvilleSubset(), profiles: AgentProfile.sample3, brain: brain)
        try await simulation.run(minutes: 24 * 60)

        let talks = Self.conversations(in: await simulation.events)
        #expect(!talks.isEmpty)
        for (conversation, _) in talks {
            #expect(conversation.acts.map(\.topic) == ["kept"])
        }
    }

    // MARK: - Knowledge before the conversation

    private static let ana = AgentID("ana")
    private static let ben = AgentID("ben")

    /// Two acquaintances who both live at the cafe, so they meet on the first tick.
    private static func cafeRegulars() -> [AgentProfile] {
        [("ana", "Ana Novak"), ("ben", "Ben Osei")].map { id, name in
            AgentProfile(
                id: AgentID(id), name: name, age: 30, innateTraits: "friendly", occupation: "barista",
                lifestyle: "early riser", currently: "\(name) works at the cafe.", home: WorldMap.hobbsCafe,
                workplace: WorldMap.hobbsCafe, favoriteSpot: WorldMap.park, wakeHour: 7, relationships: [:])
        }
    }

    private static func storyline(_ id: String, seededIn agent: AgentID) -> Storyline {
        Storyline(
            id: StorylineID(id), title: "\(id) event", seedText: "There is a \(id) event at the park tonight.",
            seededIn: agent, seededAt: SimTime(minutes: 7 * 60), targetLocation: WorldMap.park,
            eventTime: SimTime(minutes: 19 * 60))
    }

    /// Everyone spends the hour at `place(agent, hour)`, the cafe unless overridden.
    private static func staying(
        _ place: @escaping @Sendable (AgentID, Int) -> LocationID = { _, _ in WorldMap.hobbsCafe }
    ) -> @Sendable (AgentContext, DayPlan) async throws -> HourPlan? {
        { context, _ in
            HourPlan(
                hour: context.now.hour,
                actions: [
                    PlannedAction(
                        startMinute: 0, durationMinutes: 60, activity: "spending time",
                        location: place(context.profile.id, context.now.hour), emoji: "☕️",
                        event: EventTriple(subject: context.profile.name, predicate: "is", object: "spending time"))
                ])
        }
    }

    private static func scriptedTalk(acts: [SocialAct], conveyed: [StorylineID])
        -> @Sendable (ConversationRequest) async throws -> Conversation?
    {
        { request in
            Conversation(
                initiator: request.initiator.profile.id, partner: request.partner.profile.id,
                turns: [ConversationTurn(speaker: request.initiator.profile.id, text: "hello")], acts: acts,
                conveyedStorylines: conveyed, initiatorSummary: "we talked", partnerSummary: "we talked")
        }
    }

    @Test("an accepted invitation is told-by only if its own storyline was new to the acceptor")
    func acceptProvenanceIsPerStoryline() async throws {
        // Ana knows x and y; Ben already knows y. Ana conveys x, and Ben accepts y.
        let brain = ScriptedBrain(
            planHour: Self.staying(),
            converse: Self.scriptedTalk(
                acts: [
                    SocialAct(kind: .invite, from: Self.ana, to: Self.ben, topic: "y", storyline: StorylineID("y")),
                    SocialAct(kind: .accept, from: Self.ben, to: Self.ana, topic: "y", storyline: StorylineID("y")),
                ],
                conveyed: [StorylineID("x")]))
        let simulation = Simulation(world: .smallvilleSubset(), profiles: Self.cafeRegulars(), brain: brain)
        await simulation.whisper(Self.storyline("x", seededIn: Self.ana))
        await simulation.whisper(Self.storyline("y", seededIn: Self.ana))
        await simulation.whisper(Self.storyline("y", seededIn: Self.ben))
        try await simulation.run(minutes: 60)

        #expect(!Self.conversations(in: await simulation.events).isEmpty)
        let discoveries = await simulation.discoveries()
        let x = try #require(discoveries.first { $0.storyline == StorylineID("x") })
        let y = try #require(discoveries.first { $0.storyline == StorylineID("y") })
        #expect(x.diffusion.map { [$0.from, $0.to] } == [[Self.ana, Self.ben]])
        #expect(y.diffusion.isEmpty, "Ben knew y already; accepting it is not being told it")
        #expect(y.accepted == [Self.ben])
    }

    @Test("an invitation from someone who never knew the storyline, and its acceptance, are dropped")
    func uninformedInviteIsDropped() async throws {
        // Only Ana knows x, but the model has Ben invite Ana to it and Ana accept.
        let brain = ScriptedBrain(
            planHour: Self.staying(),
            converse: Self.scriptedTalk(
                acts: [
                    SocialAct(kind: .invite, from: Self.ben, to: Self.ana, topic: "x", storyline: StorylineID("x")),
                    SocialAct(kind: .accept, from: Self.ana, to: Self.ben, topic: "x", storyline: StorylineID("x")),
                ],
                conveyed: []))
        let simulation = Simulation(world: .smallvilleSubset(), profiles: Self.cafeRegulars(), brain: brain)
        await simulation.whisper(Self.storyline("x", seededIn: Self.ana))
        try await simulation.run(minutes: 60)

        #expect(!Self.conversations(in: await simulation.events).isEmpty)
        let x = try #require(await simulation.discoveries().first)
        #expect(x.knows == [Self.ana], "Ben never learned x, so he is not in knows")
        #expect(x.invited.isEmpty)
        #expect(x.accepted.isEmpty, "an acceptance of an invitation that was never made")
        #expect(x.diffusion.isEmpty)
    }

    @Test("hearing of an event is not being invited: an uninvited listener cannot invite anyone")
    func uninvitedListenerCannotInvite() async throws {
        // Ana tells Ben about x without inviting him; once both know it, the model has Ben invite Ana.
        let brain = ScriptedBrain(
            planHour: Self.staying(),
            converse: { request in
                let x = StorylineID("x")
                let bothKnow = [request.initiator, request.partner].allSatisfy {
                    $0.activeStorylines.contains { $0.id == x }
                }
                let acts =
                    bothKnow
                    ? [
                        SocialAct(kind: .invite, from: Self.ben, to: Self.ana, topic: "x", storyline: x),
                        SocialAct(kind: .accept, from: Self.ana, to: Self.ben, topic: "x", storyline: x),
                    ]
                    : [SocialAct(kind: .inform, from: Self.ana, to: Self.ben, topic: "x", storyline: x)]
                return Conversation(
                    initiator: request.initiator.profile.id, partner: request.partner.profile.id,
                    turns: [ConversationTurn(speaker: request.initiator.profile.id, text: "hello")], acts: acts,
                    conveyedStorylines: bothKnow ? [] : [x], initiatorSummary: "we talked about x",
                    partnerSummary: "we talked about x")
            })
        let simulation = Simulation(world: .smallvilleSubset(), profiles: Self.cafeRegulars(), brain: brain)
        await simulation.whisper(Self.storyline("x", seededIn: Self.ana))
        try await simulation.run(minutes: 6 * 60)

        #expect(Self.conversations(in: await simulation.events).count >= 2, "Ben had a chance to invite")
        let x = try #require(await simulation.discoveries().first)
        #expect(x.knows == [Self.ana, Self.ben], "Ben did hear of x")
        #expect(x.invited.isEmpty, "Ben was never invited, so his invitation is dropped")
        #expect(x.accepted.isEmpty)
    }

    @Test("accepting the host's ask counts as being invited even when the model filed the ask as a plan")
    func acceptImpliesInvite() async throws {
        // As seen on device: Isabella asks Maria to help with the party (kind `plan`), Maria accepts.
        let x = StorylineID("x")
        let brain = ScriptedBrain(
            planHour: Self.staying(),
            converse: Self.scriptedTalk(
                acts: [
                    SocialAct(kind: .plan, from: Self.ana, to: Self.ben, topic: "x help", storyline: x),
                    SocialAct(kind: .accept, from: Self.ben, to: Self.ana, topic: "x help", storyline: x),
                ],
                conveyed: [x]))
        let simulation = Simulation(world: .smallvilleSubset(), profiles: Self.cafeRegulars(), brain: brain)
        await simulation.whisper(Self.storyline("x", seededIn: Self.ana))
        try await simulation.run(minutes: 6 * 60)

        let talks = Self.conversations(in: await simulation.events).map(\.0)
        #expect(talks.count >= 2)
        let first = try #require(talks.first)
        #expect(first.acts.map(\.kind) == [.plan, .invite, .accept], "the invite goes right before the accept")
        #expect(talks.dropFirst().allSatisfy { !$0.acts.contains { $0.kind == .invite } }, "Ben is invited once")
        let discovery = try #require(await simulation.discoveries().first)
        #expect(discovery.invited == [Self.ben])
        #expect(discovery.accepted == [Self.ben])
        let remembered = await simulation.memories(of: Self.ana).filter { $0.text.contains(" invited ") }
        #expect(remembered.count == 1, "Ana remembers inviting Ben")
    }

    @Test("someone who has set off for elsewhere does not start a conversation where they were")
    func travelersAreNotPresent() async throws {
        // Both start at the cafe at 07:00; Ana's 07:00 plan is the park, a one-tick walk.
        let brain = ScriptedBrain(
            planHour: Self.staying { agent, _ in agent == Self.ana ? WorldMap.park : WorldMap.hobbsCafe },
            converse: Self.scriptedTalk(acts: [], conveyed: []))
        let simulation = Simulation(world: .smallvilleSubset(), profiles: Self.cafeRegulars(), brain: brain)
        try await simulation.run(minutes: 10)

        let events = await simulation.events
        #expect(Self.conversations(in: events).isEmpty, "Ana left at 07:00; she is not in the cafe to talk")
        let departed = events.contains { event in
            if case .acted(let agent, let action, let at) = event {
                return agent == Self.ana && action.location == WorldMap.park && at == SimTime(minutes: 7 * 60)
            }
            return false
        }
        #expect(departed, "the scenario really has Ana leaving on the first tick")
    }
}
