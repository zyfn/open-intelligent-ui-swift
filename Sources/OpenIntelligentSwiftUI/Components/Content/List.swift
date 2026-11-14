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
    @Environment(\.intelligentUIInteractiveContent) private var interactive
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
            guard context.canInteract, !interactive, SourceURL.isActionable(url.absoluteString) else { return .discarded }
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
    @Environment(\.locale) private var locale
    let context: OpenUIComponentContext
    @Environment(\.intelligentUITheme) private var theme
    @Environment(\.layoutDirection) private var direction
    @ScaledMetric(relativeTo: .body) private var markerHeight = 26.0
    @ScaledMetric(relativeTo: .body) private var markerLane = 24.0

    var body: some View {
        let children = context.children("items")
        let timeline = context.flag("timeline") == true
        let mode = context.string("marker") ?? "bullet"
        return VStack(alignment: .leading, spacing: timeline ? 0 : theme.paragraphSpacing) {
            ForEach(Array(children.enumerated()), id: \.element.id) { ordinal, child in
                let custom = ValueReading.string(ValueReading.field(child.value, "marker"))
                let longMarker = ListMarkerRules.usesHeader(custom)
                let showsLane = mode != "none" || (!custom.isEmpty && (!longMarker || timeline))
                let lane = mode == "bullet" && !timeline && custom.isEmpty ? markerLane * 0.6 : markerLane
                let nextHasMarker = ordinal + 1 < children.count && (mode != "none" || !ValueReading.string(ValueReading.field(children[ordinal + 1].value, "marker")).isEmpty)
                HStack(alignment: .top, spacing: theme.innerSpacing) {
                    if showsLane {
                        marker(custom: longMarker ? "" : custom, mode: longMarker && timeline ? "bullet" : mode, ordinal: ordinal, timeline: timeline)
                            .frame(width: lane, alignment: .center)
                            .frame(minHeight: markerHeight, alignment: .top)
                    }
                    VStack(alignment: .leading, spacing: theme.spacingUnit) {
                        // Each item's own marker determines its presentation;
                        // appending another item cannot reformat earlier rows.
                        if longMarker {
                            Text(custom).font(theme.captionFont).monospacedDigit()
                                .foregroundStyle(theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                        }
                        if case .string(let text) = child.value { RichMarkdown(context: context, text: text.displayString, compact: true) }
                        else { context.render(child.value) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, timeline && ordinal < children.count - 1 ? theme.groupSpacing : 0)
                .background(alignment: .leading) {
                    if timeline && showsLane && nextHasMarker {
                        GeometryReader { geometry in
                            Path { path in
                                let line = TimelineGeometry.connector(lane: lane, wide: false, markerHeight: markerHeight, rowHeight: geometry.size.height)
                                let x = direction == .rightToLeft ? geometry.size.width - line.start.x : line.start.x
                                path.move(to: CGPoint(x: x, y: line.start.y))
                                path.addLine(to: CGPoint(x: x, y: line.end.y))
                            }.stroke(theme.separator, lineWidth: 1)
                        }.accessibilityHidden(true)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    @ViewBuilder private func marker(custom: String, mode: String, ordinal: Int, timeline: Bool) -> some View {
        if !custom.isEmpty {
            Text(custom).font(theme.captionFont.weight(.medium)).monospacedDigit()
                .foregroundStyle(theme.primaryText).fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: markerHeight)
        } else if mode == "number" {
            Text(String(ordinal + 1) + ".").font(theme.captionFont.weight(.medium)).monospacedDigit()
                .foregroundStyle(theme.primaryText).frame(minHeight: markerHeight)
                .accessibilityLabel(SDKStrings.text("list.item", locale: locale, Int64(ordinal + 1)))
        } else if timeline {
            Circle().fill(theme.canvas).overlay(Circle().strokeBorder(theme.primaryText, lineWidth: 2))
                .frame(width: 9, height: 9).frame(height: markerHeight).accessibilityHidden(true)
        } else {
            Circle().fill(theme.secondaryText).frame(width: 5, height: 5)
                .frame(height: markerHeight).accessibilityHidden(true)
        }
    }
}

enum ListMarkerRules {
    static func usesHeader(_ marker: String) -> Bool { marker.count > 2 || marker.contains("\n") }
    static func connects(mode: String, wide: Bool, timeline: Bool) -> Bool { timeline && (mode != "none" || wide) }
}

enum TimelineGeometry {
    static func anchor(lane: CGFloat, wide: Bool) -> CGFloat { wide ? lane + 10 : lane / 2 }
    static func connector(lane: CGFloat, wide: Bool, markerHeight: CGFloat, rowHeight: CGFloat) -> (start: CGPoint, end: CGPoint) {
        let x = anchor(lane: lane, wide: wide)
        return (.init(x: x, y: markerHeight / 2 + 5), .init(x: x, y: max(markerHeight / 2 + 5, rowHeight + markerHeight / 2 - 5)))
    }
}
