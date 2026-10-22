import Foundation

/// A deterministic stand-in for the language model. It is not clever; it exists so the
/// simulation loop, the budget accounting, the detector and the UI can be exercised without
/// a model, and so the package tests on Linux. It knows exactly one social trick: if it has
/// heard about a storyline the other agent hasn't, it tells them and invites them.
public struct StubBrain: AgentBrain {
    public var acceptsInvites = true

    public init() {}

    /// Keeps `currently` as it is; the plan note names the first storyline event still ahead today.
    public func reviseIdentity(_ context: AgentContext) async throws -> BrainResponse<IdentityRevision> {
        let now = context.now
        let today = context.activeStorylines.first { storyline in
            guard let time = storyline.eventTime else { return false }
            return time.day == now.day && time >= now
        }
        let planNote = today.map { "Remember \($0.title) later today." } ?? "A usual day."
        let revision = IdentityRevision(
            planNote: planNote, thoughtNote: "Feeling settled.", currently: context.profile.currently)
        return BrainResponse(value: revision, receipt: receipt(for: context, outputTokens: 100))
    }

    public func planDay(_ context: AgentContext) async throws -> BrainResponse<DayPlan> {
        let profile = context.profile
        let plan = DayPlan(
            wakeHour: profile.wakeHour,
            entries: [
                DayPlanEntry(hour: profile.wakeHour, activity: "wake up and have breakfast at home"),
                DayPlanEntry(hour: 9, activity: "work: \(profile.occupation)"),
                DayPlanEntry(hour: 13, activity: "lunch at a favorite spot"),
                DayPlanEntry(hour: 14, activity: "work: \(profile.occupation)"),
                DayPlanEntry(hour: 18, activity: "evening at a favorite spot"),
                DayPlanEntry(hour: 21, activity: "go home and relax"),
            ])
        return BrainResponse(value: plan, receipt: receipt(for: context, outputTokens: 120))
    }

    public func planHour(_ context: AgentContext, dayPlan: DayPlan) async throws -> BrainResponse<HourPlan> {
        let profile = context.profile
        let hour = context.now.hour

        // A known storyline event under way at the start of this hour, or starting during it,
        // wins over routine. The stub plans whole hours, so an event with a mid-hour start or end
        // is rounded out to the hours it touches; it is never attended once over.
        let hourStart = SimTime(minutes: context.now.minutes - context.now.minuteOfHour)
        let happeningNow = context.activeStorylines.first { storyline in
            guard let time = storyline.eventTime, storyline.targetLocation != nil else { return false }
            return storyline.isUnderway(at: hourStart) || (time.day == hourStart.day && time.hour == hour)
        }
        if let storyline = happeningNow, let location = storyline.targetLocation {
            let action = PlannedAction(
                startMinute: 0, durationMinutes: 60, activity: "attending \(storyline.title)", location: location,
                emoji: "🎉", event: EventTriple(subject: profile.name, predicate: "attends", object: storyline.title))
            return BrainResponse(
                value: HourPlan(hour: hour, actions: [action]), receipt: receipt(for: context, outputTokens: 80))
        }

        let actions = routine(for: profile, hour: hour).map { stop in
            PlannedAction(
                startMinute: stop.startMinute, durationMinutes: 60 - stop.startMinute, activity: stop.activity,
                location: stop.location, emoji: stop.emoji,
                event: EventTriple(subject: profile.name, predicate: "is", object: stop.activity))
        }
        return BrainResponse(
            value: HourPlan(hour: hour, actions: actions),
            receipt: receipt(for: context, outputTokens: 40 * actions.count))
    }

    public func converse(_ request: ConversationRequest) async throws -> BrainResponse<Conversation> {
        let a = request.initiator
        let b = request.partner
        let knownByA = Set(a.activeStorylines.map(\.id))
        let knownByB = Set(b.activeStorylines.map(\.id))

        var turns = [
            ConversationTurn(speaker: a.profile.id, text: "Hi \(b.profile.name)! How is it going?"),
            ConversationTurn(
                speaker: b.profile.id, text: "Hey \(a.profile.name), good. Just \(b.location.name) things."),
        ]
        var acts: [SocialAct] = []
        var conveyed: [StorylineID] = []

        if let storyline = a.activeStorylines.first(where: { !knownByB.contains($0.id) }) {
            share(storyline, from: a, to: b, turns: &turns, acts: &acts)
            conveyed.append(storyline.id)
        } else if let storyline = b.activeStorylines.first(where: { !knownByA.contains($0.id) }) {
            share(storyline, from: b, to: a, turns: &turns, acts: &acts)
            conveyed.append(storyline.id)
        } else {
            turns.append(ConversationTurn(speaker: a.profile.id, text: "Same here. See you around!"))
        }
        turns = Array(turns.prefix(request.maxTurns))

        let topics = conveyed.isEmpty ? "" : " about \(conveyed.map(\.rawValue).joined(separator: ", "))"
        let conversation = Conversation(
            initiator: a.profile.id, partner: b.profile.id, turns: turns, acts: acts, conveyedStorylines: conveyed,
            initiatorSummary: "\(a.profile.name) talked with \(b.profile.name) at \(a.location.name)\(topics)",
            partnerSummary: "\(b.profile.name) talked with \(a.profile.name) at \(b.location.name)\(topics)")
        return BrainResponse(value: conversation, receipt: receipt(for: a, outputTokens: 40 * turns.count))
    }

