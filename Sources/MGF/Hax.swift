// The Hax design system in SwiftUI: tokens first, then the components the app uses.
// Source of truth: claude.ai/design project f3ee618a-0226-4df0-8b8d-60f88c837139 (tokens/*.css, components/components.css).
import AppKit
import SwiftUI

/// Where strings and articles come from: macOS's choice of language, or the one picked in settings → app.
var languageBundle = bundle(forLanguage: Settings.load().language)
func bundle(forLanguage code: String?) -> Bundle {
    code.flatMap { Bundle.module.path(forResource: $0, ofType: "lproj") }.flatMap(Bundle.init(path:)) ?? .module
}
func L(_ key: String) -> String { languageBundle.localizedString(forKey: key, value: nil, table: nil) }
func L(_ key: String, _ arguments: CVarArg...) -> String { String(format: L(key), arguments: arguments) }

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

enum Hax {
    // ink: surfaces, darkest to lightest
    static let bgPage = Color(hex: 0x070b09), bgPanel = Color(hex: 0x0b110d), bgCard = Color(hex: 0x101813)
    static let bgRaised = Color(hex: 0x172119), bgActive = Color(hex: 0x1f2c23)
    static let borderSubtle = Color(hex: 0x1a251d), borderDefault = Color(hex: 0x28382d), borderStrong = Color(hex: 0x3a4d40)
    static let textPrimary = Color(hex: 0xe6efe8), textSecondary = Color(hex: 0xa9b8ad), textMuted = Color(hex: 0x7a8b7e), textDisabled = Color(hex: 0x46554b)
    // one accent, traffic-light semantics
    static let accent = Color(hex: 0x39ff6e), accentHover = Color(hex: 0x8dffad), accentPress = Color(hex: 0x22d35a)
    static let accentSoft = accent.opacity(0.12), borderAccent = accent.opacity(0.35), onAccent = Color(hex: 0x07110a)
    static let success = Color(hex: 0x22d35a), warning = Color(hex: 0xffbd2e), danger = Color(hex: 0xff5f56), info = Color(hex: 0x5ad7ff)
    static let scrim = bgPage.opacity(0.72)

    static let radiusXS: CGFloat = 2, radiusSM: CGFloat = 4, radiusMD: CGFloat = 6, radiusLG: CGFloat = 10
    /// topbar is the height of the system title bar with a unified toolbar, so the window buttons sit on its centre line
    static let sidebar: CGFloat = 240, topbar: CGFloat = 52

    // motion: one ease-out curve, 120 / 200 / 400 ms
    static let fast = 0.12, base = 0.2, slow = 0.4
    static func ease(_ duration: Double) -> Animation { .timingCurve(0.2, 0.8, 0.2, 1, duration: duration) }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom("Red Hat Mono", size: size).weight(weight) }
    static let body = mono(14), bodySmall = mono(13), caption = mono(12), overline = mono(11, .medium)

    static func registerFonts() {
        guard let url = Bundle.module.url(forResource: "RedHatMono", withExtension: "ttf", subdirectory: "Fonts") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

/// The MGF wordmark and app icon (assets/brand-src has the sources).
enum Brand {
    private static func image(_ file: String) -> NSImage {
        Bundle.module.url(forResource: file, withExtension: nil, subdirectory: "Brand").flatMap(NSImage.init(contentsOf:)) ?? NSImage()
    }

    static let wordmark = image("wordmark@4x.png")
    static let icon = image("MGF.icns")
}

enum Tone {
    case neutral, accent, success, warning, danger, info
    var color: Color {
        switch self {
        case .neutral: return Hax.textSecondary
        case .accent: return Hax.accent
        case .success: return Hax.success
        case .warning: return Hax.warning
        case .danger: return Hax.danger
        case .info: return Hax.info
        }
    }
}

extension View {
    /// Fill, 1px border and radius in one go: nearly every Hax surface is this.
    func surface(_ fill: Color, border: Color, radius: CGFloat = Hax.radiusSM) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(border, lineWidth: 1))
    }
}

