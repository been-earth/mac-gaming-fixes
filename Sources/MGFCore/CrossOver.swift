import AppKit

/// A CrossOver installation: the bundle the fixes are written into.
public struct CrossOver: Equatable {
    public let bundle: URL

    public init(bundle: URL) { self.bundle = bundle.standardizedFileURL }
    public init(path: String) { self.init(bundle: URL(fileURLWithPath: (path as NSString).expandingTildeInPath)) }

    public var support: URL { bundle.appendingPathComponent("Contents/SharedSupport/CrossOver") }
    public var bin: URL { support.appendingPathComponent("bin") }
    public var unixLibs: URL { support.appendingPathComponent("lib/wine/x86_64-unix") }
    public var wineserver: URL { bin.appendingPathComponent("wineserver") }
    public var audioDriver: URL { unixLibs.appendingPathComponent("winecoreaudio.so") }

    /// True when the bundle holds a Wine server, patched or not.
    public var isValid: Bool { FileManager.default.fileExists(atPath: wineserver.path) }

    /// Whether macOS lets this process change files in the bundle (App Management). Opens the Wine
    /// server for writing and closes it again: not a byte is written. nil when there is no server to try.
    public var isWritable: Bool? {
        let fd = open(wineserver.path, O_WRONLY)
        if fd >= 0 { close(fd); return true }
        return errno == ENOENT ? nil : false
    }

    public var version: String? {
        let plist = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
        return plist?["CFBundleShortVersionString"] as? String
    }

    /// Where CrossOver usually lives, then wherever Launch Services knows it.
    public static func detect() -> CrossOver? {
        var candidates = ["~/Applications/CrossOver.app", "/Applications/CrossOver.app"].map(CrossOver.init(path:))
        if let known = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.codeweavers.CrossOver") {
            candidates.append(CrossOver(bundle: known))
        }
        return candidates.first(where: \.isValid)
    }
}
