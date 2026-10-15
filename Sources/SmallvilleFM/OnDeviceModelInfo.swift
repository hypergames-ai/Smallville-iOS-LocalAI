#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// What this device's on-device model is: shown in the app and written into benchmark files.
public struct OnDeviceModelInfo: Sendable, Codable, Hashable {
    public var isAvailable: Bool
    public var unavailableReason: String?
    /// "AFM 3 Core" / "AFM 3 Core Advanced" on iOS 27; nil on iOS 26.
    public var variantName: String?
    public var contextSize: Int?

    @available(iOS 26.0, macOS 26.0, *)
    public static func probe(_ model: SystemLanguageModel = .default) -> OnDeviceModelInfo {
        var info = OnDeviceModelInfo(isAvailable: model.isAvailable)
        if case .unavailable(let reason) = model.availability {
            info.unavailableReason = String(describing: reason)
        }
        if model.isAvailable {
            // VERIFY: contextSize is documented as iOS 26.0+ (back-deployed before 26.4).
            info.contextSize = model.contextSize
            if #available(iOS 27.0, macOS 27.0, *) {
                info.variantName = model.variant.displayName
            }
        }
        return info
    }

    public init(isAvailable: Bool, unavailableReason: String? = nil, variantName: String? = nil, contextSize: Int? = nil) {
        self.isAvailable = isAvailable
        self.unavailableReason = unavailableReason
        self.variantName = variantName
        self.contextSize = contextSize
    }

    /// A conservative agent-count ceiling for the UI to default to.
    public var suggestedAgentCount: Int {
        guard isAvailable else { return 0 }
        return (contextSize ?? 4096) >= 8192 ? 10 : 5
    }
}
#endif
