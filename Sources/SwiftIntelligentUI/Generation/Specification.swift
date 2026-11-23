import Foundation
import SwiftLang

extension OpenIntelligentUIComponents {
    public var specification: LibrarySpec { components.toSpec() }
    public var specificationJSON: String { specification.jsonString() }
    /// Historical read contract, including compatibility-only fields.
    public var readerSpecification: LibrarySpec { readerComponents.toSpec() }

    public var systemPrompt: String {
        let generated = components.prompt(PromptOptions(
            additionalRules: selectedGenerationRules,
            examples: selectedGenerationExamples, toolCalls: false, bindings: true
        ))
        // The pinned core template assumes an implicit Button action.
        // This narrow policy adapter is not a signature/schema transformation.
        // Writer definitions above are the source of every exported signature.
        return generated.replacingOccurrences(
            of: "Buttons without an action automatically send their label to the assistant (equivalent to @ToAssistant(label)).",
            with: "Buttons without an explicit action are disabled. No implicit assistant request is sent."
        )
    }

    var selectedGenerationRules: [String] {
        let available = Set(components.library.components.map(\.name))
        return Self.generationRules.filter { $0.requires.isSubset(of: available) }.map(\.text)
    }

    var selectedGenerationExamples: [String] {
        let available = Set(components.library.components.map(\.name))
        return Self.generationExampleDefinitions.filter { $0.requires.isSubset(of: available) }.map(\.source)
    }

    private struct GenerationRule {
        let text: String
        let requires: Set<String>
        init(_ text: String, requires: Set<String> = []) {
            self.text = text
            self.requires = requires
        }
    }

