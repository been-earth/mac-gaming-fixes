import AppKit
import SwiftUI

/// An empty unified toolbar makes the title bar as tall as our top bar, which centres the system's
/// window buttons in the sidebar's brand row; the content runs underneath.
@MainActor func configure(_ window: NSWindow) {
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.styleMask.insert(.fullSizeContentView)
    window.toolbar = NSToolbar()
    window.toolbarStyle = .unified
    window.backgroundColor = NSColor(Hax.bgPage)
}

private struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { configure(window) } }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct MGFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    /// MGF_DRY=1 opens the real window on a model that reads the system but never changes it.
    @State private var model = AppModel(live: ProcessInfo.processInfo.environment["MGF_DRY"] == nil)

    init() { Hax.registerFonts() }

    var body: some Scene {
        Window("MacGamingFixes", id: "main") {
            RootView().environment(model).background(WindowChrome())
        }
        // with the default style the system draws its title bar opaque over our top bar
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 820)
        .windowResizability(.contentMinSize)
    }
}

/// MGF_SNAPSHOT=<dir> renders every screen into PNG files without showing a window or changing
/// anything on the system. Used to check the design and to make screenshots.
@MainActor enum Snapshot {
    static func run(into directory: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Hax.registerFonts()
        let model = AppModel(live: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        configure(window)
        window.contentView = NSHostingView(rootView: RootView().environment(model))
        let screens: [(String, () -> Void)] = [
            ("setup-hello", { model.restartSetup() }),
            ("setup-fixes", { model.settings.setupStep = 1 }),
            ("setup-crossover", { model.settings.setupStep = 2 }),
            ("setup-permission", { model.settings.setupStep = 3 }),
            ("setup-apply", { model.settings.setupStep = 4 }),
            ("setup-ready", { model.settings.setupStep = 5 }),
            ("fixes", { model.finishSetup(loginItem: model.loginItem) }),
            ("article", { model.screen = .article(.regsave) }),
            ("tools", { model.screen = .tools }),
            ("settings", { model.screen = .settings }),
            ("dialog", { model.screen = .fixes; model.confirm = .revert }),
            // a window tall enough to show every card without scrolling
            ("fixes-tall", { model.confirm = nil; window.setContentSize(NSSize(width: 1240, height: 1420)) }),
        ]
        var index = 0
        func next() {
            guard index < screens.count else { exit(0) }
            let (name, prepare) = screens[index]
            index += 1
            prepare()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {   // the setup types its findings line by line
                let view = window.contentView?.superview ?? window.contentView!
                view.layoutSubtreeIfNeeded()
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
                }
                next()
            }
        }
        next()
        app.run()
    }
}

@main @MainActor enum Entry {
    static func main() {
        if let directory = ProcessInfo.processInfo.environment["MGF_SNAPSHOT"] {
            Snapshot.run(into: directory)
        } else {
            MGFApp.main()
        }
    }
}
