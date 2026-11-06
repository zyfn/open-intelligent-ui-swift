import SwiftUI
import OpenUILang
import OpenUISwiftUI

enum SVGComponents {
    static var components: [OpenUIComponent] {
        let paint: [ParamDef] = [OpenUIParameter.string("fill", required: false), OpenUIParameter.string("stroke", required: false), Parameter.number("strokeWidth", minimum: 0), Parameter.number("opacity", minimum: 0, maximum: 1)]
        func numbers(_ names: [String]) -> [ParamDef] { names.map { var p = Parameter.number($0); p.required = true; return p } }
        let shapes: [(String, [ParamDef])] = [
            ("Svg", [OpenUIParameter.slot("children", required: true), OpenUIParameter.string("viewBox"), Parameter.number("width", minimum: 0, maximum: 2400), Parameter.number("height", minimum: 0, maximum: 2400)]),
            ("Circle", numbers(["cx", "cy", "r"]) + paint),
            ("Ellipse", numbers(["cx", "cy", "rx", "ry"]) + paint),
            ("Rect", numbers(["x", "y", "width", "height"]) + paint + [Parameter.number("rx", minimum: 0)]),
            ("Line", numbers(["x1", "y1", "x2", "y2"]) + [OpenUIParameter.string("stroke", required: false), Parameter.number("strokeWidth", minimum: 0), Parameter.number("opacity", minimum: 0, maximum: 1)]),
            ("Path", [OpenUIParameter.string("d")] + paint),
            ("Polyline", [OpenUIParameter.string("points"), OpenUIParameter.string("stroke", required: false), Parameter.number("strokeWidth", minimum: 0), OpenUIParameter.string("fill", required: false), Parameter.number("opacity", minimum: 0, maximum: 1)]),
            ("Polygon", [OpenUIParameter.string("points")] + paint),
            ("G", [OpenUIParameter.slot("children", required: true), OpenUIParameter.string("transform", required: false), Parameter.number("opacity", minimum: 0, maximum: 1)]),
            ("SvgText", [OpenUIParameter.string("text")] + numbers(["x", "y"]) + [Parameter.number("size", minimum: 0), OpenUIParameter.string("fill", required: false), OpenUIParameter.string("anchor", required: false, values: ["start", "middle", "end"]), OpenUIParameter.string("weight", required: false, values: ["normal", "medium", "semibold"])])
        ]
        return shapes.map { name, params in
            let detail = name == "Svg" ? " viewBox defines drawing coordinates; displayed width/height can scale the whole diagram. Keep essential labels at least about 14 display points on phones; put detailed/accessibility explanations in native text outside the drawing." : name == "SvgText" ? " size is in viewBox units, not guaranteed display points: size * displayedWidth / viewBoxWidth estimates the rendered size when width-constrained. Avoid tiny labels; text does not independently grow with Dynamic Type." : ""
            return OpenUIComponent(name: name, description: "SVG drawing element rendered in a script-free local WebKit bridge. Numeric attributes use drawing coordinates; shapes accept finite values and safe paint/transform attributes only." + detail, params: params) { context in
                SVGView(context: context)
            }
        }
    }
}

