import AppKit
import CoreAudio
import MGFCore
import Observation
import ServiceManagement

let repoURL = URL(string: "https://github.com/been-earth/mac-gaming-fixes")!
let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"

enum Category: String, CaseIterable {
    case network, audio, input
    var title: String {
        switch self {
        case .network: return L("network")
        case .audio: return L("audio")
        case .input: return L("input")
        }
    }
}

enum FeatureID: String, CaseIterable, Identifiable {
    case regsave, wifi, audioBuffer, fkeys, audioDevices
    var id: String { rawValue }
    static let fixes: [FeatureID] = [.regsave, .wifi, .audioBuffer]
}

struct Feature: Identifiable {
    struct Measure { let label: String, unit: String, before: Double, after: Double }
    struct Change: Hashable { let tag: String, path: String, note: String }

    let id: FeatureID
    let category: Category
    let icon: String
    let slug: String        // article file name
    let title: String
    let useCase: String     // the symptom it is for, in plain words
    let description: String
    let meta: String        // one line under the article title
    var measure: Measure?
    var changes: [Change] = []  // what applying it does inside CrossOver
    var isFix: Bool { FeatureID.fixes.contains(id) }
    /// The page its card lives on: fixes patch CrossOver, tools change macOS settings.
    var home: AppModel.Screen { isFix ? .fixes : .tools }

    // computed, not stored: the strings follow the language picked in settings
    private static var wrapper: [Change] { [
        Change(tag: "WRAP", path: "bin/wineserver", note: L("original kept as wineserver.orig")),
        Change(tag: "NEW", path: "bin/wineserver.real", note: L("unsigned copy the wrapper runs")),
        Change(tag: "NEW", path: "bin/wineserver_fix.dylib", note: L("injected into wineserver")),
    ] }

    static var all: [Feature] { [
        Feature(id: .regsave, category: .network, icon: "save-off", slug: "registry-save-deferral", title: L("registry save deferral"),
                useCase: L("for online games that hitch every 30 seconds: the net jitter graph spikes and the game catches up in one jump."),
                description: L("wine rewrites its 12 mb registry every 30 s and freezes the whole bottle for ~240 ms while it does. this holds the save back while a game runs and lets it through when the bottle is idle or exits."),
                meta: L("network · patches bin/wineserver · active after the bottle restarts"),
                measure: Measure(label: L("longest stall"), unit: L("ms"), before: 264, after: 10), changes: wrapper),
        Feature(id: .wifi, category: .network, icon: "wifi", slug: "low-latency-wifi", title: L("low-latency wi-fi"),
                useCase: L("for playing over wi-fi: the game shows constant net jitter although the connection itself is fine."),
                description: L("the wi-fi chip holds packets for up to 25 ms unless a socket asks for real-time service, and wine never asks. this tags every udp socket in the bottle, so game traffic skips the hold-off."),
                meta: L("network · same wrapper as registry save deferral · active after the bottle restarts"),
                measure: Measure(label: L("median to router"), unit: L("ms"), before: 8.7, after: 3.8), changes: wrapper),
        Feature(id: .audioBuffer, category: .audio, icon: "audio-lines", slug: "audio-buffer-fix", title: L("audio buffer fix"),
                useCase: L("for crackling game sound and a choppy voice in voice chat, when your headphones or mic cannot run at 96 khz."),
                description: L("coreaudio hands wine blocks that outlast its 10 ms period at 44.1 and 48 khz, so playback crackles and the mic drops ~7 % of its audio. this asks for a 5.3 ms buffer at any sample rate. no 96 khz device needed."),
                meta: L("audio · patches winecoreaudio.so · active for games started after applying"),
                measure: Measure(label: L("silence inserted"), unit: "%", before: 6.3, after: 0.1),
                changes: [
                    Change(tag: "WRAP", path: "lib/wine/x86_64-unix/winecoreaudio.so", note: L("original kept as winecoreaudio.so.orig")),
                    Change(tag: "NEW", path: "lib/wine/x86_64-unix/winecoreaudio_real.so", note: L("copy the wrapper loads")),
                    Change(tag: "NEW", path: "lib/wine/x86_64-unix/mgf_audio_io_ms", note: L("buffer length for the wrapper")),
                ]),
        Feature(id: .fkeys, category: .input, icon: "keyboard", slug: "function-keys", title: L("function keys"),
                useCase: L("for games that use f1–f12: press them without holding fn, and get brightness and volume keys back after the match."),
                description: L("switches the top row between f1–f12 and brightness or media keys at once, no logout. turn it on by hand, or let it follow the apps you pick and macos game mode."),
                meta: L("input · changes a macos setting · takes effect immediately")),
        Feature(id: .audioDevices, category: .audio, icon: "headphones", slug: "audio-devices", title: L("audio devices"),
                useCase: L("for picking headphones and a microphone before a match without opening system settings."),
                description: L("sets the system output and microphone without a trip to system settings, and the mic input level. warns when a bluetooth mic would drop your headphones to phone quality."),
                meta: L("audio · changes macos defaults · takes effect immediately")),
    ] }
    static func get(_ id: FeatureID) -> Feature { all.first { $0.id == id }! }
}