// MARK: icon

/// Lucide stroke icons, loaded from the bundled SVGs at the design system's 1.75 stroke.
struct HxIcon: View {
    let name: String
    var size: CGFloat = 16
    private static var cache: [String: NSImage] = [:]

    init(_ name: String, size: CGFloat = 16) { self.name = name; self.size = size }

    static func image(_ name: String) -> NSImage {
        if let hit = cache[name] { return hit }
        var image = NSImage(size: NSSize(width: 24, height: 24))
        if let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "Icons"),
           let svg = try? String(contentsOf: url, encoding: .utf8),
           let loaded = NSImage(data: Data(svg.replacingOccurrences(of: "stroke-width=\"2\"", with: "stroke-width=\"1.75\"").utf8)) {
            image = loaded
        }
        image.isTemplate = true
        cache[name] = image
        return image
    }

    var body: some View {
        Image(nsImage: Self.image(name)).resizable().renderingMode(.template).frame(width: size, height: size).accessibilityHidden(true)
    }
}

// MARK: button

struct HxButton: View {
    enum Variant { case primary, secondary, ghost, danger }
    var title: String?
    var variant: Variant = .secondary
    var small = false
    var icon: String?
    var iconRight: String?
    var prompt = false
    var loading = false
    var help: String?
    let action: () -> Void

    @State private var hovering = false
    @State private var spin = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let height: CGFloat = small ? 28 : 36, iconSize: CGFloat = small ? 14 : 16
        Button(action: action) {
            HStack(spacing: small ? 6 : 8) {
                if prompt { Text(verbatim: "❯").fontWeight(.semibold).foregroundStyle(variant == .primary ? Hax.onAccent : Hax.accent) }
                if loading {
                    HxIcon("loader", size: iconSize).rotationEffect(.degrees(spin ? 360 : 0))
                        .onAppear { withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { spin = true } }
                } else if let icon { HxIcon(icon, size: iconSize) }
                if let title { Text(verbatim: title).lineLimit(1).fixedSize() }
                if let iconRight { HxIcon(iconRight, size: iconSize) }
            }
            .font(Hax.mono(small ? 12 : 13, .medium))
            .padding(.horizontal, title == nil ? 0 : (small ? 8 : 12))
            .frame(width: title == nil ? height : nil, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(HxButtonStyle(variant: variant, hovering: hovering && enabled))
        .onHover { hovering = $0 }
        .opacity(enabled ? 1 : 0.45)
        .help(help ?? "")
        .accessibilityLabel(title ?? help ?? "")
    }
}

private struct HxButtonStyle: ButtonStyle {
    let variant: HxButton.Variant
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let fill: Color, border: Color, text: Color
        switch variant {
        case .primary:
            fill = pressed ? Hax.accentPress : hovering ? Hax.accentHover : Hax.accent; border = fill; text = Hax.onAccent
        case .secondary:
            fill = pressed ? Hax.bgActive : hovering ? Hax.bgRaised : Hax.bgCard; border = hovering ? Hax.borderStrong : Hax.borderDefault; text = Hax.textPrimary
        case .ghost:
            fill = pressed ? Hax.bgActive : hovering ? Hax.bgRaised : .clear; border = .clear; text = hovering ? Hax.textPrimary : Hax.textSecondary
        case .danger:
            fill = hovering ? Hax.danger.opacity(0.14) : .clear; border = Hax.danger; text = Hax.danger
        }
        return configuration.label
            .foregroundStyle(text)
            .surface(fill, border: border)
            .shadow(color: variant == .primary && hovering && !pressed ? Hax.accent.opacity(0.28) : .clear, radius: 9)  // glow instead of shadow
            .animation(Hax.ease(Hax.fast), value: hovering)
    }
}

// MARK: small pieces

struct HxKbd: View {
    let text: String
    var body: some View {
        Text(verbatim: text).font(Hax.mono(11, .medium)).foregroundStyle(Hax.textSecondary)
            .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20)
            .surface(Hax.bgRaised, border: Hax.borderStrong, radius: Hax.radiusXS)
    }
}

