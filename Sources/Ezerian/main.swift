import AppKit

let args = CommandLine.arguments

func argument(after flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let devSeed = argument(after: "--seed").flatMap(UInt64.init) ?? 1234

if let path = argument(after: "--render") {
    DevTools.writeScreenshot(seed: devSeed, walk: argument(after: "--walk") ?? "", to: path,
                             options: Set((argument(after: "--show") ?? "").split(separator: ",").map(String.init)),
                             hour: argument(after: "--hour").flatMap(Double.init),
                             scale: argument(after: "--scale").flatMap(Int.init) ?? 2)
    exit(0)
}
if let path = argument(after: "--sheet") {
    DevTools.writeSpriteSheet(to: path)
    exit(0)
}
if let path = argument(after: "--textures") {
    DevTools.writeTextures(to: path)
    exit(0)
}
if let path = argument(after: "--overview") {
    DevTools.writeOverview(seed: devSeed, radius: Int(argument(after: "--radius") ?? "2") ?? 2, to: path)
    exit(0)
}
if let n = argument(after: "--duels").flatMap(Int.init) {
    DevTools.duels(seed: devSeed, count: n, chain: args.contains("--chain"),
                   walkTurns: argument(after: "--walk-turns").flatMap(Int.init) ?? 0, pickFights: args.contains("--pick"))
    exit(0)
}
if args.contains("--bench") {
    DevTools.benchmark(seed: devSeed)
    exit(0)
}
if args.contains("--selftest") {
    exit(DevTools.selfTest(seed: devSeed) ? 0 : 1)
}
if let path = argument(after: "--icon") {
    DevTools.writeIcon(to: path)
    exit(0)
}

// Launch the game.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
