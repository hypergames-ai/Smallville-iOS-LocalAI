import Foundation

/// Turns whatever a brain put in an action's emoji field into one displayable glyph. Models
/// sometimes write `:coffee:`-style shortcodes or words; the Town scene needs a glyph.
public enum ActionEmoji {
    /// Shown when nothing usable came back.
    public static let fallback = "🙂"

    /// Shortcodes seen from the on-device model, plus the common ones for town activities.
    static let shortcodes: [String: String] = [
        "art": "🎨", "book": "📖", "books": "📚", "broom": "🧹", "bulb": "💡", "clipboard": "📋",
        "coffee": "☕️", "cooking": "🍳", "fork_and_knife": "🍽️", "gift": "🎁", "heart": "❤️",
        "memo": "📝", "newspaper": "📰", "pencil": "✏️", "pencil2": "✏️", "shopping": "🛍️",
        "shopping_cart": "🛒", "shopping_list": "🛒", "sleeping": "😴", "smile": "😊", "tada": "🎉",
        "wave": "👋",
    ]

    /// An emoji passes through; `:name:` becomes its glyph if known; otherwise the first emoji
    /// in the text, or `fallback`.
    public static func normalized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 2, trimmed.hasPrefix(":"), trimmed.hasSuffix(":") {
            let name = trimmed.dropFirst().dropLast().lowercased()
            return shortcodes[name] ?? fallback
        }
        return trimmed.first(where: isEmoji).map(String.init) ?? fallback
    }

    /// True for a character drawn as an emoji. Digits and `#` carry the emoji property too, so
    /// only scalars outside ASCII count, except that a keycap mark (U+20E3) makes "1️⃣" one.
    private static func isEmoji(_ character: Character) -> Bool {
        character.unicodeScalars.contains { $0.value == 0x20E3 || ($0.value > 0x7F && $0.properties.isEmoji) }
    }
}