    private static let generationRules: [GenerationRule] = [
        .init("Output only the complete openui-lang program, without a Markdown fence or a JSON wrapper. Use registered components, declared positional arguments and supported functions. State defaults are literals; derived values belong in ordinary variables. Use ASCII identifiers, quoted non-ASCII keys and bracket access. Respect exact case-sensitive source field names."),
        .init("Organize the answer around the user task: concise conclusion, meaningful groups, then supporting details. Choose one primary presentation for each idea. Use whitespace and alignment for reading. Preserve source uncertainty concisely. For follow-ups, update the requested material and retain relevant entity identity; do not recreate unrelated interactive sections."),
        .init("Copy each source URL once into a variable and reuse its exact opaque string, including encoded/compressed values and padding. Never normalize, shorten, decode, repair or remove parts. Keep fields owned by their exact source entity or endpoint. Do not infer elapsed time from local clocks, fees from unknown status codes, missing photos or coordinates. Describe planned amounts as estimates, not actual purchases."),
        .init("Use stable named statements for stateful content and explicit bindings for state that must survive unmounting. Do not depend on a particular intermediate rendering order while the source is streaming; the runtime follows the pinned OpenUI default publication behavior. Reactive state edits may update already visible content."),
        .init("Examples show syntax and composition only; replace illustrative data with supplied task facts. Project records to component schemas instead of passing rich business objects wholesale. Parser success does not establish source fidelity, legal fields, correct calculations or accessible layout."),
        .init("Bind edits to visible results or an explicit action. Present real validation and result feedback. Never fabricate progress, availability, completion or action success. Navigation does not purchase or confirm inventory. ToAssistant is allowed only when the caller explicitly supports a follow-up request; the SDK provides no assistant or order service."),
        .init("Preserve supplied price amounts, currencies and quote scope, including later corrections. Determine ownership from source fields, not earlier assistant explanations. For requested budgets, totals or allocations, use known inputs with compatible currencies and scope; label derived results and estimates separately from source quotes. Do not invent prices, fees, exchange rates, stock, ratings or cancellation terms. Missing conditions do not erase a known amount; a round-trip URL or leg count does not establish a total fare."),
        .init("Use the default semantic typography and colors. Leave body weight at normal; emphasize only short key phrases when useful. Do not make entire paragraphs semibold or mute primary prose. Avoid equivalent solid foreground/background colors. Status backgrounds are soft tints. Explicit component parameters express intent; wrapping content does not redefine its meaning."),
        .init("Use typed calculations: numeric Min/Max do not consume clock strings. Same-date/same-zone zero-padded clocks can be sorted then the owning record selected. FormatDate has no locale argument; its named styles are English, iso is language-neutral. Plural defaults to English. Keep monetary rounding and source duration scope explicit."),
        .init("Use Card when a real object or coherent group needs one visible surface. Its children form a vertical group; ordinary paragraphs and chapters can keep open reading layout. Do not add a surface merely to arrange content or repeat a heading inside every card.", requires: ["Card"]),
        .init("Title labels real headings; Text is the reading body; Caption is supporting text. Text sizes are xs/sm/md/lg only. Do not wrap headings in Markdown bold. Choose an explicit supporting role when intended rather than relying on an item's position.", requires: ["Title", "Text", "Caption"]),
        .init("Grid arranges ordinary children in equal-width columns independently of their surfaces. columns is the fixed count when minChildWidth is omitted; with minChildWidth it is the maximum count. Choose a readable minChildWidth for the content and let the container determine the actual columns.", requires: ["Grid"]),
        .init("Box supplies explicit sizing, padding, background and borders when the content needs them. Ordinary compositions can use the layout defaults; explicit layout arguments are optional controls, not a required wrapper pattern.", requires: ["Box"]),
        .init("For a photo beside text, place the image and a Col of text directly in Row. Its horizontal photo layout owns width, alignment and 4:3 framing, overriding the image aspectRatio. Choose the content relationship without calculating device widths or adding required width/flex wrappers.", requires: ["Row", "Col", "Image"]),
        .init("Image(src, alt, aspectRatio?, radius?, fit?) accepts a real supplied URL and meaningful alt. Leave optional framing unset for ordinary use; specify it when the content calls for it, and let the containing layout supply its defaults. Never invent a URL or attribution.", requires: ["Image"]),
        .init("SearchImage(query, aspectRatio?, radius?, fit?) requires an explicitly configured caller search service. Give an exact subject; framing arguments are optional. Do not fabricate attribution.", requires: ["SearchImage"]),
        .init("Use Col for vertical reading, Row for a horizontal group, Grid for equal-width columns and Carousel for horizontal browsing. Each arranges ordinary child components. Choose the layout from the information relationship; do not add decorative page numbers or current/total counters.", requires: ["Col", "Row", "Grid", "Carousel"]),
        .init("Keep a figure and its attribution in one compact Col([Image(src,alt), Text([suppliedCredit, Citation(suppliedSources)], \"xs\", \"muted\")], 2). Preserve supplied author/license facts. Add references only where supported and useful; do not fabricate attribution or add an empty source entry.", requires: ["Image", "Col", "Text", "Citation"]),
        .init("References attached to a sentence belong in mixed Text([text, Citation(...)]) so they share paragraph flow; standalone source lists remain valid. Do not append sources around consumer cards by default.", requires: ["Citation", "Text"]),
        .init("Use Link for intentional navigation such as an official site or full guide; avoid duplicate standalone source links when a source entry already serves that purpose.", requires: ["Link"]),
        .init("Badge presents static facts; it is not a selectable or actionable control.", requires: ["Badge"]),
        .init("Use SegmentedControl for a short view switch with a real visible result.", requires: ["SegmentedControl"]),
        .init("Use RadioGroup for one choice. Retain complete supplied option descriptions and an explicit binding.", requires: ["RadioGroup"]),
        .init("Use Checkbox for independent choices and a real binding; do not replace an entity's details with a checklist.", requires: ["Checkbox"]),
        .init("Every enabled Button needs an explicit action. Buttons without an explicit action are disabled. No implicit assistant request is sent.", requires: ["Button"]),
        .init("Every enabled IconButton needs an explicit action and an accessible label describing the operation.", requires: ["IconButton"]),
        .init("Every enabled Pressable needs an explicit action. Its children are presentation-only; never nest interactive controls or independent link/image operations inside the trigger.", requires: ["Pressable"]),
        .init("Popover trigger content is presentation-only. Put independent controls and links inside the opened content, not inside the trigger.", requires: ["Popover"]),
        .init("Use ProductCard for supplied purchasable goods or bookable services, including accommodation. Preserve known price, all supplied images, exact purchase/booking destination and stable entity identity. Filtering, confirmation or adding a checklist must keep selected entities as cards; use a compact layout when useful. Do not generate legacy priceText, offers, marketing prefixes or inferred units. Put supplied conditions in priceNote.", requires: ["ProductCard"]),
        .init("Use JourneyLine as a horizontal transport connector between departure and arrival content. Place it between endpoint groups inside Row and choose its mode only from supplied transport facts. It draws the dashed line and mode icon; times, station names, duration, transfer details, price and actions remain ordinary sibling components. Do not use it as a vertical timeline or invent route facts.", requires: ["JourneyLine"]),
        .init("Build Map markers only from supplied names and coordinates, with optional source category and emoji icon. Never invent coordinates or place facts. Map handles category filtering, recentering, expansion and responsive sizing. selected stores the clicked marker label, including when labels repeat. route follows the supplied marker order when street routing is available; an overview does not imply turn-by-turn navigation or an inferred visit order.", requires: ["Map", "MapMarker"]),
        .init("ListItem.description is a secondary summary; put substantial reading content in children. Timeline times and stages use the existing marker field.", requires: ["ListItem"]),
        .init("Use Svg for a diagram; always provide its short accessible label. Svg children must be drawing shapes (G may group shapes), not arbitrary UI. Preserve source coordinates and readable text, with equivalent native explanation. Explicit source colors retain meaning; semantic colors follow the SwiftUI theme.", requires: ["Svg"]),
        .init("Flashcard is a learning surface, not decoration. Both faces are presentation-only; keep independent interactive operations outside the flipping surface.", requires: ["Flashcard"]),
        .init("Celebration reflects a real supplied state transition only. Do not use it to imply an unconfirmed business result.", requires: ["Celebration"]),
        .init("Use HtmlView only when the task needs its content. It has no native bridge and is not a substitute for registered native controls.", requires: ["HtmlView"])
    ]

