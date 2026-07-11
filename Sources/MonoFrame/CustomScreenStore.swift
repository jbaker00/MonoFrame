import Foundation

// Generated screens, persisted as a JSON array in Documents.
@MainActor
final class CustomScreenStore: ObservableObject {
    @Published private(set) var screens: [ScreenLayout] = []

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("customScreens.json")
    }

    init() {
        screens = Self.load()
    }

    /// Adds a screen, de-duplicating its name ("Focus", "Focus 2", …) since
    /// the picker keys off names.
    func add(_ layout: ScreenLayout) {
        var unique = layout
        let base = layout.name
        var n = 2
        while screens.contains(where: { $0.name == unique.name }) {
            unique.name = "\(base) \(n)"
            n += 1
        }
        screens.append(unique)
        persist()
    }

    func remove(_ layout: ScreenLayout) {
        screens.removeAll { $0.name == layout.name }
        persist()
    }

    private static func load() -> [ScreenLayout] {
        guard let data = try? Data(contentsOf: fileURL),
              let screens = try? JSONDecoder().decode([ScreenLayout].self, from: data)
        else { return [] }
        return screens.map { $0.clamped() }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(screens) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
