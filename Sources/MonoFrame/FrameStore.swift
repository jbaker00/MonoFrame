import Foundation
import Security

struct Frame: Codable, Identifiable, Equatable, Hashable {
    let frameId: String
    let token: String
    var name: String
    let createdAt: Date
    var model: DeviceModel

    var id: String { frameId }

    init(frameId: String, token: String, name: String, createdAt: Date,
         model: DeviceModel = .crowPanel42) {
        self.frameId = frameId
        self.token = token
        self.name = name
        self.createdAt = createdAt
        self.model = model
    }

    // Frames paired before multi-device support have no `model` key, and an
    // unknown model string must not make the whole Keychain array undecodable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frameId = try c.decode(String.self, forKey: .frameId)
        token = try c.decode(String.self, forKey: .token)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        model = DeviceModel(infoModel: try? c.decode(String.self, forKey: .model))
    }
}

// All paired frames, persisted as a JSON array in a single Keychain item.
// Migrates the v1 payload (one {frameId, token} object) into a one-element
// array on first load.
@MainActor
final class FrameStore: ObservableObject {
    @Published private(set) var frames: [Frame] = []
    @Published var selectedFrameId: String? {
        didSet { UserDefaults.standard.set(selectedFrameId, forKey: "selectedFrameId") }
    }

    var selectedFrame: Frame? {
        frames.first { $0.frameId == selectedFrameId } ?? frames.first
    }

    init() {
        frames = Self.load()
        let saved = UserDefaults.standard.string(forKey: "selectedFrameId")
        selectedFrameId = frames.contains { $0.frameId == saved } ? saved : frames.first?.frameId
    }

    func add(_ frame: Frame) {
        frames.removeAll { $0.frameId == frame.frameId }
        frames.append(frame)
        selectedFrameId = frame.frameId
        persist()
    }

    func rename(_ frame: Frame, to name: String) {
        guard let i = frames.firstIndex(where: { $0.frameId == frame.frameId }) else { return }
        frames[i].name = name
        persist()
    }

    func remove(_ frame: Frame) {
        frames.removeAll { $0.frameId == frame.frameId }
        if selectedFrameId == frame.frameId { selectedFrameId = frames.first?.frameId }
        persist()
    }

    // MARK: - Keychain

    private static let service = "com.jamesbaker.MonoFrame"
    private static let account = "frameCredentials"

    private struct LegacyCredentials: Codable {
        let frameId: String
        let token: String
    }

    private static func load() -> [Frame] {
        guard let data = readKeychain() else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let frames = try? decoder.decode([Frame].self, from: data) {
            return frames
        }
        if let legacy = try? decoder.decode(LegacyCredentials.self, from: data) {
            let migrated = [Frame(frameId: legacy.frameId, token: legacy.token,
                                  name: "My Frame", createdAt: Date())]
            write(migrated)
            return migrated
        }
        return []
    }

    private func persist() {
        Self.write(frames)
    }

    private static func write(_ frames: [Frame]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(frames) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func readKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }
}
