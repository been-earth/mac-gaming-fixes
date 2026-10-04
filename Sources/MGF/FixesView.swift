// The fixes and tools pages: feature cards in a grid whose rows are always full.
import AppKit
import CoreAudio
import MGFCore
import SwiftUI

struct FixesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Overview(headline: L("windows games on a mac. no *net jitter*, no *broken sound*."),
                         hint: L("patches crossover's wine in place. every change is listed before it is made, and every original file is kept.")) {
                    let missing = model.missingFixes.count
                    HxButton(title: missing > 0 ? L("apply recommended") : L("all fixes applied"), variant: .primary, icon: missing > 0 ? nil : "check", prompt: missing > 0) { model.confirm = .apply }
                        .disabled(missing == 0 || model.crossover == nil || model.busy)
                    HxButton(title: L("revert all"), icon: "rotate-ccw") { model.confirm = .revert }
                        .disabled(model.appliedFixes.isEmpty || model.busy)
                }
                CardGrid(features: model.shownFixes, revealFrom: 3)
            }
            .padding(24)
        }
    }
}

struct ToolsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Overview(headline: L("*f1–f12* without fn. *audio devices* in one place."),
                         hint: L("tools change macos settings, not crossover, and take effect at once.")) {}
                CardGrid(features: model.tools, revealFrom: 3)
            }
            .padding(24)
        }
    }
}

/// Feature cards in rows that are always full: fixes three to a row, tools two, leftovers stretch.
private struct CardGrid: View {
    let features: [Feature]
    let revealFrom: Int

    var body: some View {
        VStack(spacing: 16) {
            ForEach(Array(gridRows(features.map(\.isFix)).enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: 16) {
                    ForEach(features[row]) { feature in
                        card(feature, wide: row.count < 3).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .reveal(revealFrom + index)
            }
        }
    }

    @ViewBuilder private func card(_ feature: Feature, wide: Bool) -> some View {
        switch feature.id {
        case .fkeys: FkeysCard(feature: feature, wide: wide)
        case .audioDevices: AudioCard(feature: feature, wide: wide)
        default: FixCard(feature: feature, wide: wide)
        }
    }
}

/// The top of a page: headline, a line of context, the page's actions if it has any, and the activity log.
private struct Overview<Actions: View>: View {
    @Environment(AppModel.self) private var model
    let headline: String    // the parts between asterisks are set in the accent colour and never break across lines
    let hint: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 32) {
            VStack(alignment: .leading, spacing: 16) {
                title.reveal(0)
                HxHint(hint).font(Hax.bodySmall).reveal(1)
                if Actions.self != EmptyView.self { HStack(spacing: 8) { actions }.reveal(2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HxTerminal(title: "mgf — " + L("activity"), lines: model.log).frame(width: 414, height: 204).reveal(1)
        }
    }

    private var title: some View {
        let parts = headline.components(separatedBy: "*")
        return parts.enumerated().reduce(Text(verbatim: "")) { text, part in
            let marked = part.offset % 2 == 1
            return text + Text(verbatim: marked ? part.element.replacingOccurrences(of: " ", with: "\u{00A0}") : part.element)
                .foregroundStyle(marked ? Hax.accent : Hax.textPrimary)
        }
        .font(Hax.mono(28, .medium)).tracking(-0.4).lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true).accessibilityLabel(parts.joined())
    }
}

// MARK: card frame

/// Icon, name, use case, description, a state line and the details button that shows on hover.
private struct FeatureCard<Content: View, Status: View>: View {
    @Environment(AppModel.self) private var model
    let feature: Feature
    let wide: Bool
    let isOn: Bool
    var toggle: ((Bool) -> Void)?
    @ViewBuilder var content: Content
    @ViewBuilder var status: Status
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                IconBox(icon: feature.icon, on: isOn, lifted: hovering)
                Text(verbatim: feature.title).font(Hax.mono(13, .medium)).foregroundStyle(Hax.textPrimary).lineLimit(1)
                Spacer(minLength: 4)
                if wide { Text(verbatim: "// " + feature.category.title).font(Hax.caption).foregroundStyle(Hax.textMuted) }
                if let toggle { HxSwitch(isOn: Binding(get: { isOn }, set: toggle), accessibilityName: feature.title).disabled(model.busy) }
            }
            .padding(.horizontal, 16).frame(height: 52)
            Rectangle().fill(Hax.borderSubtle).frame(height: 1)
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: feature.useCase).font(Hax.bodySmall).foregroundStyle(Hax.textPrimary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: feature.description).font(Hax.bodySmall).foregroundStyle(Hax.textMuted).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
                content
            }
            .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Rectangle().fill(Hax.borderSubtle).frame(height: 1)
            HStack(spacing: 8) {
                HStack(spacing: 8) { status }.font(Hax.caption).foregroundStyle(Hax.textMuted).lineLimit(1)
                Spacer(minLength: 8)
                HxButton(title: L("details"), variant: .ghost, small: true, iconRight: "arrow-right") { model.screen = .article(feature.id) }
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 16).frame(height: 44)
        }
        .surface(Hax.bgCard, border: hovering ? Hax.borderStrong : Hax.borderSubtle, radius: Hax.radiusMD)
        .onHover { hovering = $0 }
        .animation(Hax.ease(Hax.fast), value: hovering)
    }
}

