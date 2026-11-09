import SwiftUI
import OpenUILang
import OpenUISwiftUI

enum ListItemComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "ListItem", description: "List item with title, description, optional custom marker and child content. Runtime statement identity preserves content; persistence after unmount requires an explicit binding.", params: [
            OpenUIParameter.string("title"), OpenUIParameter.string("description", required: false),
            OpenUIParameter.string("marker", required: false), OpenUIParameter.slot("children")
        ]) { ListItemView(context: $0) }
    }
}
private struct ListItemView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title = context.string("title"), !title.isEmpty { Text(inline(title, font: theme.bodyFont.weight(.medium))).font(theme.bodyFont.weight(.medium)).fixedSize(horizontal: false, vertical: true) }
            if let description = context.string("description"), !description.isEmpty {
                Text(inline(description, font: theme.secondaryFont)).font(theme.secondaryFont).foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            if !context.children().isEmpty { context.slot().padding(.top, theme.innerSpacing - 2) }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard context.canInteract, SourceURL.isActionable(url.absoluteString) else { return .discarded }
            Task { await context.perform(OpenUIActions.openURL(url.absoluteString)) }; return .handled
        })
    }
    private func inline(_ text: String, font: Font) -> AttributedString { InlineTypography.attributed(text, font: font, emphasis: theme.emphasisWeight) }
}
enum ListComponent {
    static var component: OpenUIComponent {
        OpenUIComponent(name: "List", description: "Ordered content. marker defaults to bullet; timeline links the markers. Custom ListItem markers take precedence.", params: [
            Parameter.array("items", items: .object([.init(key: "anyOf", value: .array([
                .object([.init(key: "type", value: .string("string"))]), .object([.init(key: "$ref", value: .string("#/$defs/ListItem"))])
            ]))])),
            OpenUIParameter.string("marker", required: false, values: ["bullet", "number", "none"]), OpenUIParameter.flag("timeline")
        ]) { ListView(context: $0) }
    }
}
private struct ListView: View {
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    @ScaledMetric(relativeTo: .body) private var markerHeight = 26.0
    @ScaledMetric(relativeTo: .body) private var timeWidth = 64.0
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let children = context.children("items")
        let wide = children.contains { ValueReading.string(ValueReading.field($0.value, "marker")).count > 2 }
        let timeline = context.flag("timeline") == true
        let mode = context.string("marker") ?? "bullet"
        VStack(alignment: .leading, spacing: timeline ? 0 : 10) {
            ForEach(Array(children.enumerated()), id: \.element.id) { ordinal, child in
                let custom = ValueReading.string(ValueReading.field(child.value, "marker"))
                let stacked = wide && typeSize.isAccessibilitySize
                let showsMarker = !custom.isEmpty || mode != "none" || wide
                let connects = ListMarkerRules.connects(mode: mode, wide: wide, timeline: timeline) && ordinal < children.count - 1
                let lane: CGFloat = stacked ? 24 : wide ? timeWidth : (mode == "bullet" && !timeline ? 14 : 24)
                let anchor = TimelineGeometry.anchor(lane: lane, wide: wide && !stacked)
                HStack(alignment: .top, spacing: wide && !stacked ? 24 : mode == "bullet" && !timeline ? 8 : 12) {
                    if showsMarker {
                        Group {
                            if stacked { node }
                            else { marker(custom: custom, mode: mode, ordinal: ordinal, timeline: timeline, wide: wide) }
                        }
                            .frame(width: lane, height: markerHeight, alignment: wide && !stacked ? .leading : .center)
                            .overlay(alignment: .topLeading) {
                                if wide && timeline && !stacked {
                                    node.position(x: anchor, y: markerHeight / 2)
                                }
                            }
                            .accessibilityHidden(stacked || custom.isEmpty)
                    }
                    VStack(alignment: .leading, spacing: theme.spacingUnit) {
                        if stacked && !custom.isEmpty { Text(custom).font(theme.captionFont).monospacedDigit().foregroundStyle(theme.secondaryText) }
                        if case .string(let text) = child.value { RichMarkdown(context: context, text: text.displayString, compact: true) }
                        else { context.render(child.value) }
                    }
                }
                .padding(.bottom, timeline && ordinal < children.count - 1 ? 18 : 0)
                .background(alignment: .leading) {
                    if connects {
                        GeometryReader { geometry in
                            Path { path in
                                let line = TimelineGeometry.connector(lane: lane, wide: wide && !stacked, markerHeight: markerHeight, rowHeight: geometry.size.height)
                                path.move(to: line.start)
                                path.addLine(to: line.end)
                            }.stroke(theme.separator, lineWidth: 1)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    @ViewBuilder private func marker(custom: String, mode: String, ordinal: Int, timeline: Bool, wide: Bool) -> some View {
        if wide {
            Text(custom).font(theme.captionFont).monospacedDigit().foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true)
        } else if !custom.isEmpty {
            if custom.range(of: "^[0-9A-Za-z]{1,2}$", options: .regularExpression) != nil {
                Text(custom).font(theme.captionFont.weight(.medium)).foregroundStyle(theme.actionForeground)
                    .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20).background(theme.primaryText, in: Capsule())
            } else {
                Text(custom).font(theme.captionFont).monospacedDigit().foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if mode == "number" {
            Text(String(ordinal + 1)).font(theme.captionFont.weight(.medium)).monospacedDigit().foregroundStyle(theme.actionForeground)
                .frame(width: 24, height: 24).background(theme.primaryText, in: Circle())
        } else if timeline { node }
        else { Circle().fill(theme.secondaryText).frame(width: 5, height: 5) }
    }
    private var node: some View { Circle().fill(theme.canvas).overlay(Circle().strokeBorder(theme.primaryText, lineWidth: 2)).frame(width: 9, height: 9) }
}

enum ListMarkerRules {
    static func connects(mode: String, wide: Bool, timeline: Bool) -> Bool { timeline && (mode != "none" || wide) }
}

enum TimelineGeometry {
    static func anchor(lane: CGFloat, wide: Bool) -> CGFloat { wide ? lane + 10 : lane / 2 }
    static func connector(lane: CGFloat, wide: Bool, markerHeight: CGFloat, rowHeight: CGFloat) -> (start: CGPoint, end: CGPoint) {
        let x = anchor(lane: lane, wide: wide)
        return (.init(x: x, y: markerHeight / 2 + 5), .init(x: x, y: max(markerHeight / 2 + 5, rowHeight + markerHeight / 2 - 5)))
    }
}
