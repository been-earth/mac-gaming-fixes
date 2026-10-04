// First-run setup: five steps and a closing screen in the app window, without the sidebar.
// What the app is and the language, what it fixes, where CrossOver is, the one macOS permission,
// the first apply. The setup itself cannot be skipped; applying the fixes can.
import AppKit
import MGFCore
import SwiftUI

struct SetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // crossover step
    @State private var path = ""
    @State private var scan: [TermLine] = []
    @State private var typing = false
    @State private var scanTask: Task<Void, Never>?
    // permission step
    @State private var waiting = false
    // apply step
    @State private var picks = Set(FeatureID.fixes)
    @State private var running = false
    @State private var logMark: UUID?       // the last log line before apply was pressed
    // closing screen
    @State private var login = false     // opening at login is the user's call: it starts as macos has it

    private static let ready = 5            // the closing screen, after the five steps
    private static let side: CGFloat = 420  // the terminal or illustration next to a step
    /// Kept in settings: granting the permission can make macOS quit and reopen the app.
    private var step: Int { min(max(model.settings.setupStep ?? 0, 0), Self.ready) }
    private func go(_ step: Int) { model.settings.setupStep = step }

    var body: some View {
        VStack(spacing: 0) {
            top.frame(maxWidth: .infinity).frame(height: Hax.topbar).background(Hax.bgPanel)
            Rectangle().fill(Hax.borderSubtle).frame(height: 1)
            GeometryReader { geo in
                ScrollView {
                    content(width: geo.size.width)
                        .frame(maxWidth: 1040)
                        .padding(.horizontal, 48).padding(.vertical, 32)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
            }
            .id(step)   // every step reveals itself
            Rectangle().fill(Hax.borderSubtle).frame(height: 1)
            foot
        }
        .background(Hax.bgPage)
        .onChange(of: step, initial: true) { _, step in
            if step == 2 { scanCrossOver(model.crossover.map { tilde($0.bundle.path) } ?? model.settings.crossoverPath) }
            if step == 3 { waiting = false }
            if step == Self.ready { login = model.loginItem }
        }
    }

    // MARK: frame

    private var top: some View {
        let names = [L("hello"), L("what it fixes"), "crossover", L("permission"), L("apply")]
        let shown = min(step, names.count - 1)
        return HStack(spacing: 12) {
            // the system's own window buttons sit in the first 78 points
            Image(nsImage: Brand.wordmark).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(height: 18)
                .accessibilityLabel("MGF")
            HStack(spacing: 6) {
                Text(verbatim: "mgf")
                Text(verbatim: "/").foregroundStyle(Hax.textDisabled)
                Text(verbatim: L("setup"))
                Text(verbatim: "/").foregroundStyle(Hax.textDisabled)
                Text(verbatim: names[shown]).foregroundStyle(Hax.textPrimary)
            }
            .font(Hax.bodySmall).foregroundStyle(Hax.textMuted).lineLimit(1).padding(.leading, 8)
            Spacer(minLength: 16)
            HStack(spacing: 3) {
                ForEach(names.indices, id: \.self) { index in
                    Text(verbatim: index <= shown ? "■" : "□").foregroundStyle(index <= shown ? Hax.accent : Hax.textDisabled)
                }
            }
            .font(Hax.caption).accessibilityElement(children: .ignore).accessibilityLabel("\(shown + 1) / \(names.count)")
        }
        .padding(.leading, 78).padding(.trailing, 16)
    }

    private var foot: some View {
        let primary = primary
        return HStack(spacing: 8) {
            HStack(spacing: 8) {
                if step > 0 && step < Self.ready && !running {
                    HxButton(title: L("back"), variant: .ghost, icon: "arrow-left") { go(step - 1) }.keyboardShortcut(.cancelAction)
                }
                // without the permission nothing can be applied, but the tools still work
                if step == 3 && model.canPatch != true {
                    HxButton(title: L("set up without fixes"), variant: .ghost) { go(Self.ready) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) { HxKbd(text: "↵"); Text(verbatim: primary.title) }
                .font(Hax.caption).foregroundStyle(Hax.textMuted).opacity(primary.enabled ? 1 : 0).accessibilityHidden(true)
            HStack(spacing: 8) {
                if step == 4 && !running && !pending.isEmpty {
                    HxButton(title: L("skip")) { go(Self.ready) }
                }
                HxButton(title: primary.title, variant: .primary, prompt: !primary.loading, loading: primary.loading, action: primary.run)
                    .disabled(!primary.enabled).keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 12).background(Hax.bgPanel)
    }

    private struct Action {
        let title: String
        var enabled = true
        var loading = false
        var run: () -> Void = {}
    }

    /// Fixes that are not on disk yet: the ones the apply step can add.
    private var pending: [FeatureID] { FeatureID.fixes.filter { !model.isApplied($0) } }

    private var primary: Action {
        switch step {
        case 0: return Action(title: L("start setup")) { go(1) }
        case 1: return Action(title: L("continue")) { go(2) }
        case 2: return Action(title: L("continue"), enabled: !typing && model.crossoverProblem(path) == nil) { model.useCrossOver(path); go(3) }
        case 3: return Action(title: L("continue"), enabled: model.canPatch == true) { go(4) }
        case 4:
            if running { return Action(title: L("applying"), enabled: false, loading: true) }
            if pending.isEmpty { return Action(title: L("continue")) { go(Self.ready) } }
            let chosen = pending.filter(picks.contains)
            let title = chosen.isEmpty ? L("apply fixes") : chosen.count == 1 ? L("apply 1 fix") : L("apply %d fixes", chosen.count)
            return Action(title: title, enabled: !chosen.isEmpty && model.crossover != nil) { apply(chosen) }
        default: return Action(title: L("open mgf")) { model.finishSetup(loginItem: login) }
        }
    }

    @ViewBuilder private func content(width: CGFloat) -> some View {
        switch step {
        case 0: hello(width: width)
        case 1: pains
        case 2: crossover
        case 3: permission
        case 4: applyStep
        default: ready
        }
    }

    private func head(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(title)
            Text(verbatim: text).font(Hax.body).foregroundStyle(Hax.textSecondary).lineSpacing(4)
                .frame(maxWidth: 600, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func heading(_ title: String) -> some View {
        Text(verbatim: title).font(Hax.mono(28, .medium)).tracking(-0.4).foregroundStyle(Hax.textPrimary).fixedSize(horizontal: false, vertical: true)
    }

    private func tilde(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }

    // MARK: hello

    private var detected: String { Bundle.module.preferredLocalizations.first == "ru" ? "ru" : "en" }

    private func hello(width: CGFloat) -> some View {
        VStack(spacing: 24) {
            Image(nsImage: Brand.icon).resizable().interpolation(.high).frame(width: 88, height: 88).accessibilityHidden(true).reveal(0)
            Headline(text: L("windows games on a mac. no *net jitter*, no *broken sound*."), size: min(40, max(28, width * 0.033)))
                .frame(maxWidth: 900).reveal(1)
            Text(verbatim: L("mgf patches crossover's wine for online games: three fixes for network stalls and sound, two tools for keys and audio devices. every change can be reverted."))
                .font(Hax.body).foregroundStyle(Hax.textSecondary).lineSpacing(4).multilineTextAlignment(.center)
                .frame(maxWidth: 560).fixedSize(horizontal: false, vertical: true).reveal(2)
            VStack(spacing: 12) {
                Text(verbatim: "LANGUAGE / ЯЗЫК").font(Hax.overline).tracking(0.9).foregroundStyle(Hax.textMuted)
                HStack(spacing: 12) {
                    ForEach(Array(["en", "ru"].enumerated()), id: \.element) { index, code in
                        LanguageOption(code: code, key: index + 1, selected: (model.settings.language ?? detected) == code, detected: detected == code) {
                            model.setLanguage(code)
                        }
                    }
                }
            }
            .reveal(3)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: what it fixes

    /// Each feature as the player meets it: the pain first, then what the app does about it.
    fileprivate static func pitch(_ id: FeatureID) -> (pain: String, cure: String) {
        switch id {
        case .regsave: return (L("the game hitches every 30 seconds and the net jitter graph spikes."), L("wine's registry save is held back while you play."))
        case .wifi: return (L("constant net jitter on wi-fi although the connection is fine."), L("game sockets ask the wi-fi chip for real-time service."))
        case .audioBuffer: return (L("crackling sound and a choppy voice in voice chat."), L("a shorter audio buffer at any sample rate. no 96 khz device needed."))
        case .fkeys: return (L("a game wants f1–f12, the mac wants fn held down."), L("one switch, or automatically when the game starts."))
        case .audioDevices: return (L("headphones and microphone are picked deep in system settings."), L("output, microphone and input level in one place."))
        }
    }

    private var pains: some View {
        let features = Feature.all
        return VStack(alignment: .leading, spacing: 24) {
            head(L("what goes wrong, and what mgf does about it."), L("three fixes go inside crossover. two tools switch macos settings.")).reveal(0)
            VStack(spacing: 16) {
                ForEach(Array(gridRows(features.map(\.isFix)).enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(features[row]) { PainCard(feature: $0).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top) }
                    }
                    .fixedSize(horizontal: false, vertical: true).reveal(1 + index)
                }
            }
            HxHint(L("measured on m3 max, crossover 26.0, deadlock. every card has an article in the app.")).reveal(3)
        }
    }

    // MARK: crossover

    private var crossover: some View {
        let problem = typing ? nil : model.crossoverProblem(path)
        return HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 20) {
                head(typing ? L("looking for crossover…") : problem == nil ? L("found crossover.") : L("crossover not found."),
                     L("the fixes are written inside this bundle. every original file stays next to its replacement.")).reveal(0)
                HStack(alignment: .top, spacing: 8) {
                    HxInput(label: L("crossover app"), text: $path, prompt: true,
                            hint: typing ? nil : L("crossover %@ found", CrossOver(path: path).version ?? "?"), error: problem)
                    HxButton(title: L("browse"), icon: "folder-open") { if let picked = chooseApplication() { scanCrossOver(picked) } }
                        .padding(.top, 23)  // sits on the field's row, under the label
                    HxButton(title: L("detect again"), icon: "scan-search") { scanCrossOver(CrossOver.detect().map { tilde($0.bundle.path) } ?? path) }
                        .padding(.top, 23)
                }
                .reveal(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HxTerminal(title: "mgf — detect", lines: scan).frame(width: Self.side, height: 264).reveal(2)
        }
        .onChange(of: path) { if !typing { scan = [TermLine(kind: .command, text: "mgf detect")] + lines(for: path) } }
    }

    private func lines(for path: String) -> [TermLine] {
        if let problem = model.crossoverProblem(path) { return [TermLine(kind: .error, text: "[FAIL] " + problem)] }
        let crossover = CrossOver(path: path), fixes = Fixes(crossover: crossover, payload: model.payload)
        return [
            TermLine(kind: .ok, text: "[ OK ] " + path),
            TermLine(kind: .ok, text: "[ OK ] crossover " + (crossover.version ?? "?")),
            TermLine(kind: .ok, text: "[ OK ] wineserver · " + (fixes.wineserverConfig() == nil ? L("stock") : L("patched"))),
            TermLine(kind: .ok, text: "[ OK ] winecoreaudio.so · " + (fixes.audioIOms() == nil ? L("stock") : L("patched"))),
        ]
    }

    /// Looks at the bundle under `newPath`; the findings arrive one line at a time, the way the activity log fills in.
    private func scanCrossOver(_ newPath: String) {
        scanTask?.cancel()
        typing = true
        path = newPath
        scan = [TermLine(kind: .command, text: "mgf detect")]
        let found = lines(for: newPath)
        scanTask = Task { @MainActor in
            for line in found {
                if !reduceMotion { try? await Task.sleep(for: .milliseconds(340)) }
                if Task.isCancelled { return }
                scan.append(line)
            }
            typing = false
        }
    }

    // MARK: permission

    private var permission: some View {
        let allowed = model.canPatch == true
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "MacGamingFixes"
        return HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 20) {
                head(L("one permission from macos."),
                     L("macos does not let one app change another until you allow it. mgf needs it once, to write the fixes into crossover.")).reveal(0)
                VStack(alignment: .leading, spacing: 8) {
                    numbered(1, L("open system settings → privacy & security → app management"))
                    numbered(2, L("turn on %@. if it is not in the list, add it with +", name))
                    numbered(3, L("come back here. if macos offers to quit and reopen mgf, agree: the setup continues from this step"))
                }
                .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                .surface(Hax.bgCard, border: Hax.borderSubtle, radius: Hax.radiusMD).reveal(1)
                HStack(spacing: 12) {
                    HxButton(title: L("open system settings"), variant: allowed ? .secondary : .primary, iconRight: "arrow-up-right") {
                        waiting = true
                        model.openAppManagement()
                    }
                    PermissionState(waiting: waiting)
                }
                .reveal(2)
                HxHint(L("no admin password, no sip changes, no full disk access")).reveal(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // what the pane looks like: an illustration, the real switch is in system settings
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) { HxLights(); Text(verbatim: L("system settings")) }
                    .font(Hax.caption).foregroundStyle(Hax.textMuted)
                    .padding(.horizontal, 12).frame(height: 34).frame(maxWidth: .infinity, alignment: .leading).background(Hax.bgPanel)
                Rectangle().fill(Hax.borderSubtle).frame(height: 1)
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: L("privacy & security › app management")).font(Hax.caption).foregroundStyle(Hax.textMuted)
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Image(nsImage: Brand.icon).resizable().interpolation(.high).frame(width: 24, height: 24)
                            Text(verbatim: name).foregroundStyle(Hax.textPrimary)
                            Spacer()
                            HxSwitch(isOn: .constant(allowed))
                        }
                        .padding(12)
                        Rectangle().fill(Hax.borderSubtle).frame(height: 1)
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: Hax.radiusSM).strokeBorder(Hax.borderDefault, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(width: 24, height: 24)
                            Text(verbatim: L("other apps")).foregroundStyle(Hax.textDisabled)
                            Spacer()
                        }
                        .padding(12)
                    }
                    .font(Hax.bodySmall).surface(Hax.bgPanel, border: Hax.borderSubtle)
                }
                .padding(16)
            }
            .surface(Hax.bgCard, border: Hax.borderDefault, radius: Hax.radiusMD).clipShape(RoundedRectangle(cornerRadius: Hax.radiusMD))
            .frame(width: Self.side).allowsHitTesting(false).accessibilityHidden(true).reveal(2)
        }
    }

    private func numbered(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: "\(number).").foregroundStyle(Hax.accent)
            Text(verbatim: text).foregroundStyle(Hax.textPrimary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .font(Hax.bodySmall)
    }

    // MARK: apply

    private var applyStep: some View {
        HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 20) {
                head(L("pick the fixes to apply."),
                     L("originals are kept next to every file. each fix has its own switch in the app, so nothing here is final.")).reveal(0)
                VStack(spacing: 0) {
                    ForEach(Array(FeatureID.fixes.enumerated()), id: \.element) { index, id in
                        let feature = Feature.get(id), applied = model.isApplied(id)
                        if index > 0 { Rectangle().fill(Hax.borderSubtle).frame(height: 1) }
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            // a fix that is already on disk stays: the setup only adds
                            HxCheckbox(isOn: Binding(get: { applied || picks.contains(id) }, set: { if $0 { picks.insert(id) } else { picks.remove(id) } }),
                                       label: feature.title, detail: Self.pitch(id).pain)
                                .disabled(applied)
                            Spacer(minLength: 8)
                            Text(verbatim: applied ? L("applied") : L("files: %d", feature.changes.count))
                                .font(Hax.caption).foregroundStyle(applied ? Hax.success : Hax.textMuted).fixedSize()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                }
                .surface(Hax.bgCard, border: Hax.borderSubtle, radius: Hax.radiusMD)
                .disabled(running).opacity(running ? 0.55 : 1).reveal(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HxTerminal(title: "mgf — " + L("setup"),
                       lines: logMark == nil ? [TermLine(kind: .comment, text: "// " + L("nothing is written until you press apply"))] : runLog)
                .frame(width: Self.side, height: 264).reveal(2)
        }
    }

    /// What the log gained since apply was pressed; the whole log when this run has not applied anything.
    private var runLog: [TermLine] {
        guard let logMark, let index = model.log.firstIndex(where: { $0.id == logMark }) else { return model.log }
        return Array(model.log[(index + 1)...])
    }

    private func apply(_ ids: [FeatureID]) {
        running = true
        logMark = model.log.last?.id
        model.setFixes(ids, on: true) { applied in
            running = false
            if applied { go(Self.ready); return }
            // macos took the permission back between the steps: return to the step that asks for it
            model.refreshPermission()
            if model.canPatch == false { go(3) }
        }
    }

    // MARK: ready

    private var ready: some View {
        let count = model.appliedFixes.count
        return HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 20) {
                heading(count == 0 ? L("ready. no fixes applied yet.") : count == 1 ? L("ready. 1 fix is in place.") : L("ready. %d fixes are in place.", count)).reveal(0)
                VStack(alignment: .leading, spacing: 8) {
                    if count == 0 {
                        bullet(L("apply them any time from the fixes page"))
                    } else if model.wineRunning {
                        bullet(L("restart %@: games started earlier keep the old files", model.restartTarget))
                    }
                    if count > 0 { bullet(L("after a crossover update, open mgf once: it puts the fixes back")) }
                    bullet(L("function keys and audio devices are on the tools page"))
                    bullet(L("every fix has a switch and an article with its measurements"))
                }
                .reveal(1)
                HxCheckbox(isOn: $login, label: L("open at login"), detail: L("triggers only work while the app is running. closing the window quits it")).reveal(2)
                HxButton(title: L("star on github"), variant: .ghost, icon: "star", iconRight: "arrow-up-right") { NSWorkspace.shared.open(repoURL) }.reveal(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HxTerminal(title: "mgf — " + L("setup"), lines: runLog).frame(width: Self.side, height: 264).reveal(2)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "▸").foregroundStyle(Hax.accent)
            Text(verbatim: text).foregroundStyle(Hax.textSecondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .font(Hax.body)
    }
}

/// A headline whose words light up one after another. The phrases between asterisks take the accent
/// colour and never break across lines.
private struct Headline: View {
    let text: String
    let size: CGFloat
    @State private var lit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var words: [Text] {
        var out: [Text] = []
        for (index, part) in text.components(separatedBy: "*").enumerated() {
            if index % 2 == 1 { out.append(Text(verbatim: part).foregroundStyle(Hax.accent)); continue }
            var plain = part.split(separator: " ").map { Text(verbatim: String($0)) }
            // punctuation right after a phrase stays on it
            if !part.hasPrefix(" "), !plain.isEmpty, let phrase = out.popLast() { out.append(phrase + plain.removeFirst()) }
            out += plain
        }
        return out
    }

    var body: some View {
        FlowLayout(spacing: size * 0.57, lineSpacing: 0, centered: true) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                word.opacity(lit ? 1 : 0.12)
                    .animation(reduceMotion ? nil : Hax.ease(Hax.base).delay(0.1 + Double(index) * 0.04), value: lit)
            }
        }
        .font(Hax.mono(size, .medium)).tracking(-size * 0.03).foregroundStyle(Hax.textPrimary)
        .accessibilityElement(children: .ignore).accessibilityLabel(text.replacingOccurrences(of: "*", with: ""))
        .onAppear { lit = true }
    }
}

