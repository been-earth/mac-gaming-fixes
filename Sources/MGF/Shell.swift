// The window: the first-run setup, or sidebar, top bar, the current screen and status line; and the layers above them.
import AppKit
import MGFCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.inSetup { SetupView() } else { main }
        }
        .background(Hax.bgPage)
        .blur(radius: model.confirm == nil && !model.permissionNeeded ? 0 : 2)
        .overlay { if let confirm = model.confirm { ConfirmDialog(kind: confirm).transition(.opacity) } }
        .overlay { if model.permissionNeeded { PermissionDialog().transition(.opacity) } }
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 8) {
                ForEach(model.toasts) { toast in
                    HxToast(toast: toast) { model.toasts.removeAll { $0.id == toast.id } }
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
            }
            .padding(16)
        }
        .animation(Hax.ease(Hax.base), value: model.toasts)
        .animation(Hax.ease(Hax.base), value: model.confirm)
        .animation(Hax.ease(Hax.base), value: model.permissionNeeded)
        .onExitCommand { if case .article = model.screen, model.confirm == nil { model.screen = model.page } }
        .id(model.settings.language)    // a new language rebuilds every view: strings are read while drawing
        .frame(minWidth: 1100, minHeight: 640)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private var main: some View {
        HStack(spacing: 0) {
            Sidebar().frame(width: Hax.sidebar)
            Rectangle().fill(Hax.borderSubtle).frame(width: 1)
            VStack(spacing: 0) {
                Topbar().frame(height: Hax.topbar)
                Rectangle().fill(Hax.borderSubtle).frame(height: 1)
                Group {
                    switch model.screen {
                    case .fixes: FixesView().id(model.category)
                    case .tools: ToolsView()
                    case .settings: SettingsView()
                    case .article(let id): ArticleView(feature: Feature.get(id)).id(id)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(Hax.borderSubtle).frame(height: 1)
                StatusLine().frame(height: 28)
            }
        }
    }
}

/// A row that rises 8 px and fades in when its screen appears: the page-level reveal, staggered by `order`.
struct Reveal: ViewModifier {
    let order: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0).offset(y: shown ? 0 : 8)
            .onAppear {
                if reduceMotion { shown = true } else { withAnimation(Hax.ease(Hax.slow).delay(Double(order) * 0.04)) { shown = true } }
            }
    }
}
extension View {
    func reveal(_ order: Int) -> some View { modifier(Reveal(order: order)) }
}

private struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // the system's own window buttons sit in the first 78 points
                Image(nsImage: Brand.wordmark).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(height: 18)
                    .accessibilityLabel("MGF")
                Spacer()
                HxBadge(text: "v" + appVersion)
            }
            .padding(.leading, 78).padding(.trailing, 16).frame(height: Hax.topbar)
            Rectangle().fill(Hax.borderSubtle).frame(height: 1)

            VStack(spacing: 2) {
                NavItem(icon: "wrench", title: L("fixes"), count: FeatureID.fixes.count, active: model.page == .fixes) { model.screen = .fixes }
                NavItem(icon: "sliders-horizontal", title: L("tools"), count: model.tools.count, active: model.page == .tools) { model.screen = .tools }
                NavItem(icon: "settings", title: L("settings"), count: nil, active: model.screen == .settings) { model.screen = .settings }
            }
            .padding(8)

            section(L("categories"))
            VStack(spacing: 1) {
                // categories narrow the fixes page, so only fixes are counted and empty categories are left out
                let fixes = Feature.all.filter(\.isFix)
                ListItem(name: L("all"), meta: "\(fixes.count)", dot: nil, active: model.screen == .fixes && model.category == nil) { model.category = nil; model.screen = .fixes }
                ForEach(Category.allCases.filter { category in fixes.contains { $0.category == category } }, id: \.self) { category in
                    ListItem(name: category.title, meta: "\(fixes.filter { $0.category == category }.count)", dot: nil,
                             active: model.screen == .fixes && model.category == category) { model.category = category; model.screen = .fixes }
                }
            }
            .padding(.horizontal, 8)

            section(L("environment"))
            VStack(spacing: 1) {
                ListItem(name: "crossover", meta: model.crossover.map { $0.version ?? "?" } ?? L("not found"), dot: model.crossover == nil ? Hax.danger : Hax.success)
                ListItem(name: "wineserver", meta: model.wineserver == nil ? L("stock") : L("patched"), dot: model.wineserver == nil ? Hax.textDisabled : Hax.success)
                ListItem(name: "steam", meta: steamState, dot: model.steamRunning ? Hax.accent : Hax.textDisabled, pulse: model.steamRunning)
                ListItem(name: L("game mode"), meta: model.gameModeOn ? L("on") : L("off"), dot: model.gameModeOn ? Hax.accent : Hax.textDisabled)
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 0)
            Rectangle().fill(Hax.borderSubtle).frame(height: 1)
            (Text(verbatim: "~ ").foregroundStyle(Hax.accent) + Text(verbatim: "been-earth/mac-gaming-fixes").foregroundStyle(Hax.textSecondary))
                .font(Hax.mono(11)).lineLimit(1).padding(.horizontal, 16).frame(height: 40)
        }
        .background(Hax.bgPanel)
    }

    /// Which Steam is up matters: the fixes reach only the one under Wine.
    private var steamState: String {
        switch (model.steamWine, model.steamNative) {
        case (true, true): return "wine + " + L("native")
        case (true, false): return L("running") + " · wine"
        case (false, true): return L("running") + " · " + L("native")
        case (false, false): return L("not running")
        }
    }

    private func section(_ title: String) -> some View {
        Text(verbatim: title.uppercased()).font(Hax.overline).tracking(0.9).foregroundStyle(Hax.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
    }

    private struct NavItem: View {
        let icon: String, title: String, count: Int?, active: Bool
        let action: () -> Void
        @State private var hovering = false
        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    HxIcon(icon)
                    Text(verbatim: title).font(Hax.mono(13, .medium))
                    Spacer()
                    if let count { Text(verbatim: "\(count)").font(Hax.mono(11)).foregroundStyle(Hax.textMuted) }
                }
                .foregroundStyle(active ? Hax.accent : hovering ? Hax.textPrimary : Hax.textSecondary)
                .padding(.horizontal, 8).frame(height: 32)
                .background(active ? Hax.accentSoft : hovering ? Hax.bgRaised : .clear, in: RoundedRectangle(cornerRadius: Hax.radiusSM))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).onHover { hovering = $0 }.animation(Hax.ease(Hax.fast), value: hovering)
        }
    }

    private struct ListItem: View {
        let name: String, meta: String
        var dot: Color?
        var active = false
        var pulse = false
        var action: (() -> Void)?
        @State private var hovering = false

        var body: some View {
            let row = HStack(spacing: 8) {
                Circle().fill(dot ?? (active ? Hax.success : Hax.textDisabled)).frame(width: 6, height: 6).modifier(Pulse(active: pulse))
                Text(verbatim: name).font(Hax.bodySmall).lineLimit(1)
                Spacer()
                Text(verbatim: meta).font(Hax.mono(11)).foregroundStyle(Hax.textMuted).lineLimit(1)
            }
            .foregroundStyle(active || (hovering && action != nil) ? Hax.textPrimary : Hax.textSecondary)
            .padding(.horizontal, 8).frame(height: 30)
            .background(active || (hovering && action != nil) ? Hax.bgRaised : .clear, in: RoundedRectangle(cornerRadius: Hax.radiusSM))
            .overlay(alignment: .leading) { if active { Rectangle().fill(Hax.accent).frame(width: 2) } }
            .clipShape(RoundedRectangle(cornerRadius: Hax.radiusSM))
            .contentShape(Rectangle())
            if let action {
                Button(action: action) { row }.buttonStyle(.plain).onHover { hovering = $0 }.animation(Hax.ease(Hax.fast), value: hovering)
            } else {
                row.accessibilityElement(children: .combine)
            }
        }
    }
}

private struct Topbar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let path: [String] = {
            switch model.screen {
            case .fixes: return [L("fixes")] + (model.category.map { [$0.title] } ?? [])
            case .tools: return [L("tools")]
            case .settings: return [L("settings")]
            case .article(let id): return [Feature.get(id).isFix ? L("fixes") : L("tools"), Feature.get(id).slug + ".md"]
            }
        }()
        HStack(spacing: 6) {
            crumb("mgf") { model.category = nil; model.screen = .fixes }
            ForEach(Array(path.enumerated()), id: \.offset) { index, part in
                Text(verbatim: "/").foregroundStyle(Hax.textDisabled)
                if index < path.count - 1 {
                    crumb(part) { if model.screen == .fixes { model.category = nil } else { model.screen = model.page } }
                } else {
                    Text(verbatim: part).foregroundStyle(Hax.textPrimary).lineLimit(1)
                }
            }
            Spacer(minLength: 16)
            let applied = model.appliedFixes.count
            HxBadge(text: L("%d/%d fixes applied", applied, FeatureID.fixes.count), tone: applied > 0 ? .success : .neutral, dot: true, pulse: applied > 0)
            HxButton(variant: .ghost, icon: "settings", help: L("settings")) { model.screen = .settings }
            HxButton(title: L("star on github"), variant: .primary, small: true, icon: "star", iconRight: "arrow-up-right") { NSWorkspace.shared.open(repoURL) }
        }
        .font(Hax.bodySmall).foregroundStyle(Hax.textMuted)
        .padding(.leading, 24).padding(.trailing, 16)
    }

    private func crumb(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(verbatim: text) }.buttonStyle(.plain)
    }
}

