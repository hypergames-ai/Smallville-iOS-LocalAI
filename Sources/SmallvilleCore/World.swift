import Foundation

/// A named place in the town. Mirrors Smallville's sector/arena/object hierarchy without the tile map.
public struct Location: Hashable, Sendable, Codable, Identifiable {
    public var id: LocationID
    public var name: String
    public var sector: String
    public var arena: String
    public var objects: [String]
    /// Public places are where strangers can meet; homes are not.
    public var isPublic: Bool

    public init(id: LocationID, name: String, sector: String, arena: String, objects: [String], isPublic: Bool) {
        self.id = id
        self.name = name
        self.sector = sector
        self.arena = arena
        self.objects = objects
        self.isPublic = isPublic
    }
}

/// The set of locations agents can move between. Travel is abstract (no pathfinding yet).
public struct WorldMap: Sendable, Codable {
    public private(set) var locations: [LocationID: Location]

    public init(locations: [Location]) {
        self.locations = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
    }

    public func location(_ id: LocationID) -> Location? {
        locations[id]
    }

    public func contains(_ id: LocationID) -> Bool {
        locations[id] != nil
    }

    public var allLocations: [Location] {
        locations.values.sorted { $0.id < $1.id }
    }

    public var publicLocations: [Location] {
        allLocations.filter(\.isPublic)
    }

    /// Minutes to get from one place to another. Flat for now; the tile map will replace this.
    public func travelMinutes(from: LocationID, to: LocationID) -> Int {
        from == to ? 0 : SimTime.minutesPerTick
    }
}

extension WorldMap {
    public static let hobbsCafe = LocationID("the_ville:hobbs_cafe")
    public static let isabellasApartment = LocationID("the_ville:isabella_apartment")
    public static let dormMaria = LocationID("the_ville:dorm_maria")
    public static let dormKlaus = LocationID("the_ville:dorm_klaus")
    public static let library = LocationID("the_ville:oak_hill_library")
    public static let pub = LocationID("the_ville:rose_and_crown_pub")
    public static let supplyStore = LocationID("the_ville:harvey_oak_supply_store")
    public static let park = LocationID("the_ville:johnson_park")

    /// A handful of Smallville's locations, enough for the three-agent scenario.
    public static func smallvilleSubset() -> WorldMap {
        WorldMap(locations: [
            Location(
                id: hobbsCafe, name: "Hobbs Cafe", sector: "Hobbs Cafe", arena: "cafe",
                objects: ["counter", "espresso machine", "tables", "piano"], isPublic: true),
            Location(
                id: isabellasApartment, name: "Isabella's apartment", sector: "Isabella Rodriguez's apartment",
                arena: "main room", objects: ["bed", "desk", "kitchen"], isPublic: false),
            Location(
                id: dormMaria, name: "Maria's dorm room", sector: "Oak Hill College dorm", arena: "Maria's room",
                objects: ["bed", "desk", "computer", "streaming setup"], isPublic: false),
            Location(
                id: dormKlaus, name: "Klaus's dorm room", sector: "Oak Hill College dorm", arena: "Klaus's room",
                objects: ["bed", "desk", "bookshelf"], isPublic: false),
            Location(
                id: library, name: "Oak Hill College library", sector: "Oak Hill College", arena: "library",
                objects: ["bookshelves", "study tables", "computers"], isPublic: true),
            Location(
                id: pub, name: "The Rose and Crown Pub", sector: "The Rose and Crown Pub", arena: "bar",
                objects: ["bar", "tables", "dartboard"], isPublic: true),
            Location(
                id: supplyStore, name: "Harvey Oak Supply Store", sector: "Harvey Oak Supply Store", arena: "store",
                objects: ["shelves", "counter"], isPublic: true),
            Location(
                id: park, name: "Johnson Park", sector: "Johnson Park", arena: "park",
                objects: ["benches", "pond", "path"], isPublic: true),
        ])
    }
}
