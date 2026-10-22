#if canImport(FoundationModels)
import Foundation
import FoundationModels
import Testing

@testable import SmallvilleCore
@testable import SmallvilleFM

@Suite("Dynamic schemas")
struct DynamicSchemaTests {
    @Test("an hour plan may only use the agent's known locations, deduplicated in order")
    func hourPlanLocations() throws {
        let schema = try DynamicSchemas.hourPlan(locationIDs: [
            "the_ville:hobbs_cafe", "the_ville:park", "the_ville:hobbs_cafe",
        ])
        #expect(try Fixtures.choices(for: "locationID", in: schema) == ["the_ville:hobbs_cafe", "the_ville:park"])
    }

    @Test("an agent who knows no locations can still only stay where it is")
    func emptyLocationsFallBack() throws {
        let context = try Fixtures.context(knownLocations: [])
        #expect(Mapping.locationIDs(for: context) == [context.location.id.rawValue])
        let schema = try DynamicSchemas.hourPlan(locationIDs: Mapping.locationIDs(for: context))
        #expect(try Fixtures.choices(for: "locationID", in: schema) == [context.location.id.rawValue])
    }

    @Test("a conversation may only name its two speakers and the storylines in play, or none")
    func conversationChoices() throws {
        let schema = try DynamicSchemas.conversation(
            names: ["Klaus Mueller", "Maria Lopez"], storylineIDs: ["valentines-party"], maxTurns: 6)
        for property in ["speaker", "from", "to"] {
            #expect(try Fixtures.choices(for: property, in: schema) == ["Klaus Mueller", "Maria Lopez"], "\(property)")
        }
        #expect(try Fixtures.choices(for: "storylineID", in: schema) == ["valentines-party", "none"])
        #expect(try Fixtures.choices(for: "conveyedStorylineIDs", in: schema) == ["valentines-party", "none"])
        #expect(try Fixtures.choices(for: "kind", in: schema) == SocialActKind.allCases.map(\.rawValue))
    }

    @Test("with no storylines in play, none is the only storyline choice")
    func noStorylines() throws {
        let schema = try DynamicSchemas.conversation(names: ["A", "B"], storylineIDs: [], maxTurns: 1)
        #expect(try Fixtures.choices(for: "storylineID", in: schema) == ["none"])
        let turns = try Fixtures.node(for: "turns", in: schema)
        #expect(turns["minItems"] as? Int == 1, "never more turns required than allowed")
        #expect(turns["maxItems"] as? Int == 1)
    }

    @Test(
        "no array is bounded 0...1, which the on-device model fails on",
        arguments: [0, 1, 3], [0, 1, 2, 6])
    func noZeroToOneArrays(storylineCount: Int, maxTurns: Int) throws {
        let ids = (0..<storylineCount).map { "storyline-\($0)" }
        let conversation = try DynamicSchemas.conversation(names: ["A", "B"], storylineIDs: ids, maxTurns: maxTurns)
        let hourPlan = try DynamicSchemas.hourPlan(locationIDs: ["the_ville:hobbs_cafe"])
        let arrays = [
            ("turns", conversation), ("acts", conversation), ("conveyedStorylineIDs", conversation),
            ("actions", hourPlan),
        ]
        for (property, schema) in arrays {
            let node = try Fixtures.node(for: property, in: schema)
            let maxItems = try #require(node["maxItems"] as? Int, "\(property) is bounded")
            let minItems = node["minItems"] as? Int ?? 0
            #expect(!(minItems == 0 && maxItems == 1), "\(property): \(storylineCount) storylines, \(maxTurns) turns")
        }
        let conveyed = try Fixtures.node(for: "conveyedStorylineIDs", in: conversation)
        #expect(
            conveyed["maxItems"] as? Int == max(DynamicSchemas.minimumArrayCeiling, storylineCount + 1),
            "every choice can still be listed")
    }

    @Test("storylines either participant knows are offered once each")
    func storylinesFromBothSides() throws {
        let other = Storyline(
            id: StorylineID("whisper-maria"), title: "a secret", seedText: "a secret", seededIn: AgentProfile.maria.id,
            seededAt: SimTime(minutes: 0))
        let request = ConversationRequest(
            initiator: try Fixtures.context(.klaus, storylines: [Fixtures.party]),
            partner: try Fixtures.context(.maria, storylines: [other, Fixtures.party]), maxTurns: 6)
        #expect(Mapping.storylineIDs(for: request) == ["valentines-party", "whisper-maria"])
    }
}

