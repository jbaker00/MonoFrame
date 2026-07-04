import Foundation

// Every e-ink panel the app can drive. The raw value matches the `model`
// string the firmware reports from /info and is what gets persisted, so it
// must never change for shipped panels.
enum DeviceModel: String, Codable, CaseIterable, Identifiable {
    case crowPanel42 = "crowpanel-4.2"
    case crowPanel579 = "crowpanel-5.79"
    case reTerminalE1001 = "reterminal-e1001"

    var id: String { rawValue }

    var width: Int {
        switch self {
        case .crowPanel42: 400
        case .crowPanel579: 792
        case .reTerminalE1001: 800
        }
    }

    var height: Int {
        switch self {
        case .crowPanel42: 300
        case .crowPanel579: 272
        case .reTerminalE1001: 480
        }
    }

    var byteCount: Int { width * height / 8 }

    var displayName: String {
        switch self {
        case .crowPanel42: "CrowPanel 4.2\""
        case .crowPanel579: "CrowPanel 5.79\""
        case .reTerminalE1001: "reTerminal E1001 7.5\""
        }
    }

    var resolutionText: String { "\(width) × \(height)  ·  black & white" }

    // The "sync now" button, described the way a user would find it.
    var syncButtonHint: String {
        switch self {
        case .crowPanel42, .crowPanel579: "the button on the back"
        case .reTerminalE1001: "the top button"
        }
    }

    // Unknown strings (newer firmware than app) fall back to the original
    // panel rather than failing the whole pairing or decode.
    init(infoModel: String?) {
        self = infoModel.flatMap(DeviceModel.init(rawValue:)) ?? .crowPanel42
    }
}
