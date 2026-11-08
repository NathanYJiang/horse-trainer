import AppKit
import CoreText

/// Registers the bundled Geist fonts (SIL OFL) for this process. Looks in the .app's Resources and in the SwiftPM resource
/// bundle next to the executable (`swift run`), without touching `Bundle.module` (which traps if the bundle is missing).
enum FontLoader {
    static func registerBundledFonts() {
        var dirs: [URL] = []
        if let res = Bundle.main.resourceURL { dirs.append(res.appendingPathComponent("Fonts")) }
        let exeDir = Bundle.main.executableURL?.deletingLastPathComponent()
        if let exeDir { dirs.append(exeDir.appendingPathComponent("HorseTrainer_HorseTrainer.bundle/Fonts")) }
        if let exeDir { dirs.append(exeDir.appendingPathComponent("HorseTrainer_HorseTrainer.bundle/Contents/Resources/Fonts")) }
        for dir in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for f in files where f.pathExtension == "ttf" {
                CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
            }
            return
        }
    }
}