@Suite("Mapping hand-built model output")
struct MappingTests {
    @Test("an hour plan decodes from the schema's shape into core actions")
    func hourPlan() throws {
        let generated = try Fixtures.decode(
            GeneratedHourPlan.self,
            """
            {"actions": [{"startMinute": 0, "durationMinutes": 30, "activity": "getting coffee",
              "locationID": "the_ville:hobbs_cafe", "emoji": ":coffee:", "subject": "Klaus Mueller",
              "predicate": "is getting", "object": "coffee"}]}
            """)
        let plan = Mapping.hourPlan(generated, hour: 9)
        #expect(plan.hour == 9)
        let action = try #require(plan.actions.first)
        #expect(action.location == WorldMap.hobbsCafe)
        #expect(action.event == EventTriple(subject: "Klaus Mueller", predicate: "is getting", object: "coffee"))
        #expect(plan.normalized(hour: 9).actions.first?.emoji == "☕️", "the core fixes shortcodes")
    }

    @Test("names become ids, none becomes no storyline, unknown kinds drop, conveyed storylines dedupe")
    func conversation() throws {
        let generated = try Fixtures.decode(
            GeneratedConversation.self,
            """
            {"turns": [{"speaker": "Klaus Mueller", "text": "Coming to the party?"},
                       {"speaker": "Maria Lopez", "text": "Yes!"}],
             "acts": [{"kind": "invite", "from": "Klaus Mueller", "to": "Maria Lopez", "topic": "party",
                       "storylineID": "valentines-party"},
                      {"kind": "inform", "from": "Maria Lopez", "to": "Klaus Mueller", "topic": "class",
                       "storylineID": "none"},
                      {"kind": "hug", "from": "Maria Lopez", "to": "Klaus Mueller", "topic": "x",
                       "storylineID": "none"}],
             "conveyedStorylineIDs": ["valentines-party", "none", "valentines-party"],
             "initiatorSummary": "I invited Maria.", "partnerSummary": "Klaus invited me."}
            """)
        let conversation = Mapping.conversation(generated, initiator: .klaus, partner: .maria)
        let klaus = AgentProfile.klaus.id
        let maria = AgentProfile.maria.id
        #expect(conversation.turns.map(\.speaker) == [klaus, maria])
        #expect(conversation.acts.map(\.kind) == [.invite, .inform])
        #expect(conversation.acts.map(\.from) == [klaus, maria])
        #expect(conversation.acts.map(\.storyline) == [StorylineID("valentines-party"), nil])
        #expect(conversation.conveyedStorylines == [StorylineID("valentines-party")])
        #expect(conversation.initiatorSummary == "I invited Maria.")
    }

    @Test("with nothing in play the model may list none twice; that conveys nothing")
    func conveyedNoneOnly() throws {
        let generated = try Fixtures.decode(
            GeneratedConversation.self,
            """
            {"turns": [{"speaker": "Klaus Mueller", "text": "Hi"}, {"speaker": "Maria Lopez", "text": "Hey"}],
             "acts": [], "conveyedStorylineIDs": ["none", "none"],
             "initiatorSummary": "We said hi.", "partnerSummary": "We said hi."}
            """)
        #expect(Mapping.conversation(generated, initiator: .klaus, partner: .maria).conveyedStorylines.isEmpty)
    }

    @Test("a day plan maps entry by entry")
    func dayPlan() throws {
        let generated = try Fixtures.decode(
            GeneratedDayPlan.self,
            #"{"wakeHour": 7, "entries": [{"hour": 8, "activity": "study"}, {"hour": 12, "activity": "lunch"}]}"#)
        #expect(
            Mapping.dayPlan(generated)
                == DayPlan(
                    wakeHour: 7,
                    entries: [DayPlanEntry(hour: 8, activity: "study"), DayPlanEntry(hour: 12, activity: "lunch")]
                ))
    }

