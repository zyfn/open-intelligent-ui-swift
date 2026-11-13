import Foundation
import OpenUILang

extension IntelligentUILibrary {
    public var specification: LibrarySpec { components.toSpec() }
    public var specificationJSON: String { specification.jsonString() }
    /// Historical read contract, including compatibility-only fields.
    public var readerSpecification: LibrarySpec { readerComponents.toSpec() }

    public var systemPrompt: String {
        let generated = components.prompt(PromptOptions(
            additionalRules: selectedGenerationRules,
            examples: selectedGenerationExamples, toolCalls: false, bindings: true
        ))
        // RC20's generic template still assumes an implicit Button action.
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
        return zip(Self.generationExamples, Self.exampleRequirements).compactMap { example, requirements in
            requirements.isSubset(of: available) ? example : nil
        }
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
        .init("A supplied price remains its supplied amount, currency and scope. Use source field definitions for quote ownership; an earlier assistant explanation is not additional evidence. Preserve known amounts and corrections on later turns. Never sum, split, reprice, invent stock, ratings or cancellation conditions. Missing conditions do not justify discarding a known amount. Do not infer a round-trip total from a round URL or number of legs."),
        .init("Use the default semantic typography and colors. Leave body weight at normal; emphasize only short key phrases when useful. Do not make entire paragraphs semibold or mute primary prose. Avoid equivalent solid foreground/background colors. Status backgrounds are soft tints. Explicit component parameters express intent; wrapping content does not redefine its meaning."),
        .init("Use typed calculations: numeric Min/Max do not consume clock strings. Same-date/same-zone zero-padded clocks can be sorted then the owning record selected. FormatDate has no locale argument; its named styles are English, iso is language-neutral. Plural defaults to English. Keep monetary rounding and source duration scope explicit."),
        .init("Use Card for a real object or coherent group. Ordinary paragraphs and chapters keep open reading layout. Avoid redundant nested surfaces and display headings inside every card.", requires: ["Card"]),
        .init("Title labels real headings; Text is the reading body; Caption is supporting text. Text sizes are xs/sm/md/lg only. Do not wrap headings in Markdown bold. Choose an explicit supporting role when intended rather than relying on an item's position.", requires: ["Title", "Text", "Caption"]),
        .init("Grid columns retain their declared meaning. Supply the existing minChildWidth when cards or reading columns need a minimum readable width; narrow containers should not depend on guessed screen dimensions.", requires: ["Grid"]),
        .init("Generate Image(src, alt) using required arguments only. The SDK owns framing, crop, radius and image sizes according to layout. Do not emit image proportions or use container dimensions to override an image frame. Describe meaningful content in alt and preserve supplied attribution.", requires: ["Image"]),
        .init("SearchImage(query) uses an explicitly configured caller service. Use its query only; do not add legacy presentation arguments or fabricate a source attribution.", requires: ["SearchImage"]),
        .init("Use Col for covers, Row for leading/trailing thumbnails, Grid for tiles and Carousel for a short visual collection. Choose structure from the information relationship. No decorative page numbers or current/total counters.", requires: ["Image", "Col", "Row", "Grid", "Carousel"]),
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
        .init("Use TransportCard for transport. One card represents one source journey/direction and only its supplied ordered segments. Independent journeys, outbound/return and alternatives remain separate cards. Preserve parent quote ownership. Price and navigation belong in journey fields. An unclear shared quote is preserved once in the first related journey's priceNote, with price empty, rather than duplicated or assigned an unsupported scope. Use supplied fromCity/toCity and full from/to names without trimming or guessing. Only supplied connection facts justify transfer labels. Do not generate legacy priceText or inferred units.", requires: ["TransportCard"]),
        .init("Build Map markers from supplied names, coordinates and optional category/emoji icon. Map.selected holds the clicked marker label. The SDK supplies filtering, fit and expansion. Keep place cards, photos and details outside the map. route draws schematic straight connectors in marker order, not road directions or an inferred visit order.", requires: ["Map", "MapMarker"]),
        .init("ListItem.description is a secondary summary; put substantial reading content in children. Timeline times and stages use the existing marker field.", requires: ["ListItem"]),
        .init("Use Svg for a task that needs a diagram. Preserve supplied drawing coordinates and readable labels; provide equivalent native explanatory text for accessibility. Explicit source colors retain their meaning; semantic colors follow the theme.", requires: ["Svg"]),
        .init("Flashcard is a learning surface, not decoration. Both faces are presentation-only; keep independent interactive operations outside the flipping surface.", requires: ["Flashcard"]),
        .init("Celebration reflects a real supplied state transition only. Do not use it to imply an unconfirmed business result.", requires: ["Celebration"]),
        .init("Use HtmlView only when the task needs its content. It has no native bridge and is not a substitute for registered native controls.", requires: ["HtmlView"])
    ]

