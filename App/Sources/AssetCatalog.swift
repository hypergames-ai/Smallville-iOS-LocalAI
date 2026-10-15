import Foundation

/// The only door to the third-party art. The folder is optional: a fresh clone has none, and
/// every caller must treat `nil` as a normal state (draw the schematic town instead).
enum AssetCatalog {
    /// Root of the fetched assets inside the app bundle, if `scripts/fetch-assets.sh` ran before the build.
    static var thirdPartyRoot: URL? {
        Bundle.main.url(forResource: "ThirdParty", withExtension: nil)
    }

    static var isInstalled: Bool {
        guard let root = thirdPartyRoot else { return false }
        return FileManager.default.fileExists(atPath: root.appendingPathComponent("MANIFEST.txt").path)
    }

    /// The Tiled map JSON for the town, when present.
    static var townMapURL: URL? {
        // VERIFY: file name inside the Stanford repo's the_ville/visuals folder.
        thirdPartyRoot?.appendingPathComponent("the_ville/visuals/the_ville_jan7.json")
    }
}
