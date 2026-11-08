import Foundation

/// Stores the Anthropic API key in a user-only file (0600) in Application Support.
/// Avoids the Keychain, which re-prompts for access after every rebuild of an ad-hoc signed app.
enum KeyStore {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HorseTrainer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("anthropic-api-key")
    }

    static func read() -> String {
        (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func write(_ key: String) {
        if key.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? Data(key.utf8).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