struct IconBox: View {
    let icon: String
    var on = false
    var lifted = false
    var body: some View {
        HxIcon(icon, size: 14).foregroundStyle(on ? Hax.accent : Hax.textSecondary).frame(width: 24, height: 24)
            .surface(lifted ? Hax.bgActive : Hax.bgPanel, border: on ? Hax.borderAccent : Hax.borderDefault)
    }
}

/// Before/after evidence drawn with block glyphs; the cells count up in steps when the card appears.
struct MeasureBars: View {
    let measure: Feature.Measure
    var large = false
    private let cells = 16
    @State private var filled = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: measure.label.uppercased()).font(Hax.overline).tracking(0.9).foregroundStyle(Hax.textMuted)
            row(L("before"), cells, measure.before, Hax.warning)
            row(L("after"), max(1, Int((measure.after / measure.before * Double(cells)).rounded())), measure.after, Hax.accent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(measure.label): \(L("before")) \(format(measure.before)) \(measure.unit), \(L("after")) \(format(measure.after)) \(measure.unit)")
        .task {
            if reduceMotion { filled = cells; return }
            for step in 1...cells {
                try? await Task.sleep(for: .milliseconds(25))
                filled = step
            }
        }
    }

    private func format(_ value: Double) -> String { value == value.rounded() ? String(Int(value)) : String(value) }

    private func row(_ name: String, _ count: Int, _ value: Double, _ color: Color) -> some View {
        let on = min(count, filled)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: name).foregroundStyle(Hax.textMuted).frame(width: 46, alignment: .leading)
            (Text(verbatim: String(repeating: "█", count: on)).foregroundStyle(color)
                + Text(verbatim: String(repeating: "░", count: cells - on)).foregroundStyle(Hax.textDisabled)).tracking(-0.5)
            Text(verbatim: "\(format(value)) \(measure.unit)").fontWeight(.medium).foregroundStyle(Hax.textPrimary)
        }
        .font(Hax.mono(large ? 13 : 12)).lineLimit(1).fixedSize()
    }
}

// MARK: the three kinds of card

private struct FixCard: View {
    @Environment(AppModel.self) private var model
    let feature: Feature
    let wide: Bool

    var body: some View {
        let on = model.isApplied(feature.id), pending = model.pending.contains(feature.id)
        FeatureCard(feature: feature, wide: wide, isOn: on, toggle: { model.setFixes([feature.id], on: $0) }) {
            if let measure = feature.measure {
                Spacer(minLength: 0)
                Rectangle().fill(Hax.borderSubtle).frame(height: 1)
                MeasureBars(measure: measure)
            }
        } status: {
            if pending {
                HxBadge(text: "WARN", tone: .warning, bracket: true)
                Text(verbatim: L("restart %@", model.restartTarget)).help(on ? L("applied. loads when the bottle restarts") : L("removed. gone when the bottle restarts"))
            } else if on {
                HxBadge(text: "OK", tone: .success, bracket: true)
                Text(verbatim: L("applied"))
            } else {
                HxBadge(text: "OFF", bracket: true)
                Text(verbatim: L("not applied"))
            }
        }
    }
}

private struct FkeysCard: View {
    @Environment(AppModel.self) private var model
    let feature: Feature
    let wide: Bool
    // the top row as it behaves with the switch off, by key position
    private let media = ["sun-dim", "sun", "layout-grid", "search", "mic", "moon", "rewind", "play", "fast-forward", "volume-x", "volume-1", "volume-2"]