    @Test("an identity revision maps as generated, and a blank status keeps the previous one")
    func identityRevision() throws {
        let generated = try Fixtures.decode(
            GeneratedIdentityRevision.self,
            #"{"planNote": "Go to the party.", "thoughtNote": "Excited.", "currently": "Klaus plans to attend."}"#)
        #expect(
            Mapping.identityRevision(generated, previous: "old")
                == IdentityRevision(planNote: "Go to the party.", thoughtNote: "Excited.", currently: "Klaus plans to attend."))
        let blank = try Fixtures.decode(
            GeneratedIdentityRevision.self, #"{"planNote": "", "thoughtNote": "", "currently": "  \n"}"#)
        #expect(Mapping.identityRevision(blank, previous: "old").currently == "old")
    }

    @Test("reflection evidence is limited to memory ids that were in the prompt")
    func reflections() throws {
        let generated = try Fixtures.decode(
            GeneratedReflections.self, #"{"insights": [{"insight": "Klaus likes the cafe", "evidence": [1, 2, 99]}]}"#)
        #expect(
            Mapping.reflections(generated, known: [1, 2]) == [
                Reflection(insight: "Klaus likes the cafe", evidence: [1, 2])
            ])
    }

    @Test(
        "ratings are clamped to 1...10 and made exactly as long as the batch",
        arguments: [
            ("[0, 11, 5]", 3, [1, 10, 5]), ("[4]", 3, [4, 3, 3]), ("[2, 2, 2, 2]", 2, [2, 2]),
        ])
    func ratings(json: String, count: Int, expected: [Int]) throws {
        let generated = try Fixtures.decode(GeneratedRatings.self, #"{"ratings": \#(json)}"#)
        #expect(Mapping.ratings(generated, count: count) == expected)
    }
}

@Suite("Prompts")
struct PromptTests {
    private static let memories = ["first memory", "second memory", "third memory"]

    @Test("the memory limit trims retrieved memories, and zero leaves the block out")
    func memoryLimit() throws {
        let context = try Fixtures.context(memories: Self.memories)
        let dayPlan = DayPlan(wakeHour: 7, entries: [DayPlanEntry(hour: 9, activity: "study")])
        let two = Prompts.hourPlan(context, dayPlan: dayPlan, memoryLimit: 2)
        #expect(two.contains("first memory") && two.contains("second memory"))
        #expect(!two.contains("third memory"))
        #expect(!Prompts.hourPlan(context, dayPlan: dayPlan, memoryLimit: 0).contains("Relevant memories"))
    }

    @Test("the hour-plan prompt lists the known location ids the schema allows")
    func hourPlanLocations() throws {
        for context in [try Fixtures.context(), try Fixtures.context(knownLocations: [])] {
            let prompt = Prompts.hourPlan(context, dayPlan: DayPlan(wakeHour: 7, entries: []))
            for id in Mapping.locationIDs(for: context) {
                #expect(prompt.contains(id), "\(id) with \(context.knownLocations.count) known")
            }
        }
    }

    @Test("the day-plan prompt names the profile's workplace, favorite spot and home")
    func dayPlanNamesUsualPlaces() throws {
        let prompt = Prompts.dayPlan(try Fixtures.context(.maria, knownLocations: Fixtures.world.allLocations))
        for name in ["Oak Hill College library", "Hobbs Cafe", "Maria's dorm room"] {
            #expect(prompt.contains(name), "\(name)")
        }
    }

    @Test("the identity-revision prompt carries the old status, known events with venue, and memories")
    func identityRevisionPrompt() throws {
        let context = try Fixtures.context(.klaus, memories: Self.memories, storylines: [Fixtures.party])
        let prompt = Prompts.identityRevision(context)
        #expect(prompt.contains("Currently: \(AgentProfile.klaus.currently)"))
        #expect(prompt.contains("valentines-party: Valentine's Day party at Hobbs Cafe at \(WorldMap.hobbsCafe.rawValue)"))
        for memory in Self.memories {
            #expect(prompt.contains(memory))
        }
    }

    @Test("the status changes daily, so it is in every prompt and not in the fixed instructions")
    func statusIsInPromptsNotInstructions() throws {
        let context = try Fixtures.context(.klaus, memories: Self.memories)
        let status = "Currently: \(AgentProfile.klaus.currently)"
        #expect(!Prompts.instructions(for: .klaus).contains("Currently:"))
        let request = ConversationRequest(initiator: context, partner: try Fixtures.context(.maria), maxTurns: 6)
        for prompt in [
            Prompts.identityRevision(context), Prompts.dayPlan(context),
            Prompts.hourPlan(context, dayPlan: DayPlan(wakeHour: 7, entries: [])), Prompts.reflection(context),
            Prompts.conversation(request), Prompts.poignancy(["saw Maria"], for: .klaus),
        ] {
            #expect(prompt.contains(status))
        }
    }

    @Test("an event shows its end time, and once over it is marked over and its place is no longer a venue")
    func eventEndInPrompts() throws {
        var context = try Fixtures.context(
            .maria, knownLocations: Fixtures.world.allLocations, storylines: [Fixtures.party])
        let line = "valentines-party: Valentine's Day party at Hobbs Cafe at \(WorldMap.hobbsCafe.rawValue) on "
        let start = Fixtures.party.eventTime.map(String.init(describing:)) ?? ""
        let before = Prompts.hourPlan(context, dayPlan: DayPlan(wakeHour: 9, entries: []))
        #expect(before.contains(line + "\(start) until 19:00\n"))
        #expect(before.contains("Hobbs Cafe, favorite spot, storyline venue"))

        context.now = SimTime(minutes: 24 * 60 + 18 * 60 + 50)
        let during = Prompts.hourPlan(context, dayPlan: DayPlan(wakeHour: 9, entries: []))
        #expect(during.contains(line + "\(start) until 19:00\n"), "still on at 18:50, not over")
        #expect(during.contains("Hobbs Cafe, favorite spot, storyline venue"))

        context.now = SimTime(minutes: 24 * 60 + 19 * 60)
        let after = Prompts.hourPlan(context, dayPlan: DayPlan(wakeHour: 9, entries: []))
        #expect(after.contains("until 19:00 (over)"))
        #expect(after.contains("the_ville:hobbs_cafe (Hobbs Cafe, favorite spot)"))
        #expect(!after.contains("storyline venue"))

        let lateParty = Storyline(
            id: StorylineID("late"), title: "a late party", seedText: "A late party.", seededIn: AgentProfile.maria.id,
            seededAt: SimTime(minutes: 7 * 60), targetLocation: WorldMap.pub,
            eventTime: SimTime(minutes: 23 * 60), durationMinutes: 120)
        let overnight = Prompts.hourPlan(
            try Fixtures.context(.maria, storylines: [lateParty]), dayPlan: DayPlan(wakeHour: 9, entries: []))
        #expect(overnight.contains("on Day 1 23:00 until Day 2 01:00"), "an end past midnight names its day")
    }

    @Test("the hour-plan prompt marks the agent's own places and the storyline venue")
    func hourPlanTagsRoles() throws {
        let context = try Fixtures.context(
            .maria, knownLocations: Fixtures.world.allLocations, storylines: [Fixtures.party])
        let prompt = Prompts.hourPlan(context, dayPlan: DayPlan(wakeHour: 9, entries: []))
        #expect(prompt.contains("the_ville:oak_hill_library (Oak Hill College library, workplace)"))
        #expect(prompt.contains("the_ville:hobbs_cafe (Hobbs Cafe, favorite spot, storyline venue)"))
        #expect(prompt.contains("the_ville:dorm_maria (Maria's dorm room, home)"))
        #expect(prompt.contains("the_ville:johnson_park (Johnson Park)"), "a place that is nothing to her is untagged")
        #expect(
            Prompts.roles(of: WorldMap.hobbsCafe, in: try Fixtures.context(.isabella)) == [
                "workplace", "favorite spot",
            ])
    }

    @Test("a conversation prompt gives the partner one memory fewer and names both speakers in full")
    func conversation() throws {
        let request = ConversationRequest(
            initiator: try Fixtures.context(.klaus, memories: Self.memories, storylines: [Fixtures.party]),
            partner: try Fixtures.context(.maria, memories: ["maria one", "maria two", "maria three"]), maxTurns: 6)
        let prompt = Prompts.conversation(request, memoryLimit: 2)
        #expect(prompt.contains("second memory") && !prompt.contains("third memory"))
        #expect(prompt.contains("maria one") && !prompt.contains("maria two"))
        #expect(prompt.contains("Klaus Mueller") && prompt.contains("Maria Lopez"))
        #expect(prompt.contains("valentines-party") && prompt.contains("or none"))
    }
}
#endif
