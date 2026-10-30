import AppKit

/// Painted pictures shown at the display's full resolution over the pixel art: the
/// Avatar's portraits, one per outfit, for a man and a woman, and the town watch's.
enum Portraits {
    /// What the Avatar wears, from the shirt and slacks of the first day to gilded plate.
    enum Outfit: Int, CaseIterable {
        case clothes, leather, mail, breastplate, plate, gilded
    }

    static func avatarName(female: Bool, outfit: Outfit = .clothes) -> String {
        "avatar-\(female ? "woman" : "man")-\(outfit.rawValue)"
    }

    /// The town watch, by rank (0 watchman ... 4 knight of the watch).
    static func guardName(rank: Int, female: Bool) -> String {
        "guard-\(female ? "woman" : "man")-\(rank)"
    }

    private static var cache: [String: CGImage] = [:]
    private static let lock = NSLock()

    /// The picture called `name`, from the app's Resources/Portraits, or from the
    /// source tree when run from a build directory.
    static func image(_ name: String) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let img = cache[name] { return img }
        for dir in folders {
            let url = dir.appendingPathComponent(name + ".jpg")
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                cache[name] = img
                return img
            }
        }
        return nil
    }

    private static let folders: [URL] = {
        var dirs: [URL] = []
        if let res = Bundle.main.resourceURL { dirs.append(res.appendingPathComponent("Portraits")) }
        // Run from .build/<arch>/release: look for Resources/Portraits in the folders above.
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<5 {
            dirs.append(dir.appendingPathComponent("Resources/Portraits"))
            dir.deleteLastPathComponent()
        }
        dirs.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Portraits"))
        return dirs
    }()
}