    public func reflect(_ context: AgentContext) async throws -> BrainResponse<[Reflection]> {
        let chats = context.relevantMemories.filter { $0.kind == .chat }
        let insight: String
        if let storyline = context.activeStorylines.first {
            insight = "\(context.profile.name) is looking forward to \(storyline.title)"
        } else if chats.isEmpty {
            insight = "\(context.profile.name) has been keeping to a routine lately"
        } else {
            insight = "\(context.profile.name) has been talking with people a lot lately (\(chats.count) recent chats)"
        }
        let evidence = Array(context.relevantMemories.prefix(3).map(\.id))
        return BrainResponse(
            value: [Reflection(insight: insight, evidence: evidence)], receipt: receipt(for: context, outputTokens: 40))
    }

    public func ratePoignancy(_ texts: [String], for profile: AgentProfile) async throws -> BrainResponse<[Int]> {
        let ratings = texts.map { text -> Int in
            let lowered = text.lowercased()
            if lowered.contains("party") || lowered.contains("valentine") { return 7 }
            if lowered.contains("looking forward") || lowered.contains("lately") { return 6 }
            if lowered.contains("talked with") { return 5 }
            if lowered.contains("saw") { return 2 }
            return 3
        }
        let inputTokens = texts.reduce(0) { $0 + $1.count / 4 } + 200
        return BrainResponse(
            value: ratings,
            receipt: BrainCallReceipt(inputTokens: inputTokens, outputTokens: texts.count * 2, wallSeconds: 0))
    }

    // MARK: - Helpers

    private struct Stop {
        var startMinute = 0
        var location: LocationID
        var activity: String
        var emoji: String
    }

    /// A fixed daily routine. Lunch and the first evening hour are split in two so the
    /// simulation's action decomposition runs in every stub run.
    private func routine(for profile: AgentProfile, hour: Int) -> [Stop] {
        let working = Stop(location: profile.workplace, activity: "working as \(profile.occupation)", emoji: "💼")
        switch hour {
        case ..<9: return [Stop(location: profile.home, activity: "having breakfast", emoji: "🍳")]
        case 9..<13: return [working]
        case 13:
            return [
                Stop(location: profile.favoriteSpot, activity: "having lunch", emoji: "🥗"),
                Stop(startMinute: 30, location: profile.favoriteSpot, activity: "chatting over coffee", emoji: "💬"),
            ]
        case 14..<18: return [working]
        case 18:
            return [
                Stop(location: profile.favoriteSpot, activity: "relaxing with a coffee", emoji: "☕️"),
                Stop(startMinute: 40, location: profile.favoriteSpot, activity: "reading", emoji: "📖"),
            ]
        case 19..<21: return [Stop(location: profile.favoriteSpot, activity: "relaxing with a coffee", emoji: "☕️")]
        default: return [Stop(location: profile.home, activity: "relaxing at home", emoji: "🏠")]
        }
    }

    private func share(
        _ storyline: Storyline, from teller: AgentContext, to listener: AgentContext, turns: inout [ConversationTurn],
        acts: inout [SocialAct]
    ) {
        turns.append(ConversationTurn(speaker: teller.profile.id, text: "By the way, \(storyline.seedText)"))
        acts.append(
            SocialAct(
                kind: .inform, from: teller.profile.id, to: listener.profile.id, topic: storyline.title,
                storyline: storyline.id))
        guard storyline.eventTime != nil else { return }

        turns.append(ConversationTurn(speaker: teller.profile.id, text: "You should come!"))
        acts.append(
            SocialAct(
                kind: .invite, from: teller.profile.id, to: listener.profile.id, topic: storyline.title,
                storyline: storyline.id))
        let accepts = acceptsInvites && !listener.profile.innateTraits.lowercased().contains("reserved")
        turns.append(
            ConversationTurn(
                speaker: listener.profile.id,
                text: accepts ? "I'd love to, count me in." : "Thanks, but I'll probably skip it."))
        acts.append(
            SocialAct(
                kind: accepts ? .accept : .decline, from: listener.profile.id, to: teller.profile.id,
                topic: storyline.title, storyline: storyline.id))
    }

    private func receipt(for context: AgentContext, outputTokens: Int) -> BrainCallReceipt {
        let characters =
            context.relevantMemories.reduce(0) { $0 + $1.text.count } + context.profile.currently.count + 600
        return BrainCallReceipt(inputTokens: characters / 4, outputTokens: outputTokens, wallSeconds: 0)
    }
}