    private struct GenerationExample {
        let source: String
        let requires: Set<String>

        init(_ source: String, requires: Set<String>) {
            self.source = source
            self.requires = requires
        }
    }

    static var generationExamples: [String] { generationExampleDefinitions.map(\.source) }

    private static let generationExampleDefinitions: [GenerationExample] = [
        .init("""
        Earliest record from same-date, same-timezone zero-padded clock strings; preserve source key casing and exact action data:
        root = Col([Title("同日抵达方案", "lg"), Text("最早抵达：" + earliest.arr), Button("查看方案", @OpenUrl(earliest.bookingUrl), "outline")])
        rails = [{id:"a", date:"2026-11-07", zone:"同一输入时区", arr:"10:30", bookingUrl:"https://example.com/journey?itemParams=AA%3D%3D&flag=1"}, {id:"b", date:"2026-11-07", zone:"同一输入时区", arr:"07:49", bookingUrl:"https://example.com/journey?itemParams=BB%3D%3D&flag=1"}]
        earliest = @First(@Sort(rails, "arr", "asc"))
        """, requires: ["Col", "Title", "Text", "Button"]),
        .init("""
        Stable logical task keys in a switched list; local disclosure state and explicit business state are separate:
        root = Col([SegmentedControl($stage, ["输入", "输出"]), List($stage == "输入" ? inputItems : outputItems)])
        $stage = "输入"
        $done = false
        inputItems = [ListItem("", "", "", [Checkbox($done, "输入步骤", true), Disclosure("说明", [Text("准备输入资料。")])])]
        outputItems = [ListItem("输出步骤", "", "", [Disclosure("说明", [Text("查看输出资料。")])])]
        """, requires: ["Col", "SegmentedControl", "List", "ListItem", "Checkbox", "Disclosure", "Text"]),
        .init("""
        Consumer confirmation keeps the same ProductCard, price and destination; a checklist supplements it:
        root = Col([$confirmed ? ProductCard(product,"compact") : ProductCard(product), $confirmed ? Checkbox($checked,"已核对购买条件") : Button("确认首选",@Set($confirmed,true)), Text("补充规格：" + record.noiseControl)])
        $confirmed = false
        $checked = false
        originalURL = "https://example.com/item?sku=a%2Fb&exParams=keep%3D1&flag=0"
        record = {id:"headphones", title:"耳机", images:[{url:"https://example.com/headphones.jpg",alt:"耳机"}], price:300, currency:"CNY", purchaseURL:originalURL, noiseControl:"输入资料中的规格描述"}
        product = {id:record.id, title:record.title, images:record.images, price:record.price, currency:record.currency, purchaseURL:originalURL}
        """, requires: ["Col", "ProductCard", "Checkbox", "Button", "Text"]),
        .init("""
        Editorial cover and open sections for supplied observations. This is one reading composition, not a required page template:
        root = Col([opening, figure, silhouette, structure])
        opening = Col([Caption("建筑观察"), Title("看见屋檐的层次", "2xl"), Text("先看整体轮廓，再看支撑关系。", "lg")])
        figure = Col([Image(coverURL, "建筑封面", 1.5), Caption("资料图：屋檐与支撑构件。"), Text(["图片：示例摄影者 · 示例许可 ", Citation([{title:"封面图片来源与许可",url:sourceURL}])], "xs", "muted")], 2)
        silhouette = Col([Title("先看整体轮廓", "lg"), Text("屋檐的连续线条形成整体轮廓。先观察线条的方向，再留意层次变化。")])
        structure = Col([Title("再看支撑关系", "lg"), Text("从屋檐下方的可见构件，观察彼此之间的连接与支撑关系。"), Caption("对照资料观察，不以外观推断未提供的年代或材料。")])
        coverURL = "https://example.com/cover.jpg"
        sourceURL = "https://example.com/cover-source"
        """, requires: ["Col", "Title", "Image", "Text", "Caption", "Citation"]),
        .init("""
        Photo beside reading content; Row supplies its default media layout:
        root = Col([Row([photo, copy])])
        photo = Image("https://example.com/detail.jpg", "建筑细节")
        copy = Col([Title("观察建筑形制"), Text("从来源提供的屋檐与门窗细节理解这座建筑。")])
        """, requires: ["Col", "Row", "Image", "Title", "Text"]),
        .init("""
        Equal columns without card surfaces, followed by one deliberately grouped card:
        root = Col([Title("比较两种安排", "lg"), Grid([shortPlan, slowPlan], 2, 160), Card([Title("共同条件"), Text("两种安排都以来源确认的开放时间为准。")], "soft")])
        shortPlan = Col([Title("紧凑安排"), Text("集中观察一个主题。")])
        slowPlan = Col([Title("从容安排"), Text("在同一地点留出更多阅读时间。")])
        """, requires: ["Col", "Grid", "Card", "Title", "Text"]),
        .init("""
        Horizontal browsing of ordinary figure groups; each direct child is one carousel item:
        root = Col([Title("建筑细节", "lg"), Carousel([roof, window], 240)])
        roof = Col([Image("https://example.com/roof.jpg", "屋檐细节", 1.5), Caption("观察屋檐的层次。")], 2)
        window = Col([Image("https://example.com/window.jpg", "窗格细节", 1.5), Caption("观察窗格的结构。")], 2)
        """, requires: ["Col", "Carousel", "Image", "Title", "Caption"]),
        .init("""
        Compose a mixed train/flight itinerary from ordinary components. JourneyLine supplies only the horizontal transport connector; each endpoint, transfer note and booking action remains independently arranged:
        root = Col([Card([Title("去程", "md"), Row([Col([Title("21:00"), Text("A站")]), JourneyLine("train"), Col([Title("22:00"), Text("B站")])]), Caption("次日 · 需换站 · 衔接 10 小时"), Row([Col([Title("08:00"), Text("B机场")]), JourneyLine("flight"), Col([Title("11:00"), Text("C机场")])]), Text("两段分开预订；没有提供总价或总时长。"), Row([Link("预订列车", "/transport/train"), Link("预订航班", "/transport/flight")])])])
        """, requires: ["Col", "Card", "Title", "Row", "JourneyLine", "Caption", "Text", "Link"]),
        .init("""
        Keep outbound and return as separate compositions. JourneyLine expresses only each transport connection; the source quote remains attached to its known scope:
        root = Col([Card([Title("去程", "md"), Row([Col([Title("06:02"), Text("A站")]), JourneyLine("train"), Col([Title("06:52"), Text("B站")])]), Text("来源成人销售价：¥106；具体计价范围按来源定义。"), Link("查看来源行程", sourceURL)]), Card([Title("返程", "md"), Row([Col([Title("19:55"), Text("B站")]), JourneyLine("train"), Col([Title("20:49"), Text("A站")])])])])
        sourceURL = "https://example.com/source?journeyType=round&opaque=keep%3D%3D"
        """, requires: ["Col", "Card", "Title", "Row", "JourneyLine", "Text", "Link"]),
        .init("""
        Supplied coordinates in a street map with category filtering and expansion. Keep selection in the optional label binding:
        root = Col([Map(markers, false, $selected)])
        $selected = ""
        markers = @Each(places, "p", MapMarker(p.title, p.latitude, p.longitude, p.category, "🏛️"))
        places = [{title:"南宋德寿宫遗址博物馆",latitude:30.238678,longitude:120.173273,category:"博物馆"},{title:"胡雪岩旧居（胡雪岩故居）",latitude:30.237273,longitude:120.172906,category:"历史建筑"}]
        """, requires: ["Col", "Map", "MapMarker"]),
        .init("""
        Composed native form: each edit changes the preview, optional details are conditional, and reset is local:
        root = Col([Title("阅读偏好", "lg"), Form([Card([Input($name,"清单名称"), RadioGroup($intent,[{value:"explore",label:"发现新知",description:"保持内容多样"},{value:"focus",label:"聚焦主题",description:"围绕一个问题阅读"}],"阅读方式","list"), SegmentedControl($depth,["简要","均衡","深入"],true), Slider($minutes,5,60,5,"每天阅读","分钟"), Checkbox($pictures,"保留相关配图"), Disclosure("补充偏好",[TextArea($notes,"备注","可选",3)])]), Button("重置时长",@Set($minutes,20),"ghost")]), Card([Caption("实时预览"),Title($name),Text(($intent == "focus" ? "聚焦主题" : "发现新知") + " · " + $depth + " · " + $minutes + "分钟"),Text($pictures ? "配图开启" : "纯文字偏好","sm","muted"),$notes == "" ? null : Text($notes,"sm")],"soft")])
        $name = "我的阅读清单"
        $intent = "explore"
        $depth = "均衡"
        $minutes = 20
        $pictures = true
        $notes = ""
        """, requires: ["Col", "Title", "Form", "Card", "Input", "RadioGroup", "SegmentedControl", "Slider", "Checkbox", "Disclosure", "TextArea", "Button", "Caption", "Text"])
    ]
}