    var body: some View {
        let on = model.fkeysOn
        let triggers = model.settings.fkeysTriggers
        let byApps = model.settings.fkeysApps ?? true, gameMode = model.settings.fkeysGameMode
        let auto = (byApps ? triggers : []) + (gameMode ? [L("game mode")] : [])
        FeatureCard(feature: feature, wide: wide, isOn: on, toggle: { model.setFkeys($0) }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(Array(media.enumerated()), id: \.offset) { index, glyph in
                        Group {
                            if on { Text(verbatim: "F\(index + 1)").font(Hax.mono(11, .medium)) } else { HxIcon(glyph, size: 13) }
                        }
                        .foregroundStyle(on ? Hax.accent : Hax.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .surface(on ? Hax.accentSoft : Hax.bgRaised, border: on ? Hax.borderAccent : Hax.borderStrong, radius: Hax.radiusXS)
                        .animation(Hax.ease(Hax.fast).delay(Double(index) * 0.02), value: on)  // the row flips key by key
                    }
                }
                .accessibilityHidden(true)
                HxHint(on ? L("top row sends f1–f12. brightness and volume need fn") : L("top row controls brightness, mission control and media"))
            }
            VStack(alignment: .leading, spacing: 12) {
                HxLabel(L("turn on automatically"))
                HxCheckbox(isOn: Binding(get: { byApps }, set: { model.setTriggers(triggers, apps: $0, gameMode: gameMode) }),
                           label: L("when one of these apps is running"))
                // the list stays when the box is cleared: it is just not followed
                VStack(alignment: .leading, spacing: 8) {
                    let candidates = model.triggerCandidates
                    HxSelect(options: candidates.map { .init(id: $0.name, label: $0.name + " · " + ($0.isWine ? "wine" : L("app"))) },
                             placeholder: candidates.isEmpty ? L("no more running apps to add") : L("add a running app…")) { name in
                        model.setTriggers(triggers + [name], apps: byApps, gameMode: gameMode)
                    }
                    if triggers.isEmpty {
                        HxHint(L("no apps picked"))
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(triggers, id: \.self) { name in
                                HxTag(text: name) { model.setTriggers(triggers.filter { $0 != name }, apps: byApps, gameMode: gameMode) }
                            }
                        }
                    }
                }
                .padding(.leading, 31).disabled(!byApps).opacity(byApps ? 1 : 0.45)   // 31: under the checkbox label
                HxCheckbox(isOn: Binding(get: { gameMode }, set: { model.setTriggers(triggers, apps: byApps, gameMode: $0) }),
                           label: L("when macos game mode turns on"), detail: L("wine games do not always trigger it. add the game above to be sure"))
            }
        } status: {
            if on {
                HxBadge(text: "OK", tone: .success, bracket: true)
                Text(verbatim: L("on"))
            } else if !auto.isEmpty {
                HxBadge(text: "AUTO", tone: .info, bracket: true)
                Text(verbatim: L("turns on with %@", auto.joined(separator: ", ")))
            } else {
                HxBadge(text: "OFF", bracket: true)
                Text(verbatim: L("manual only"))
            }
        }
    }
}

private struct AudioCard: View {
    @Environment(AppModel.self) private var model
    let feature: Feature
    let wide: Bool

    var body: some View {
        let input = model.devices.first { $0.id == model.inputID }
        let output = model.devices.first { $0.id == model.outputID }
        let bluetoothMic = input?.transport == .bluetooth
        FeatureCard(feature: feature, wide: wide, isOn: true) {
            HxSelect(label: L("output"), options: options(model.devices.filter(\.hasOutput)), selection: model.outputID.map(String.init)) { pick($0, input: false) }
            HxSelect(label: L("microphone"), options: options(model.devices.filter(\.hasInput)), selection: model.inputID.map(String.init),
                     hint: bluetoothMic ? L("the headset drops to 16 khz mono while this mic is open") : nil, hintTone: .warning) { pick($0, input: true) }
            if let volume = model.inputVolume {
                HxSlider(label: L("input volume"), value: Binding(get: { volume }, set: { model.setInputVolume($0) }))
            } else {
                VStack(alignment: .leading, spacing: 8) { HxLabel(L("input volume")); HxHint(L("this microphone has no software volume")) }
            }
        } status: {
            if bluetoothMic {
                HxBadge(text: "WARN", tone: .warning, bracket: true)
                Text(verbatim: L("bluetooth mic selected"))
            } else {
                HxBadge(text: "OK", tone: .success, bracket: true)
                Text(verbatim: L("%@ out · %@ in", output?.name ?? "?", input?.name ?? "?"))
            }
        }
    }

    private func options(_ devices: [AudioDevice]) -> [HxSelect.Option] {
        devices.map { device in
            let khz = device.sampleRate / 1000
            let rate = L("%@ khz", khz == khz.rounded() ? String(Int(khz)) : String(format: "%.1f", khz))
            return .init(id: String(device.id), label: "\(device.name) · \(transport(device.transport)) · \(rate)")
        }
    }

    private func transport(_ transport: AudioDevice.Transport) -> String {
        switch transport {
        case .builtIn: return L("built-in")
        case .usb: return "usb"
        case .bluetooth: return "bluetooth"
        case .virtual: return L("virtual")
        case .other: return L("other")
        }
    }

    private func pick(_ id: String, input: Bool) {
        if let device = AudioDeviceID(id) { model.setDevice(device, input: input) }
    }
}

/// Lays children out left to right, wrapping to a new line when the row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat?   // nil: the same as spacing
    var centered = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = place(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, place(subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }

    private func place(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, rowStart = 0
        var frames: [CGRect] = []
        func centre(_ row: Range<Int>) {
            guard centered, width.isFinite, let last = frames[row].last else { return }
            for index in row { frames[index].origin.x += (width - last.maxX) / 2 }
        }
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                centre(rowStart..<index)
                rowStart = index; x = 0; y += rowHeight + (lineSpacing ?? spacing); rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        centre(rowStart..<frames.count)
        return frames
    }
}