struct HxLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(verbatim: text.uppercased()).font(Hax.mono(12, .medium)).tracking(1).foregroundStyle(Hax.textSecondary)
    }
}

/// Helper text, written as a code comment.
struct HxHint: View {
    let text: String
    var tone: Tone = .neutral
    init(_ text: String, tone: Tone = .neutral) { self.text = text; self.tone = tone }
    var body: some View {
        (Text(verbatim: "// ").foregroundStyle(tone == .danger ? Hax.danger : Hax.textMuted)
            + Text(verbatim: text).foregroundStyle(tone == .neutral ? Hax.textMuted : tone.color))
            .font(Hax.caption).fixedSize(horizontal: false, vertical: true)
    }
}

struct HxBadge: View {
    let text: String
    var tone: Tone = .neutral
    var bracket = false
    var dot = false
    var pulse = false

    var body: some View {
        if bracket {
            // status brackets: [ OK ], [WARN], [FAIL]
            (Text(verbatim: "[ ").foregroundStyle(tone.color.opacity(0.55)) + Text(verbatim: text.uppercased()).foregroundStyle(tone.color)
                + Text(verbatim: " ]").foregroundStyle(tone.color.opacity(0.55)))
                .font(Hax.overline).tracking(0.9).fixedSize()
        } else {
            HStack(spacing: 6) {
                if dot || pulse {
                    Circle().fill(tone.color).frame(width: 6, height: 6).modifier(Pulse(active: pulse))
                }
                Text(verbatim: text.uppercased()).font(Hax.overline).tracking(0.9).fixedSize()
            }
            .foregroundStyle(tone.color)
            .padding(.horizontal, 8).frame(height: 20)
            .surface(tone == .neutral ? Hax.bgRaised : tone.color.opacity(0.13), border: tone == .neutral ? Hax.borderDefault : tone.color.opacity(0.35), radius: Hax.radiusXS)
        }
    }
}

struct HxTag: View {
    let text: String
    var onRemove: (() -> Void)?
    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: text).font(Hax.caption).foregroundStyle(Hax.textSecondary)
            if let onRemove {
                Button(action: onRemove) { HxIcon("x", size: 12).foregroundStyle(Hax.textMuted) }
                    .buttonStyle(.plain).accessibilityLabel(L("remove %@", text))
            }
        }
        .padding(.horizontal, 8).frame(height: 24)
        .surface(Hax.bgCard, border: Hax.borderDefault, radius: Hax.radiusXS)
    }
}

/// Three window dots. Decorative: the real window controls are the system's.
struct HxLights: View {
    var body: some View {
        HStack(spacing: 6) {
            ForEach([Hax.danger, Hax.warning, Hax.success], id: \.self) { Circle().fill($0).frame(width: 10, height: 10) }
        }.accessibilityHidden(true)
    }
}

/// Live dots pulse in steps on a 1.6 s period. A repeating SwiftUI animation would redraw the whole
/// window on every display frame for as long as the app runs; a timeline ticks 1.25 times a second.
struct Pulse: ViewModifier {
    let active: Bool
    @Environment(\.controlActiveState) private var window
    func body(content: Content) -> some View {
        if active, window != .inactive {  // a window in the background stays still
            TimelineView(.periodic(from: .now, by: 0.8)) { context in
                content.opacity(Int(context.date.timeIntervalSinceReferenceDate / 0.8) % 2 == 0 ? 1 : 0.35)
            }
        } else {
            content
        }
    }
}