private struct StatusLine: View {
    @Environment(AppModel.self) private var model
    @Environment(\.controlActiveState) private var window
    private let facts = [
        L("stall 264 ms → 10 ms · registry save deferral"), L("late packets 25 % → 1.2 % · low-latency wi-fi"),
        L("silence inserted 6.3 % → 0.1 % · audio buffer fix"), L("mic audio lost 6.9 % → 0.2 % · audio buffer fix"),
    ]

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: L("measured on m3 max") + " ❯").foregroundStyle(Hax.accent)
            // one fact at a time, swapped in a single step every 4 s; a background window keeps the first one
            if window == .inactive || !model.live {
                fact(0)
            } else {
                TimelineView(.periodic(from: .now, by: 4)) { context in fact(Int(context.date.timeIntervalSinceReferenceDate / 4) % facts.count) }
            }
            Spacer(minLength: 12)
            Text(verbatim: environment).lineLimit(1)
        }
        .font(Hax.caption).foregroundStyle(Hax.textMuted)
        .padding(.leading, 24).padding(.trailing, 16).frame(maxHeight: .infinity).background(Hax.bgPanel)
    }

    private func fact(_ index: Int) -> some View {
        Text(verbatim: facts[index]).foregroundStyle(Hax.textSecondary).lineLimit(1)
    }

    private var environment: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "macos \(os.majorVersion).\(os.minorVersion)" + (model.crossover.flatMap(\.version).map { " · crossover \($0)" } ?? "")
    }
}

/// Lists every file that is about to change before anything is written.
private struct ConfirmDialog: View {
    @Environment(AppModel.self) private var model
    let kind: AppModel.Confirm

    var body: some View {
        let applying = kind == .apply
        let ids = applying ? model.missingFixes : model.appliedFixes
        HxDialog(title: applying ? L("apply recommended") : L("revert all"),
                 path: (model.crossover?.support.path as NSString?)?.abbreviatingWithTildeInPath ?? "", onClose: { model.confirm = nil }) {
            Text(verbatim: applying ? L("these files inside crossover will change. originals are kept next to them.")
                                    : L("these files go back to their originals. wrappers and copies are removed."))
            VStack(spacing: 0) {
                let changes = model.changes(for: ids)
                ForEach(Array(changes.enumerated()), id: \.element) { index, change in
                    if index > 0 { Rectangle().fill(Hax.borderSubtle).frame(height: 1) }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        HxBadge(text: applying ? change.tag : change.tag == "NEW" ? "DEL" : "ORIG", tone: applying ? (change.tag == "NEW" ? .info : .accent) : .warning, bracket: true)
                            .frame(width: 60, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: change.path).foregroundStyle(Hax.textPrimary)
                            HxHint(applying ? change.note : change.tag == "NEW" ? L("removed") : L("original restored"))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
            .surface(Hax.bgPanel, border: Hax.borderSubtle, radius: Hax.radiusMD)
            HxHint(L("running games keep the old files until steam restarts"))
        } actions: {
            HxButton(title: L("cancel"), variant: .ghost) { model.confirm = nil }
            if applying {
                HxButton(title: L("apply %d", ids.count), variant: .primary, prompt: true) { model.confirm = nil; model.setFixes(ids, on: true) }
            } else {
                HxButton(title: L("revert %d", ids.count), variant: .danger) { model.confirm = nil; model.setFixes(ids, on: false) }
            }
        }
    }
}

/// Shown when macOS refuses a write into CrossOver: App Management has to be allowed by hand, once.
private struct PermissionDialog: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "MacGamingFixes"
        HxDialog(title: L("macos blocked the change"), onClose: { model.permissionNeeded = false }) {
            Text(verbatim: L("macos does not let one app change another until you allow it. nothing inside crossover was changed."))
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: L("1. open system settings → privacy & security → app management"))
                Text(verbatim: L("2. turn on %@ in the list", name))
                Text(verbatim: L("3. reopen mgf and flip the switch again"))
            }
            .foregroundStyle(Hax.textPrimary).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .surface(Hax.bgPanel, border: Hax.borderSubtle, radius: Hax.radiusMD)
        } actions: {
            HxButton(title: L("close"), variant: .ghost) { model.permissionNeeded = false }
            HxButton(title: L("open system settings"), variant: .primary, iconRight: "arrow-up-right") { model.openAppManagement() }
        }
    }
}