enum SVGMarkup {
    static func render(_ element: EvaluatedElement, depth: Int = 0) -> String {
        guard depth < 64 else { return "" }
        let names = ["Svg": "svg", "Circle": "circle", "Ellipse": "ellipse", "Rect": "rect", "Line": "line", "Path": "path", "Polyline": "polyline", "Polygon": "polygon", "G": "g", "SvgText": "text"]
        guard let tag = names[element.typeName] else { return "" }
        func value(_ key: String) -> Value? { element.props.last { $0.0 == key }?.1 }
        var attrs: [String] = []
        for key in ["cx", "cy", "r", "rx", "ry", "x", "y", "width", "height", "x1", "x2", "y1", "y2", "strokeWidth", "opacity", "size"] {
            if let number = ValueReading.number(value(key)) {
                let name = key == "strokeWidth" ? "stroke-width" : key == "size" ? "font-size" : key
                let n = key == "opacity" ? min(1, max(0, number)) : ["r", "rx", "ry", "width", "height", "strokeWidth", "size"].contains(key) ? max(0, number) : number
                attrs.append("\(name)=\"\(n)\"")
            }
        }
        let filled = ["Circle", "Ellipse", "Rect", "Polygon", "SvgText"].contains(element.typeName) || value("fill") != nil
        if tag != "svg" && tag != "g" {
            attrs.append("fill=\"\(paint(ValueReading.string(value("fill"))) ?? (filled && value("stroke") == nil ? "currentColor" : "none"))\"")
            if let stroke = paint(ValueReading.string(value("stroke"))) { attrs.append("stroke=\"\(stroke)\"") }
            else if !filled {
                attrs.append("stroke=\"currentColor\"")
                if value("strokeWidth") == nil { attrs.append("stroke-width=\"2\"") }
            }
        }
        if tag == "svg" {
            let viewBox = validated(ValueReading.string(value("viewBox")), pattern: #"^\s*[-\d.]+[\s,]+[-\d.]+[\s,]+[\d.]+[\s,]+[\d.]+\s*$"#) ?? "0 0 100 100"
            attrs.append("viewBox=\"\(viewBox)\"")
        }
        if let points = validated(ValueReading.string(value("points")), pattern: #"^[\d\s,.eE+\-]+$"#) { attrs.append("points=\"\(points)\"") }
        if let path = validated(ValueReading.string(value("d")), pattern: #"^[MmLlHhVvCcSsQqTtAaZz\d\s,.eE+\-]+$"#) { attrs.append("d=\"\(path)\"") }
        if let transform = validated(ValueReading.string(value("transform")), pattern: #"^(\s*(translate|rotate|scale|skewX|skewY|matrix)\([\d\s,.eE+\-]+\)\s*)+$"#) { attrs.append("transform=\"\(transform)\"") }
        if ["start", "middle", "end"].contains(ValueReading.string(value("anchor"))) { attrs.append("text-anchor=\"\(ValueReading.string(value("anchor")))\"") }
        if ["normal", "medium", "semibold"].contains(ValueReading.string(value("weight"))) { attrs.append("font-weight=\"\(ValueReading.string(value("weight")) == "semibold" ? 600 : ValueReading.string(value("weight")) == "medium" ? 500 : 400)\"") }
        if tag == "svg" { attrs.append("xmlns=\"http://www.w3.org/2000/svg\" preserveAspectRatio=\"xMidYMid meet\" style=\"width:100%;height:100%\"") }
        let children = ValueReading.array(value("children")).prefix(2048).compactMap { value -> String? in
            guard case .element(let child) = value else { return nil }; return render(child, depth: depth + 1)
        }.joined()
        return "<\(tag) \(attrs.joined(separator: " "))>" + (tag == "text" ? XMLText.escape(ValueReading.string(value("text"))) : children) + "</\(tag)>"
    }
    static func paint(_ text: String) -> String? {
        let tokens = ["ink":"currentColor", "muted":"gray", "faint":"gray", "surface":"transparent", "info":"#007aff", "success":"#248a3d", "warning":"#b25000", "danger":"#d70015", "chart1":"#007aff", "chart2":"#248a3d", "chart3":"#af52de", "chart4":"#ff9500", "chart5":"#ff2d55", "chart6":"#30b0c7"]
        if let color = tokens[text] { return color }
        return validated(text, pattern: #"^(#[0-9a-fA-F]{3,8}|[a-zA-Z]+|rgba?\([\d\s,.%]+\)|hsla?\([\d\s,.%]+\))$"#)
    }
    private static func validated(_ text: String, pattern: String) -> String? {
        guard !text.isEmpty, text.count < 20_000, text.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return XMLText.escape(text)
    }
}
private struct SVGView: View {
    let context: OpenUIComponentContext
    var body: some View {
        let markup = SVGMarkup.render(context.element)
        let source = context.element.typeName == "Svg" ? markup : "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\" style=\"width:100%;height:100%\">\(markup)</svg>"
        WebContent(context: context, content: source, height: CGFloat(min(2400, max(40, context.number("height") ?? 240))))
            .frame(width: context.number("width").map { CGFloat(min(2400, max(0, $0))) })
            .accessibilityLabel("矢量图示")
    }
}