/// The blinking block cursor: steps, never fades.
struct HxCursor: View {
    @Environment(\.controlActiveState) private var window
    var body: some View {
        Group {
            if window == .inactive {
                Text(verbatim: "█").foregroundStyle(Hax.accent)
            } else {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    Text(verbatim: "█").foregroundStyle(Hax.accent)
                        .opacity(Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0 ? 1 : 0)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: form controls

struct HxSwitch: View {
    @Binding var isOn: Bool
    var label: String?
    var showState = false
    var accessibilityName = ""
    @State private var hovering = false

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Hax.radiusSM).fill(isOn ? Hax.accentSoft : Hax.bgPanel)
                    RoundedRectangle(cornerRadius: Hax.radiusSM).strokeBorder(isOn || hovering ? Hax.accent : Hax.borderStrong, lineWidth: 1)
                    RoundedRectangle(cornerRadius: Hax.radiusXS).fill(isOn ? Hax.accent : Hax.textMuted).frame(width: 12, height: 12)
                        .shadow(color: isOn ? Hax.accent.opacity(0.5) : .clear, radius: 4)
                        .offset(x: isOn ? 19 : 3)
                }
                .frame(width: 34, height: 18)
                if showState {
                    Text(verbatim: isOn ? "ON" : "OFF").font(Hax.overline).tracking(0.9).foregroundStyle(isOn ? Hax.accent : Hax.textMuted).frame(width: 24, alignment: .leading)
                }
                if let label { Text(verbatim: label).font(Hax.bodySmall).foregroundStyle(Hax.textPrimary) }
            }
            .contentShape(Rectangle())
            .animation(Hax.ease(Hax.fast), value: isOn)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityRepresentation { Toggle(label ?? accessibilityName, isOn: $isOn) }
    }
}

/// `[x] label` with an optional second line.
struct HxCheckbox: View {
    @Binding var isOn: Bool
    let label: String
    var detail: String?

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: isOn ? "[x]" : "[ ]").font(Hax.mono(13, .medium)).foregroundStyle(Hax.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: label).font(Hax.bodySmall).foregroundStyle(Hax.textPrimary)
                    if let detail { Text(verbatim: detail).font(Hax.caption).foregroundStyle(Hax.textMuted).fixedSize(horizontal: false, vertical: true) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(label, isOn: $isOn) }
    }
}

/// The field chrome shared by inputs, selects and the slider.
private struct HxControl<Content: View>: View {
    var focused = false
    var error = false
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) { content }
            .font(Hax.bodySmall).foregroundStyle(Hax.textPrimary)
            .padding(.horizontal, 12).frame(height: 36)
            .surface(Hax.bgPanel, border: error ? Hax.danger : focused ? Hax.accent : hovering ? Hax.borderStrong : Hax.borderDefault)
            .overlay(RoundedRectangle(cornerRadius: Hax.radiusSM + 3).strokeBorder(focused ? (error ? Hax.danger.opacity(0.14) : Hax.accentSoft) : .clear, lineWidth: 3).padding(-3))
            .onHover { hovering = $0 }
            .animation(Hax.ease(Hax.fast), value: hovering)
            .animation(Hax.ease(Hax.fast), value: focused)
    }
}

struct HxInput: View {
    var label: String?
    @Binding var text: String
    var prompt = false
    var suffix: String?
    var optional = false
    var hint: String?
    var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    HxLabel(label)
                    if optional { Text(verbatim: "// " + L("optional")).font(Hax.caption).foregroundStyle(Hax.textMuted) }
                }
            }
            HxControl(focused: focused, error: error != nil) {
                if prompt { Text(verbatim: "❯").fontWeight(.semibold).foregroundStyle(Hax.accent) }
                TextField("", text: $text).textFieldStyle(.plain).focused($focused).autocorrectionDisabled()
                    .accessibilityLabel(label ?? "")
                if let suffix { Text(verbatim: suffix).foregroundStyle(Hax.textMuted) }
            }
            if let error { HxHint(error, tone: .danger) } else if let hint { HxHint(hint) }
        }
    }
}