private struct LanguageOption: View {
    let code: String, key: Int, selected: Bool, detected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let name = code == "ru" ? "русский" : "english"
        Button(action: action) {
            HStack(spacing: 12) {
                HxKbd(text: "\(key)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name).font(Hax.mono(14, .medium)).foregroundStyle(Hax.textPrimary)
                    if detected { Text(verbatim: "// " + L("detected from macos")).font(Hax.caption).foregroundStyle(Hax.textMuted) }
                }
                Spacer(minLength: 8)
                Text(verbatim: selected ? "[x]" : "[ ]").font(Hax.mono(13, .medium)).foregroundStyle(Hax.accent)
            }
            .padding(.horizontal, 16).frame(width: 280, height: 56)
            .surface(hovering ? Hax.bgRaised : Hax.bgCard, border: hovering ? Hax.borderStrong : Hax.borderSubtle, radius: Hax.radiusMD)
            .overlay(RoundedRectangle(cornerRadius: Hax.radiusMD).strokeBorder(selected ? Hax.accent : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }.animation(Hax.ease(Hax.fast), value: hovering)
        .keyboardShortcut(KeyEquivalent(Character("\(key)")), modifiers: [])
        .accessibilityLabel(name).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct PainCard: View {
    let feature: Feature

    var body: some View {
        let pitch = SetupView.pitch(feature.id)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                IconBox(icon: feature.icon, on: true)
                Text(verbatim: feature.title).font(Hax.mono(13, .medium)).foregroundStyle(Hax.textPrimary).lineLimit(1)
                Spacer(minLength: 4)
                Text(verbatim: feature.category.title).font(Hax.caption).foregroundStyle(Hax.textMuted)
            }
            .padding(.horizontal, 16).frame(height: 44)
            Rectangle().fill(Hax.borderSubtle).frame(height: 1)
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: pitch.pain).foregroundStyle(Hax.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(verbatim: pitch.cure).foregroundStyle(Hax.textMuted).fixedSize(horizontal: false, vertical: true)
                if let measure = feature.measure { MeasureBars(measure: measure).padding(.top, 8) }
            }
            .font(Hax.bodySmall).lineSpacing(3)
            .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .surface(Hax.bgCard, border: Hax.borderSubtle, radius: Hax.radiusMD)
    }
}

/// App Management as macOS last answered, asked again whenever the app comes to the front.
struct PermissionState: View {
    @Environment(AppModel.self) private var model
    var waiting = false     // system settings were just opened from here

    var body: some View {
        let allowed = model.canPatch == true
        HStack(spacing: 8) {
            if model.crossover == nil {
                HxBadge(text: "SKIP", bracket: true)
                Text(verbatim: L("crossover not found. set the path in settings"))
            } else {
                HxBadge(text: allowed ? "OK" : "WAIT", tone: allowed ? .success : waiting ? .info : .warning, bracket: true)
                Text(verbatim: allowed ? L("allowed") : waiting ? L("waiting for the switch") : L("not allowed yet"))
                if !allowed { HxButton(title: L("check again"), variant: .ghost, small: true) { model.refreshPermission() } }
            }
        }
        .font(Hax.caption).foregroundStyle(Hax.textMuted)
        .onAppear { model.refreshPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshPermission() }
    }
}