struct Settings: Codable, Equatable {
    var crossoverPath = ""                           // empty: look in the usual places
    var logPath = "~/Library/Logs/mgf/regsave.log"   // empty: no log
    var busyCpu = 5.0                                // percent of one core
    var udpClass = 3                                 // 3 interactive video, 4 voice
    var ioMs = 5.33
    var reapply = true
    var language: String?                            // "en" or "ru"; nil follows macos
    var fkeysTriggers: [String] = []
    var fkeysApps: Bool?                             // follow the app list; nil counts as on
    var fkeysGameMode = false
    var wanted: [String]?                            // fixes to keep applied; nil until the disk has been looked at
    var setupDone: Bool?                             // nil until the first-run setup has been finished
    var setupStep: Int?                              // where the setup stands: it survives the relaunch macos asks for

    static func load() -> Settings {
        UserDefaults.standard.data(forKey: "settings").flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "settings") }
}

@MainActor @Observable final class AppModel {
    enum Screen: Equatable { case fixes, tools, settings, article(FeatureID) }
    enum Confirm { case apply, revert }

    var screen: Screen = .fixes
    var category: Category?
    var settings = Settings.load() { didSet { if live, settings != oldValue { settings.save() } } }
    var confirm: Confirm?
    var permissionNeeded = false                    // macos refused a write into crossover: explain how to allow it
    var log: [TermLine] = []
    var toasts: [Toast] = []

    // what the system looks like right now
    private(set) var crossover: CrossOver?
    private(set) var wineserver: WineserverConfig?
    private(set) var audioFix: Double?
    private(set) var canPatch: Bool?                // app management: macos lets us write into crossover. nil until asked
    private(set) var pending: Set<FeatureID> = []   // changed while Wine was running: waits for a restart
    // Only what the window shows is observed, and only assigned when it changes: the process list as a
    // whole churns every couple of seconds and would redraw the window each time.
    private(set) var wineNames: Set<String> = []    // .exe processes running under Wine
    private(set) var appNames: Set<String> = []     // ordinary apps, by executable name
    private(set) var wineRunning = false
    private(set) var gameModeOn = false
    private(set) var fkeysOn = false
    private(set) var devices: [AudioDevice] = []
    private(set) var outputID: AudioDeviceID?
    private(set) var inputID: AudioDeviceID?
    private(set) var inputVolume: Double?
    private(set) var loginItem = false
    private(set) var busy = false

    /// false while rendering snapshots and in a dry run: read the system, never change it, settings included.
    @ObservationIgnored let live: Bool
    @ObservationIgnored private let processList = ProcessList()
    @ObservationIgnored private let processQueue = DispatchQueue(label: "mgf.processes")
    @ObservationIgnored private var gameMode: GameMode?
    @ObservationIgnored private var auto = AutoSwitch()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var reapplied = false
    @ObservationIgnored private var runningNames: Set<String> = []