    private static let exampleRequirements: [Set<String>] = [
        ["Col", "Title", "Text", "Button"],
        ["Col", "SegmentedControl", "List", "ListItem", "Checkbox", "Disclosure", "Text"],
        ["Col", "ProductCard", "Checkbox", "Button", "Text"],
        ["Col", "Title", "Image", "Text", "Citation", "Row"],
        ["Col", "TransportCard"],
        ["Col", "TransportCard"],
        ["Col", "Map", "MapMarker", "Carousel", "Card", "Row", "Image", "Title", "Caption"],
        ["Col", "Title", "Form", "Card", "Input", "RadioGroup", "SegmentedControl", "Slider", "Checkbox", "Disclosure", "TextArea", "Button", "Caption", "Text"]
    ]

    static let generationExamples: [String] = [
        """
        Earliest record from same-date, same-timezone zero-padded clock strings; preserve source key casing and exact action data:
        root = Col([Title("同日抵达方案", "lg"), Text("最早抵达：" + earliest.arr), Button("查看方案", @OpenUrl(earliest.bookingUrl), "outline")])
        rails = [{id:"a", date:"2026-11-07", zone:"同一输入时区", arr:"10:30", bookingUrl:"https://example.com/journey?itemParams=AA%3D%3D&flag=1"}, {id:"b", date:"2026-11-07", zone:"同一输入时区", arr:"07:49", bookingUrl:"https://example.com/journey?itemParams=BB%3D%3D&flag=1"}]
        earliest = @First(@Sort(rails, "arr", "asc"))
        """,
        """
        Stable logical task keys in a switched list; local disclosure state and explicit business state are separate:
        root = Col([SegmentedControl($stage, ["输入", "输出"]), List($stage == "输入" ? inputItems : outputItems)])
        $stage = "输入"
        $done = false
        inputItems = [ListItem("", "", "", [Checkbox($done, "输入步骤", true), Disclosure("说明", [Text("准备输入资料。")])])]
        outputItems = [ListItem("输出步骤", "", "", [Disclosure("说明", [Text("查看输出资料。")])])]
        """,
        """
        Consumer confirmation keeps the same ProductCard, price and destination; a checklist supplements it:
        root = Col([$confirmed ? ProductCard(product,"compact") : ProductCard(product), $confirmed ? Checkbox($checked,"已核对购买条件") : Button("确认首选",@Set($confirmed,true)), Text("补充规格：" + record.noiseControl)])
        $confirmed = false
        $checked = false
        originalURL = "https://example.com/item?sku=a%2Fb&exParams=keep%3D1&flag=0"
        record = {id:"headphones", title:"耳机", images:[{url:"https://example.com/headphones.jpg",alt:"耳机"}], price:300, currency:"CNY", purchaseURL:originalURL, noiseControl:"输入资料中的规格描述"}
        product = {id:record.id, title:record.title, images:record.images, price:record.price, currency:record.currency, purchaseURL:originalURL}
        """,
        """
        Editorial cover with compact supplied attribution and inline source, then an independent image/text row:
        root = Col([Title("建筑观察", "xl"), Col([Image("https://example.com/cover.jpg", "建筑封面"),Text(["图片：示例摄影者 · 示例许可 ",Citation([{title:"封面图片来源与许可",url:"https://example.com/cover-source"}])],"xs","muted")],2), Row([Image(article.image.url,article.image.alt),Col([Title(article.title),Text(article.body)])])])
        article = {image:{url:"https://example.com/building.jpg", alt:"建筑细节"}, title:"观察建筑形制", body:"从输入资料中的建筑细节展开说明。"}
        """,
        """
        A supplied overnight train/flight connection with separate booking URLs; no invented total:
        root = Col([TransportCard(journey)])
        journey = {id:"connection", legs:[{id:"rail", mode:"train", from:"A站", to:"B站", fromCity:"A市", toCity:"B市", departureDate:"2026-11-12", arrivalDate:"2026-11-12", departureTime:"21:00", arrivalTime:"22:00", bookingURL:"/transport/train"},{id:"air", mode:"flight", from:"B机场", to:"C机场", fromCity:"B市", toCity:"C市", departureDate:"2026-11-13", arrivalDate:"2026-11-13", departureTime:"08:00", arrivalTime:"11:00", bookingURL:"/transport/flight"}], connections:[{afterLeg:0, changeStation:true, durationText:"10小时"}], separateTickets:true}
        """,
        """
        Independent outbound/return source journeys stay in separate cards. An unclear parent quote is preserved once as a note, not moved outside or assigned as a one-way fare:
        root = Col([TransportCard(outbound),TransportCard(return)])
        sourceURL = "https://example.com/source?journeyType=round&opaque=keep%3D%3D"
        outbound = {id:"outbound",legs:[{mode:"train",from:"A站",to:"B站",fromCity:"A市",toCity:"B市",departureDate:"2026-11-23",arrivalDate:"2026-11-23",departureTime:"06:02",arrivalTime:"06:52",serviceNumber:"T1"}],priceNote:"来源成人销售价：¥106；具体计价范围按来源定义",bookingURL:sourceURL}
        return = {id:"return",legs:[{mode:"train",from:"B站",to:"A站",fromCity:"B市",toCity:"A市",departureDate:"2026-11-23",arrivalDate:"2026-11-23",departureTime:"19:55",arrivalTime:"20:49",serviceNumber:"T2"}]}
        """,
        """
        Map presents supplied coordinates; place cards remain ordinary content outside the map. All names, coordinates, photos and addresses come from one supplied entity array:
        root = Col([Map(markers, true, $selected, 360), Carousel(cards, 240, 3)])
        $selected = "南宋德寿宫遗址博物馆"
        markers = @Each(places, "p", MapMarker(p.title, p.latitude, p.longitude, p.category, "🏛️"))
        cards = @Each(places, "p", Card([Row([Image(p.image.url,p.image.alt),Col([Title(p.title),Caption(p.address)])])]))
        places = [{title:"南宋德寿宫遗址博物馆",latitude:30.238678,longitude:120.173273,category:"博物馆",address:"中国浙江省杭州市上城区望江路228-264号(江城路地铁站E口步行460米)",image:{url:"https://img.alicdn.com/imgextra/i1/6000000006632/O1CN01AEaXtv1yrVVKfCqT1_!!6000000006632-2-fliggyimage.png",alt:"南宋德寿宫遗址博物馆实景（FlyAI景点资料图）"}},{title:"胡雪岩旧居（胡雪岩故居）",latitude:30.237273,longitude:120.172906,category:"历史建筑",address:"中国浙江省杭州市上城区元宝街18号",image:{url:"https://img.alicdn.com/imgextra/i4/O1CN01H2nHQX1eMY8l7wyno_!!0-alitrip.jpg",alt:"胡雪岩旧居（胡雪岩故居）实景（FlyAI景点资料图）"}}]
        """,
        """
        Composed native form: each edit changes the preview, optional details are conditional, and reset is local:
        root = Col([Title("阅读偏好", "lg"), Form([Card([Input($name,"清单名称"), RadioGroup($intent,[{value:"explore",label:"发现新知",description:"保持内容多样"},{value:"focus",label:"聚焦主题",description:"围绕一个问题阅读"}],"阅读方式","list"), SegmentedControl($depth,["简要","均衡","深入"],true), Slider($minutes,5,60,5,"每天阅读","分钟"), Checkbox($pictures,"保留相关配图"), Disclosure("补充偏好",[TextArea($notes,"备注","可选",3)])]), Button("重置时长",@Set($minutes,20),"ghost")]), Card([Caption("实时预览"),Title($name),Text(($intent == "focus" ? "聚焦主题" : "发现新知") + " · " + $depth + " · " + $minutes + "分钟"),Text($pictures ? "配图开启" : "纯文字偏好","sm","muted"),$notes == "" ? null : Text($notes,"sm")],"soft")])
        $name = "我的阅读清单"
        $intent = "explore"
        $depth = "均衡"
        $minutes = 20
        $pictures = true
        $notes = ""
        """
    ]
}
