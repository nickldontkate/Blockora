import Foundation

/// Local-first save/load for GameWorld (§49). This is deliberately separate
/// from the D1-backed server persistence the Cloudflare backend will own —
/// this store is what keeps the game playable offline and during development
/// before that backend is wired up.
final class SaveGameStore {
    static let shared = SaveGameStore()

    private let fileURL: URL

    init(fileName: String = "blockora_save.json") {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent(fileName)
    }

    func load() -> GameWorld? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GameWorld.self, from: data)
    }

    func save(_ world: GameWorld) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(world) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func deleteSave() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