    init(live: Bool = true) {
        self.live = live
        locateCrossOver()
        refreshFixes()
        adoptDiskState()
        fkeysOn = FunctionKeys.isOn
        refreshAudio()
        loginItem = SMAppService.mainApp.status == .enabled
        gameMode = GameMode { [weak self] on in self?.gameModeOn = on; self?.evaluateTriggers() }
        gameModeOn = gameMode?.isOn ?? false
        take(processList.snapshot())
        refreshApps()
        reportStatus()
        guard live else { return }
        AudioSystem.observe { [weak self] in self?.refreshAudio() }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFixes(); self?.refreshAudio() }
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshApps() }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
        evaluateTriggers()
    }

    // MARK: derived state

    /// The fixes page, narrowed by the category picked in the sidebar.
    var shownFixes: [Feature] { Feature.all.filter { $0.isFix && (category == nil || $0.category == category) } }
    var tools: [Feature] { Feature.all.filter { !$0.isFix } }
    /// The sidebar page the current screen belongs to: an article belongs to its feature's page.
    var page: Screen { if case .article(let id) = screen { return Feature.get(id).home }; return screen }
    var appliedFixes: [FeatureID] { FeatureID.fixes.filter(isApplied) }
    var missingFixes: [FeatureID] { FeatureID.fixes.filter { !isApplied($0) } }
    /// Steam itself, not its helpers (steamwebhelper.exe can stay behind for hours after Steam quits):
    /// the Windows client under Wine, and the native macOS client.
    var steamWine: Bool { wineNames.contains { $0.lowercased() == "steam.exe" } }
    var steamNative: Bool { appNames.contains("steam_osx") }
    var steamRunning: Bool { steamWine || steamNative }
    var payload: URL { Bundle.module.resourceURL!.appendingPathComponent("Payload") }
    private var fixes: Fixes? { crossover.map { Fixes(crossover: $0, payload: payload) } }

    func isApplied(_ id: FeatureID) -> Bool {
        switch id {
        case .regsave: return (wineserver?.busyCpu ?? 0) > 0
        case .wifi: return (wineserver?.udpService ?? 0) != 0
        case .audioBuffer: return audioFix != nil
        case .fkeys: return fkeysOn
        case .audioDevices: return true
        }
    }

    /// Changes for the confirmation dialog, each file once: both network fixes share the wrapper.
    func changes(for ids: [FeatureID]) -> [Feature.Change] {
        var seen = Set<String>()
        return ids.flatMap { Feature.get($0).changes }.filter { seen.insert($0.path).inserted }
    }

    /// Wine helpers nobody would pick as "the game".
    private static let plumbing: Set<String> = ["explorer.exe", "services.exe", "winedevice.exe", "plugplay.exe", "svchost.exe", "rpcss.exe", "winewrapper.exe",
        "conhost.exe", "start.exe", "wineboot.exe", "steamwebhelper.exe", "steamservice.exe", "gameoverlayui.exe", "gameoverlayui64.exe", "tabtip.exe"]

    /// Running things worth offering as a trigger: Wine .exe files and ordinary apps.
    var triggerCandidates: [(name: String, isWine: Bool)] {
        let wine = wineNames.filter { !Self.plumbing.contains($0.lowercased()) }.map { (name: $0, isWine: true) }
        let apps = appNames.subtracting(wineNames).map { (name: $0, isWine: false) }
        return (wine.sorted { $0.name.lowercased() < $1.name.lowercased() } + apps.sorted { $0.name.lowercased() < $1.name.lowercased() })
            .filter { !settings.fkeysTriggers.contains($0.name) }
    }

    // MARK: looking at the system

    private func locateCrossOver() {
        let chosen = settings.crossoverPath.isEmpty ? nil : CrossOver(path: settings.crossoverPath)
        crossover = chosen.flatMap { $0.isValid ? $0 : nil } ?? (settings.crossoverPath.isEmpty ? CrossOver.detect() : nil)
    }

    func refreshFixes() {
        wineserver = fixes?.wineserverConfig()
        audioFix = fixes?.audioIOms()
        reapplyIfWiped()
    }

    /// First launch on a machine where the shell installer already ran: take its knobs as the settings.
    private func adoptDiskState() {
        guard settings.wanted == nil else { return }
        if let config = wineserver {
            if config.busyCpu > 0 { settings.busyCpu = config.busyCpu * 100 }
            if config.udpService != 0 { settings.udpClass = config.udpService }
            settings.logPath = config.log ?? ""
        }
        if let audioFix { settings.ioMs = (audioFix * 100).rounded() / 100 }
        if crossover != nil { settings.wanted = appliedFixes.map(\.rawValue) }
    }

    func refreshAudio() {
        devices = AudioSystem.devices()
        outputID = AudioSystem.defaultDevice(input: false)
        inputID = AudioSystem.defaultDevice(input: true)
        inputVolume = inputID.flatMap(AudioSystem.inputVolume).map(Double.init)
    }

    private func poll() {
        processQueue.async { [processList] in
            let snapshot = processList.snapshot()
            DispatchQueue.main.async { MainActor.assumeIsolated {
                self.take(snapshot)
                let on = FunctionKeys.isOn
                if on != self.fkeysOn { self.fkeysOn = on }
                self.evaluateTriggers()
            } }
        }
    }

    /// Ordinary apps come from the workspace, which tells us when one starts or quits: no polling.
    private func refreshApps() {
        let apps = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .compactMap { $0.executableURL?.lastPathComponent }.filter { !$0.lowercased().hasPrefix("wine") })
        if apps != appNames { appNames = apps }
    }

    private func take(_ snapshot: [ProcessEntry]) {
        runningNames = Set(snapshot.map(\.name))
        let wine = Set(snapshot.filter(\.isWine).map(\.name))
        let server = !runningNames.isDisjoint(with: ["wineserver.real", "wineserver"])
        if wine != wineNames { wineNames = wine }
        if server != wineRunning { wineRunning = server }
        if !server, !pending.isEmpty { pending = [] }
    }

    private func reportStatus() {
        say(.command, "mgf status")
        if let crossover {
            say(.ok, "[ OK ] " + L("crossover %@ found", crossover.version ?? "?"))
            for id in FeatureID.fixes {
                isApplied(id) ? say(.ok, "[ OK ] " + Feature.get(id).title) : say(.output, "[SKIP] " + L("%@: not applied", Feature.get(id).title))
            }
        } else {
            say(.error, "[FAIL] " + L("crossover not found. set the path in settings"))
        }
    }

    // MARK: log and toasts

    func say(_ kind: TermLine.Kind, _ text: String) { log = Array((log + [TermLine(kind: kind, text: text)]).suffix(60)) }

    func toast(_ tone: Tone, _ title: String, _ message: String = "") {
        let toast = Toast(tone: tone, title: title, message: message)
        toasts = Array((toasts + [toast]).suffix(3))
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) { [weak self] in self?.toasts.removeAll { $0.id == toast.id } }
    }

    private func fail(_ what: String, _ error: Error) {
        let ns = error as NSError
        // App Management: macos answers EPERM to an app that changes another app without the user's consent
        if ns.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains(ns.code) || ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteNoPermissionError {
            say(.error, "[FAIL] \(what): " + L("macos blocked the change"))
            permissionNeeded = !inSetup     // the setup has its own step for this
            return
        }
        say(.error, "[FAIL] \(what): \(error.localizedDescription)")
        toast(.danger, what, error.localizedDescription)
    }

    // MARK: fixes

    /// What to relaunch so the new files load. The patched server starts with the bottle, so restarting
    /// a game is not enough while Steam keeps the bottle alive, and helpers left behind keep it alive too.
    var restartTarget: String {
        if steamWine { return "steam" }
        let games = wineNames.filter { !Self.plumbing.contains($0.lowercased()) }.sorted()
        if !games.isEmpty { return games.prefix(2).joined(separator: ", ") }
        return wineNames.isEmpty ? "crossover" : L("wine (%@ still running)", wineNames.sorted().prefix(2).joined(separator: ", "))
    }
    private var restartNote: String { wineRunning ? L("restart %@ to activate", restartTarget) : "" }

    /// Brings the disk to "exactly these fixes applied", off the main thread: codesign takes a moment.
    private func write(_ want: Set<FeatureID>, touching ids: [FeatureID], then done: @escaping (Error?) -> Void) {
        guard let fixes else { done(FixError.missing("CrossOver.app")); return }
        let config = WineserverConfig(busyCpu: want.contains(.regsave) ? settings.busyCpu / 100 : 0, udpService: want.contains(.wifi) ? settings.udpClass : 0,
                                      log: settings.logPath.isEmpty ? nil : (settings.logPath as NSString).expandingTildeInPath)
        let ioMs = settings.ioMs
        busy = true
        Task.detached {
            let failure: Error? = {
                do {
                    if ids.contains(.regsave) || ids.contains(.wifi) { try config.isIdle ? fixes.uninstallWineserver() : fixes.installWineserver(config) }
                    if ids.contains(.audioBuffer) { try want.contains(.audioBuffer) ? fixes.installAudio(ioMs: ioMs) : fixes.uninstallAudio() }
                    return nil
                } catch { return error }
            }()
            await MainActor.run {
                self.busy = false
                self.wineserver = fixes.wineserverConfig()
                self.audioFix = fixes.audioIOms()
                done(failure)
            }
        }
    }

    func setFixes(_ ids: [FeatureID], on: Bool, then done: @escaping (Bool) -> Void = { _ in }) {
        guard live, !ids.isEmpty else { done(false); return }
        var want = Set(appliedFixes)
        if on { want.formUnion(ids) } else { want.subtract(ids) }
        let names = ids.map { Feature.get($0).title }.joined(separator: ", ")
        say(.command, "mgf \(on ? "apply" : "revert") \(ids.map(\.rawValue).joined(separator: " "))")
        write(want, touching: ids) { [self] error in
            if let error { fail(names, error); done(false); return }
            settings.wanted = want.map(\.rawValue).sorted()
            if wineRunning { pending.formUnion(ids) }
            for id in ids { say(.ok, "[ OK ] " + (on ? L("%@: applied", Feature.get(id).title) : L("%@: original restored", Feature.get(id).title))) }
            if wineRunning { say(.warn, "[WARN] " + restartNote) }
            if !inSetup { toast(on ? .success : .info, on ? L("%@ applied", names) : L("%@ removed", names), restartNote) }  // the setup shows its log
            done(true)
        }
    }

    /// CrossOver updates and CXPatcher re-patches replace the patched files. Put back what was wanted, once per launch.
    private func reapplyIfWiped() {
        guard live, !inSetup, !reapplied, !busy, let wanted = settings.wanted else { return }
        let wiped = FeatureID.fixes.filter { wanted.contains($0.rawValue) && !isApplied($0) }
        guard !wiped.isEmpty, crossover != nil else { return }
        reapplied = true
        guard settings.reapply else {  // the user wants to do it by hand: say so, once
            say(.warn, "[WARN] " + L("crossover was updated: the fixes are gone"))
            toast(.warning, L("crossover was updated: the fixes are gone"), L("apply them again from the fixes page"))
            return
        }
        say(.output, "[INFO] " + L("crossover was updated: applying the fixes again"))
        setFixes(wiped, on: true)
    }

    // MARK: function keys

    func setFkeys(_ on: Bool, manual: Bool = true) {
        guard live else { return }
        do {
            try FunctionKeys.set(on)
            fkeysOn = FunctionKeys.isOn
            if manual { auto.manualChange() }
            say(.ok, "[ OK ] " + L("function keys") + ": " + (on ? L("top row sends f1–f12") : L("top row controls brightness and media")) + (manual ? "" : " · " + L("automatic")))
        } catch { fail(L("function keys"), error) }
    }

    func setTriggers(_ names: [String], apps: Bool, gameMode: Bool) {
        settings.fkeysTriggers = names
        settings.fkeysApps = apps
        settings.fkeysGameMode = gameMode
        evaluateTriggers()
    }

    private func evaluateTriggers() {
        guard live else { return }
        let active = (settings.fkeysApps ?? true) && settings.fkeysTriggers.contains(where: runningNames.contains) || (settings.fkeysGameMode && gameModeOn)
        if let want = auto.update(conditionActive: active, isOn: fkeysOn) { setFkeys(want, manual: false) }
    }

    // MARK: audio devices

    func setDevice(_ id: AudioDeviceID, input: Bool) {
        guard live else { return }
        do {
            try AudioSystem.setDefault(id, input: input)
            refreshAudio()
            say(.ok, "[ OK ] " + L("audio devices") + ": " + (input ? L("microphone") : L("output")) + " " + (devices.first { $0.id == id }?.name ?? ""))
        } catch { fail(L("audio devices"), error) }
    }

    func setInputVolume(_ volume: Double) {
        guard live, let inputID else { return }
        inputVolume = volume
        try? AudioSystem.setInputVolume(inputID, Float(volume))
    }

    // MARK: first-run setup

    var inSetup: Bool { settings.setupDone != true }

    func setLanguage(_ code: String) {
        languageBundle = bundle(forLanguage: code)  // before anything reads a string
        settings.language = code
    }

    /// The bundle picked in the setup: from here on the fixes go into this one.
    func useCrossOver(_ path: String) {
        settings.crossoverPath = path
        locateCrossOver()
        refreshFixes()
        adoptDiskState()
    }

    /// App Management has no API to ask: try, and see what macOS says (CrossOver.isWritable).
    func refreshPermission() {
        let allowed = crossover?.isWritable
        if allowed != canPatch { canPatch = allowed }
    }

    func openAppManagement() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!)
    }

    func finishSetup(loginItem wantLogin: Bool) {
        setLoginItem(wantLogin)
        settings.setupStep = nil
        settings.setupDone = true
        screen = .fixes
    }

    func restartSetup() {
        settings.setupStep = 0
        settings.setupDone = nil
    }

    private func setLoginItem(_ want: Bool) {
        guard live, want != loginItem else { return }
        do { try want ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() } catch { fail(L("open at login"), error) }
        loginItem = SMAppService.mainApp.status == .enabled
    }

    // MARK: settings

    /// nil when the path holds a CrossOver bundle.
    func crossoverProblem(_ path: String) -> String? {
        CrossOver(path: path).isValid ? nil : L("no wineserver under this path. expected a CrossOver.app bundle")
    }

    func apply(_ next: Settings, loginItem wantLogin: Bool) {
        let knobsChanged = next.busyCpu != settings.busyCpu || next.udpClass != settings.udpClass || next.logPath != settings.logPath || next.ioMs != settings.ioMs
        let moved = next.crossoverPath != settings.crossoverPath
        if next.language != settings.language { languageBundle = bundle(forLanguage: next.language) }  // before anything reads a string
        settings = next
        if moved { locateCrossOver(); refreshFixes() }
        setLoginItem(wantLogin)
        say(.ok, "[ OK ] " + L("settings saved"))
        guard live, knobsChanged, !appliedFixes.isEmpty else { toast(.success, L("settings saved")); return }
        // the knobs live inside CrossOver: rewrite the wrapper and the buffer file
        write(Set(appliedFixes), touching: appliedFixes) { [self] error in
            if let error { fail(L("settings"), error); return }
            if wineRunning { pending.formUnion(appliedFixes) }
            toast(.success, L("settings saved"), restartNote)
        }
    }
}