struct HxSelect: View {
    struct Option: Identifiable { let id: String; let label: String }
    var label: String?
    let options: [Option]
    var selection: String?
    var placeholder = ""
    var hint: String?
    var hintTone: Tone = .neutral
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label { HxLabel(label) }
            Menu {
                ForEach(options) { option in
                    Button { onPick(option.id) } label: {
                        if option.id == selection { Label(option.label, systemImage: "checkmark") } else { Text(verbatim: option.label) }
                    }
                }
            } label: {
                HxControl {
                    Text(verbatim: options.first { $0.id == selection }?.label ?? placeholder).lineLimit(1)
                        .foregroundStyle(selection == nil ? Hax.textMuted : Hax.textPrimary)
                    Spacer(minLength: 8)
                    HxIcon("chevron-down", size: 14).foregroundStyle(Hax.textMuted)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .disabled(options.isEmpty)
            .accessibilityLabel(label ?? placeholder)
            if let hint { HxHint(hint, tone: hintTone) }
        }
    }
}

/// Not in the Hax set: a segmented level control in the same idiom (square cells, accent fill).
struct HxSlider: View {
    let label: String
    @Binding var value: Double  // 0...1
    private let segments = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HxLabel(label)
            HxControl {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(0..<segments, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1).fill(i < Int((value * Double(segments)).rounded()) ? Hax.accent : Hax.borderDefault)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { drag in value = min(max(drag.location.x / geo.size.width, 0), 1) })
                }
                .frame(height: 12)
                Text(verbatim: "\(Int((value * 100).rounded()))%").font(Hax.mono(13, .medium)).frame(width: 40, alignment: .trailing)
            }
            .accessibilityRepresentation { Slider(value: $value, in: 0...1) { Text(verbatim: label) } }
        }
    }
}

// MARK: containers

struct HxTabs: View {
    let items: [(id: String, label: String)]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let selected = item.id == selection
                Button { selection = item.id } label: {
                    HStack(spacing: 8) {
                        Text(verbatim: "\(index + 1):").font(Hax.mono(11, .medium)).foregroundStyle(selected ? Hax.accent : Hax.textMuted)
                        Text(verbatim: item.label).font(Hax.mono(13, .medium)).foregroundStyle(selected ? Hax.textPrimary : Hax.textMuted)
                    }
                    .padding(.horizontal, 16).frame(height: 30)
                    .background(selected ? Hax.bgCard : .clear)
                    .overlay(alignment: .top) { if selected { TabEdge().stroke(Hax.borderDefault, lineWidth: 1) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .background(alignment: .bottom) { Rectangle().fill(Hax.borderDefault).frame(height: 1) }
    }

    /// Left, top and right edges of the selected tab; the bottom stays open onto the pane.
    private struct TabEdge: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + 0.5, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + 0.5, y: rect.minY + 0.5))
            path.addLine(to: CGPoint(x: rect.maxX - 0.5, y: rect.minY + 0.5))
            path.addLine(to: CGPoint(x: rect.maxX - 0.5, y: rect.maxY))
            return path
        }
    }
}

struct TermLine: Identifiable, Equatable {
    enum Kind { case command, output, comment, ok, warn, error }
    let id = UUID()
    let kind: Kind
    let text: String
    var color: Color {
        switch kind {
        case .command: return Hax.textPrimary
        case .output: return Hax.textSecondary
        case .comment: return Hax.textMuted
        case .ok: return Hax.success
        case .warn: return Hax.warning
        case .error: return Hax.danger
        }
    }
}

struct HxTerminal: View {
    let title: String
    let lines: [TermLine]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack { HxLights(); Spacer() }
                Text(verbatim: title).font(Hax.caption).foregroundStyle(Hax.textMuted)
            }
            .padding(.horizontal, 12).frame(height: 34).background(Hax.bgCard)
            Rectangle().fill(Hax.borderSubtle).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                if line.kind == .command { Text(verbatim: "❯").fontWeight(.semibold).foregroundStyle(Hax.accent) }
                                Text(verbatim: line.text).foregroundStyle(line.color).lineLimit(1)
                            }
                            .frame(height: 22)
                        }
                        HStack(spacing: 8) { Text(verbatim: "❯").fontWeight(.semibold).foregroundStyle(Hax.accent); HxCursor() }
                            .frame(height: 22).id("cursor")
                    }
                    .font(Hax.bodySmall)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
                .onChange(of: lines.count) { withAnimation(Hax.ease(Hax.base)) { proxy.scrollTo("cursor", anchor: .bottom) } }
                .onAppear { proxy.scrollTo("cursor", anchor: .bottom) }
            }
            .overlay { Scanlines().allowsHitTesting(false) }
        }
        .surface(Hax.bgPanel, border: Hax.borderDefault, radius: Hax.radiusMD)
        .clipShape(RoundedRectangle(cornerRadius: Hax.radiusMD))
    }

    /// 3.5% white lines every 3 px: the one texture terminal panes carry.
    private struct Scanlines: View {
        var body: some View {
            Canvas { context, size in
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.white.opacity(0.035)))
                    y += 3
                }
            }
        }
    }
}

