import Foundation

/// An optional file holding the Claude API key, so the game needn't read the keychain
/// (and make macOS ask for permission after every rebuild). It holds one line:
///
///     CLAUDE_API_KEY=sk-ant-...
///
/// By default it is `.claude-creds` in the project folder (found by looking upwards
/// from wherever the game runs); Options ▸ Claude Credentials File… can point elsewhere.
enum ClaudeCredentials {
    static let fileName = ".claude-creds"
    private static let pathKey = "claudeCredsPath"

    /// A location the player chose, or nil for the default.
    static var customPath: String? {
        get { UserDefaults.standard.string(forKey: pathKey) }
        set {
            if let p = newValue, !p.isEmpty { UserDefaults.standard.set(p, forKey: pathKey) } else { UserDefaults.standard.removeObject(forKey: pathKey) }
        }
    }

    /// Where the file is looked for now.
    static var url: URL? {
        if let p = customPath { return URL(fileURLWithPath: (p as NSString).expandingTildeInPath) }
        return defaultURL
    }

    /// `.claude-creds` in the nearest folder above the game that has one; failing that,
    /// in the project folder (the one with Package.swift), where it would be put.
    static var defaultURL: URL? {
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        return findDefault(from: exe) ?? findDefault(from: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    }

    static func findDefault(from start: URL) -> URL? {
        let fm = FileManager.default
        var dir = start, project: URL?
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent(fileName)
            if fm.fileExists(atPath: candidate.path) { return candidate }
            if project == nil, fm.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) { project = candidate }
            let up = dir.deletingLastPathComponent()
            if up.path == dir.path { break }
            dir = up
        }
        return project
    }

    /// The key in the file, if it exists and has a CLAUDE_API_KEY line.
    static func readKey(from url: URL? = url) -> String? {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// Finds `CLAUDE_API_KEY=...` (or `ANTHROPIC_API_KEY=...`), allowing `export`,
    /// spaces and quotes; lines starting with # are ignored.
    static func parse(_ text: String) -> String? {
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let name = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard name == "CLAUDE_API_KEY" || name == "ANTHROPIC_API_KEY" else { continue }
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { return value }
        }
        return nil
    }
}
