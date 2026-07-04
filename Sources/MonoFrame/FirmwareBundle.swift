import Foundation

// The firmware images shipped inside the app (Resources/Firmware/, generated
// by scripts/build_firmware.sh). The setup wizard pushes these to frames over
// their local hotspot, so frames can be updated phone-to-frame with no
// computer or download involved.
enum FirmwareBundle {

    static let version: String = {
        guard let url = Bundle.main.url(forResource: "version", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "0"
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    static func isOutdated(_ deviceVersion: String) -> Bool {
        deviceVersion.compare(version, options: .numeric) == .orderedAscending
    }

    static func otaImage(for model: DeviceModel) -> Data? {
        let name = switch model {
        case .crowPanel42: "monoframe-ota-42"
        case .crowPanel579: "monoframe-ota-579"
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "bin") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }
}