/// A single copyable shell command.
struct HxCommandLine: View {
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: "$").fontWeight(.semibold).foregroundStyle(Hax.accent)
            Text(verbatim: command).foregroundStyle(Hax.textPrimary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Spacer(minLength: 8)
            if copied { Text(verbatim: L("copied").uppercased()).font(Hax.overline).tracking(0.9).foregroundStyle(Hax.accent) }
            HxButton(variant: .ghost, small: true, icon: copied ? "check" : "copy", help: L("copy command")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
            }
        }
        .font(Hax.bodySmall)
        .padding(.leading, 16).padding(.trailing, 8).frame(height: 44)
        .surface(Hax.bgPanel, border: copied ? Hax.borderAccent : Hax.borderDefault)
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let tone: Tone
    let title: String
    let message: String
}

struct HxToast: View {
    let toast: Toast
    let onDismiss: () -> Void

    var body: some View {
        let status = [Tone.warning: "[WARN]", .danger: "[FAIL]", .info: "[INFO]"][toast.tone] ?? "[ OK ]"
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: status).font(Hax.mono(11, .semibold)).tracking(0.9).foregroundStyle(toast.tone.color).frame(height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: toast.title).font(Hax.mono(13, .medium)).foregroundStyle(Hax.textPrimary)
                if !toast.message.isEmpty { Text(verbatim: toast.message).font(Hax.bodySmall).foregroundStyle(Hax.textSecondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) { HxIcon("x", size: 14).foregroundStyle(Hax.textMuted) }.buttonStyle(.plain).accessibilityLabel(L("dismiss"))
        }
        .padding(12).frame(width: 380)
        .surface(Hax.bgRaised, border: Hax.borderDefault, radius: Hax.radiusMD)
        .shadow(color: .black.opacity(0.45), radius: 12, y: 8)
    }
}

/// Terminal-window modal: title bar with lights and a path, body, action row.
struct HxDialog<Content: View, Actions: View>: View {
    let title: String
    var path = ""
    var width: CGFloat = 560
    let onClose: () -> Void
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        ZStack {
            Hax.scrim.ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    HxLights()
                    Text(verbatim: title).font(Hax.mono(13, .medium)).foregroundStyle(Hax.textPrimary).fixedSize()
                    Text(verbatim: path).font(Hax.caption).foregroundStyle(Hax.textMuted).lineLimit(1).truncationMode(.head)
                    Spacer(minLength: 0)
                    HxButton(variant: .ghost, small: true, icon: "x", help: L("close"), action: onClose).keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 16).padding(.vertical, 12).background(Hax.bgPanel)
                Rectangle().fill(Hax.borderSubtle).frame(height: 1)
                VStack(alignment: .leading, spacing: 12) { content }
                    .font(Hax.bodySmall).foregroundStyle(Hax.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                Rectangle().fill(Hax.borderSubtle).frame(height: 1)
                HStack(spacing: 8) { Spacer(); actions }.padding(.horizontal, 16).padding(.vertical, 12)
            }
            .frame(width: width)
            .surface(Hax.bgCard, border: Hax.borderDefault, radius: Hax.radiusLG)
            .clipShape(RoundedRectangle(cornerRadius: Hax.radiusLG))
            .shadow(color: .black.opacity(0.6), radius: 32, y: 24)
            .accessibilityAddTraits(.isModal)
        }
    }
}
