// Settings: nothing is written until "save". Paths and knobs here replace anything hardcoded.
import AppKit
import MGFCore
import SwiftUI
import UniformTypeIdentifiers

/// The open panel for picking CrossOver.app; nil when it is cancelled.
@MainActor func chooseApplication() -> String? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    return panel.runModal() == .OK ? panel.url.map { ($0.path as NSString).abbreviatingWithTildeInPath } : nil
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = "paths"
    @State private var draft = Settings()
    @State private var baseline = Settings()
    @State private var busyCpu = ""
    @State private var ioMs = ""
    @State private var loginItem = false
    @State private var loaded = false

    private func number(_ text: String, _ range: ClosedRange<Double>) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".")).flatMap { range.contains($0) ? $0 : nil }
    }
    /// The draft with the two numeric fields parsed in, nil while either is not a valid number.
    private var parsed: Settings? {
        guard let busy = number(busyCpu, 1...100), let io = number(ioMs, 0...20) else { return nil }
        var next = draft
        next.busyCpu = busy
        next.ioMs = io
        return next
    }
    private var dirty: Bool { parsed != baseline || loginItem != model.loginItem }

    private func load() {
        draft = model.settings
        if draft.crossoverPath.isEmpty, let found = model.crossover { draft.crossoverPath = (found.bundle.path as NSString).abbreviatingWithTildeInPath }
        baseline = draft
        busyCpu = String(format: "%g", draft.busyCpu)
        ioMs = String(format: "%g", draft.ioMs)
        loginItem = model.loginItem
        loaded = true
    }

    var body: some View {
        let pathProblem = model.crossoverProblem(draft.crossoverPath)
        VStack(alignment: .leading, spacing: 0) {
            HxTabs(items: [("paths", L("paths")), ("fixes", L("fixes")), ("app", L("app"))], selection: $tab).reveal(0)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case "paths": paths(pathProblem)
                    case "fixes": knobs
                    default: app
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 24)
            }
            .id(tab).reveal(1)
            Rectangle().fill(Hax.borderSubtle).frame(height: 1)
            HStack(spacing: 8) {
                HxHint(dirty ? L("unsaved changes · apply to new wine processes") : L("changes apply to new wine processes"))
                Spacer()
                HxButton(title: L("discard"), variant: .ghost) { load() }.disabled(!dirty)
                HxButton(title: L("save"), variant: .primary, prompt: true, loading: model.busy) {
                    if let parsed { model.apply(parsed, loginItem: loginItem); load() }
                }
                .disabled(!dirty || parsed == nil || pathProblem != nil || model.busy)
            }
            .padding(.vertical, 16)
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.horizontal, 24).padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { if !loaded { load() } }
    }

    @ViewBuilder private func paths(_ problem: String?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            HxInput(label: L("crossover app"), text: $draft.crossoverPath, prompt: true,
                    hint: L("crossover %@ · fixes are written inside this bundle", CrossOver(path: draft.crossoverPath).version ?? "?"), error: problem)
            HxButton(title: L("browse"), icon: "folder-open") { if let picked = chooseApplication() { draft.crossoverPath = picked } }
            .padding(.top, 23)  // sits on the field's row, under the label
            HxButton(title: L("detect"), icon: "scan-search") {
                if let found = CrossOver.detect() { draft.crossoverPath = (found.bundle.path as NSString).abbreviatingWithTildeInPath }
            }
            .padding(.top, 23)
        }
        VStack(alignment: .leading, spacing: 6) {
            let crossover = CrossOver(path: draft.crossoverPath)
            derived("wineserver", crossover.wineserver)
            derived(L("audio driver"), crossover.audioDriver)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Hax.radiusMD).strokeBorder(Hax.borderDefault, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        HxInput(label: L("log file"), text: $draft.logPath, optional: true, hint: L("one line per registry decision. empty turns logging off"))
    }

    private func derived(_ name: String, _ url: URL) -> some View {
        let exists = FileManager.default.fileExists(atPath: url.path)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: name).foregroundStyle(Hax.textMuted).frame(width: 110, alignment: .leading)
            Text(verbatim: (url.path as NSString).abbreviatingWithTildeInPath).foregroundStyle(Hax.textSecondary).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            HxBadge(text: exists ? "OK" : "FAIL", tone: exists ? .success : .danger, bracket: true)
        }
        .font(Hax.caption)
    }

    @ViewBuilder private var knobs: some View {
        HxInput(label: L("busy threshold"), text: $busyCpu, suffix: L("% cpu"),
                hint: L("registry saves wait while wineserver uses more than this. 17 % measured with deadlock"),
                error: number(busyCpu, 1...100) == nil ? L("a number from 1 to 100") : nil)
        HxSelect(label: L("udp service class"), options: [.init(id: "3", label: L("interactive video · default")), .init(id: "4", label: L("voice"))],
                 selection: String(draft.udpClass), hint: L("what game sockets ask the wi-fi chip for")) { draft.udpClass = Int($0) ?? 3 }
        HxInput(label: L("audio io buffer"), text: $ioMs, suffix: L("ms"),
                hint: L("5.33 ms is 512 frames at 96 khz. 0 leaves coreaudio's default"),
                error: number(ioMs, 0...20) == nil ? L("a number from 0 to 20") : nil)
        HxSwitch(isOn: $draft.reapply, label: L("re-apply fixes after a crossover update"), showState: true)
        HxHint(L("updates and cxpatcher re-patches replace the patched files"))
    }

    @ViewBuilder private var app: some View {
        HxSelect(label: L("language"), options: [.init(id: "", label: L("same as macos")), .init(id: "en", label: "english"), .init(id: "ru", label: "русский")],
                 selection: draft.language ?? "", hint: L("the interface and the articles switch when you save")) { draft.language = $0.isEmpty ? nil : $0 }
        HxSwitch(isOn: $loginItem, label: L("open at login"))
        HxHint(L("triggers only work while the app is running. closing the window quits it"))
        HxLabel(L("macos permission"))
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: L("app management")).font(Hax.bodySmall).foregroundStyle(Hax.textPrimary)
                PermissionState()
                HxHint(L("lets mgf write the fixes into crossover. macos ties it to the app's signature and may ask again after an update"))
            }
            Spacer()
            HxButton(title: L("open system settings"), iconRight: "arrow-up-right") { model.openAppManagement() }
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: Hax.radiusMD).strokeBorder(Hax.borderDefault, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        HxLabel(L("first-run setup"))
        HxButton(title: L("run setup again"), icon: "rotate-ccw") { model.restartSetup() }
        HxLabel(L("settings store"))
        HxCommandLine(command: "defaults read \(Bundle.main.bundleIdentifier ?? "earth.been.mgf")")
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: L("revert every fix")).font(Hax.bodySmall).foregroundStyle(Hax.textPrimary)
                HxHint(L("restores the original wineserver and audio driver. settings are kept."))
            }
            Spacer()
            HxButton(title: L("revert all"), variant: .danger) { model.confirm = .revert }.disabled(model.appliedFixes.isEmpty)
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: Hax.radiusMD).strokeBorder(Hax.borderDefault, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}
