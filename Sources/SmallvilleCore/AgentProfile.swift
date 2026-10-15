import Foundation

/// Who an agent is: the stable facts that go into the model's instructions. Mirrors the
/// persona "scratch" fields of the original (innate traits, lifestyle, currently).
public struct AgentProfile: Hashable, Sendable, Codable, Identifiable {
    public var id: AgentID
    public var name: String
    public var age: Int
    public var innateTraits: String
    public var occupation: String
    public var lifestyle: String
    public var currently: String
    public var home: LocationID
    public var workplace: LocationID
    public var favoriteSpot: LocationID
    public var wakeHour: Int
    /// What this agent believes about others, keyed by agent.
    public var relationships: [AgentID: String]

    public init(
        id: AgentID, name: String, age: Int, innateTraits: String, occupation: String, lifestyle: String,
        currently: String, home: LocationID, workplace: LocationID, favoriteSpot: LocationID, wakeHour: Int,
        relationships: [AgentID: String]
    ) {
        self.id = id
        self.name = name
        self.age = age
        self.innateTraits = innateTraits
        self.occupation = occupation
        self.lifestyle = lifestyle
        self.currently = currently
        self.home = home
        self.workplace = workplace
        self.favoriteSpot = favoriteSpot
        self.wakeHour = wakeHour
        self.relationships = relationships
    }
}

extension AgentProfile {
    public static let isabella = AgentProfile(
        id: AgentID("isabella"), name: "Isabella Rodriguez", age: 34,
        innateTraits: "friendly, outgoing, hospitable",
        occupation: "owner of Hobbs Cafe",
        lifestyle: "goes to bed around 11pm, wakes up around 6am, eats dinner around 5pm",
        currently: "Isabella Rodriguez runs Hobbs Cafe and loves making the regulars feel welcome.",
        home: WorldMap.isabellasApartment, workplace: WorldMap.hobbsCafe, favoriteSpot: WorldMap.hobbsCafe,
        wakeHour: 6,
        relationships: [
            AgentID("maria"): "a regular at the cafe, a college student",
            AgentID("klaus"): "a regular at the cafe, a college student who reads a lot",
        ])

    public static let maria = AgentProfile(
        id: AgentID("maria"), name: "Maria Lopez", age: 21,
        innateTraits: "energetic, enthusiastic, inquisitive",
        occupation: "student at Oak Hill College studying physics, part-time Twitch streamer",
        lifestyle: "goes to bed around 2am, wakes up around 9am, eats dinner around 6pm",
        currently: "Maria Lopez is studying for her physics exams and streaming games in the evenings.",
        home: WorldMap.dormMaria, workplace: WorldMap.library, favoriteSpot: WorldMap.hobbsCafe, wakeHour: 9,
        relationships: [
            AgentID("isabella"): "owner of Hobbs Cafe, where she studies",
            AgentID("klaus"): "a classmate who seems to like her",
        ])

    public static let klaus = AgentProfile(
        id: AgentID("klaus"), name: "Klaus Mueller", age: 20,
        innateTraits: "kind, inquisitive, passionate",
        occupation: "student at Oak Hill College studying sociology",
        lifestyle: "goes to bed around 11pm, wakes up around 7am, eats dinner around 5pm",
        currently: "Klaus Mueller is writing a research paper on gentrification and has a crush on Maria Lopez.",
        home: WorldMap.dormKlaus, workplace: WorldMap.library, favoriteSpot: WorldMap.hobbsCafe, wakeHour: 7,
        relationships: [
            AgentID("isabella"): "owner of Hobbs Cafe",
            AgentID("maria"): "a classmate he has a crush on",
        ])

    /// The three-agent base scenario from the original repository.
    public static let sample3: [AgentProfile] = [isabella, maria, klaus]
}
