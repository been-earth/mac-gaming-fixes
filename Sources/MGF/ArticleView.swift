// The article reader: contents and reading progress on the left, the Markdown article on the right.
import AppKit
import MGFCore
import SwiftUI

/// Top edge of each section and of the whole article, in the scroll view's coordinate space.
private struct Offsets: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) { value.merge(nextValue()) { $1 } }
}
private let articleID = -1, endID = -2

struct ArticleView: View {
    @Environment(AppModel.self) private var model
    let feature: Feature
    @State private var progress = 0.0
    @State private var active = 0
    private let bar = 20

    private var article: Article {
        let url = languageBundle.url(forResource: feature.slug, withExtension: "md")
        return Article(markdown: url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")
    }

    var body: some View {
        let article = article
        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 32) {
                contents(article) { id in withAnimation(Hax.ease(Hax.slow)) { proxy.scrollTo(id, anchor: .top) } }
                    .frame(width: 224).padding(.top, 24).reveal(0)
                GeometryReader { viewport in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                            header(article).reveal(1)
                            ForEach(article.sections) { section in
                                VStack(alignment: .leading, spacing: 12) {
                                    (Text(verbatim: "## ").foregroundStyle(Hax.textDisabled) + Text(verbatim: section.title).foregroundStyle(Hax.textPrimary))
                                        .font(Hax.mono(16, .medium))
                                    ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in BlockView(block: block) }
                                }
                                .id(section.id)
                                .background(marker(section.id))
                                .reveal(2 + section.id)
                            }
                            footer.background(marker(endID, edge: .bottom))
                        }
                        .frame(maxWidth: 680, alignment: .leading)
                        .padding(.vertical, 24).padding(.trailing, 24)
                        .background(marker(articleID))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .coordinateSpace(name: "article")
                    .onPreferenceChange(Offsets.self) { offsets in
                        // reading position, straight from the scroll offset
                        let top = offsets[articleID] ?? 0, bottom = offsets[endID] ?? 0
                        let scrollable = bottom - top - viewport.size.height + 24
                        progress = scrollable <= 1 ? 1 : min(max(-top / scrollable, 0), 1)
                        let line: CGFloat = 120  // a section is current once its heading nears the top
                        active = article.sections.last { (offsets[$0.id] ?? .infinity) <= line }?.id ?? 0
                    }
                }
            }
            .padding(.leading, 24)
        }
    }

    private func marker(_ id: Int, edge: Alignment = .top) -> some View {
        GeometryReader { geo in
            Color.clear.preference(key: Offsets.self, value: [id: edge == .top ? geo.frame(in: .named("article")).minY : geo.frame(in: .named("article")).maxY])
        }
    }

    private func contents(_ article: Article, jump: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HxButton(title: feature.isFix ? L("back to fixes") : L("back to tools"), variant: .ghost, small: true, icon: "arrow-left") { model.screen = feature.home }
            VStack(alignment: .leading, spacing: 1) {
                ForEach(article.sections) { section in
                    let current = section.id == active
                    Button { jump(section.id) } label: {
                        HStack(spacing: 8) {
                            Text(verbatim: current ? "▸" : " ")
                            Text(verbatim: section.title).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .font(Hax.bodySmall).foregroundStyle(current ? Hax.accent : Hax.textMuted)
                        .padding(.horizontal, 8).frame(height: 28).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            let cells = Int((progress * Double(bar)).rounded())
            (Text(verbatim: String(repeating: "█", count: cells)).foregroundStyle(Hax.accent)
                + Text(verbatim: String(repeating: "░", count: bar - cells) + String(format: " %3d%%", Int((progress * 100).rounded()))).foregroundStyle(Hax.textDisabled))
                .font(Hax.mono(11)).tracking(-0.5).padding(.horizontal, 8)
                .accessibilityLabel(L("reading progress")).accessibilityValue("\(Int(progress * 100))%")
        }
    }

    private func header(_ article: Article) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                IconBox(icon: feature.icon)
                HxHint(feature.meta)
            }
            Text(verbatim: feature.title).font(Hax.mono(28, .medium)).tracking(-0.4).foregroundStyle(Hax.textPrimary)
            Text(verbatim: article.lead).font(Hax.body).foregroundStyle(Hax.textPrimary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(spacing: 16) {
            Rectangle().fill(Hax.borderSubtle).frame(height: 1)
            HStack {
                HxHint(L("%@.md · bundled with the app", feature.slug))
                Spacer()
                HxButton(title: L("source on github"), small: true, icon: "git-fork", iconRight: "arrow-up-right") { NSWorkspace.shared.open(repoURL) }
            }
        }
    }
}

private struct BlockView: View {
    let block: Article.Block

    var body: some View {
        switch block {
        case .paragraph(let text):
            rich(text).font(Hax.body).foregroundStyle(Hax.textSecondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        case .list(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "▸").foregroundStyle(Hax.accent)
                        rich(item).foregroundStyle(Hax.textSecondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(Hax.body)
                }
            }
        case .table(let head, let rows):
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 0) {
                GridRow { tableCells(head, header: true) }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Rectangle().fill(Hax.borderSubtle).frame(height: 1).gridCellColumns(head.count).gridCellUnsizedAxes(.horizontal)
                    GridRow { tableCells(row, header: false) }
                }
            }
            .surface(Hax.bgCard, border: Hax.borderSubtle, radius: Hax.radiusMD)
        case .bars(let label, let unit, let before, let after):
            MeasureBars(measure: .init(label: label, unit: unit, before: before, after: after), large: true)
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .surface(Hax.bgCard, border: Hax.borderSubtle, radius: Hax.radiusMD)
        case .code(let title, let text):
            VStack(spacing: 0) {
                Text(verbatim: title).font(Hax.caption).foregroundStyle(Hax.textMuted).frame(maxWidth: .infinity).frame(height: 34).background(Hax.bgCard)
                Rectangle().fill(Hax.borderSubtle).frame(height: 1)
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(verbatim: text).font(Hax.bodySmall).foregroundStyle(Hax.textPrimary).lineSpacing(5).textSelection(.enabled).padding(16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .surface(Hax.bgPanel, border: Hax.borderDefault, radius: Hax.radiusMD)
            .clipShape(RoundedRectangle(cornerRadius: Hax.radiusMD))
        case .command(let command):
            HxCommandLine(command: command)
        case .note(let warning, let text):
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HxBadge(text: warning ? "WARN" : "INFO", tone: warning ? .warning : .info, bracket: true)
                rich(text).font(Hax.bodySmall).foregroundStyle(Hax.textSecondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: Hax.radiusMD).strokeBorder(Hax.borderDefault, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
    }

    /// Text between backticks is code: brighter, on a card-coloured ground.
    private func rich(_ text: String) -> Text {
        var out = AttributedString()
        for (index, part) in text.components(separatedBy: "`").enumerated() {
            var run = AttributedString(part)
            if index % 2 == 1 {
                run.foregroundColor = Hax.textPrimary
                run.backgroundColor = Hax.bgRaised
            }
            out += run
        }
        return Text(out)
    }

    private func tableCells(_ cells: [String], header: Bool) -> some View {
        ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
            Group {
                if header {
                    Text(verbatim: cell.uppercased()).font(Hax.overline).tracking(0.9).foregroundStyle(Hax.textMuted)
                } else {
                    Text(verbatim: cell).font(Hax.bodySmall).foregroundStyle(index == 0 ? Hax.textPrimary : Hax.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, index == 0 ? 16 : 0).padding(.trailing, index == cells.count - 1 ? 16 : 0).padding(.vertical, 8)
        }
    }
}
