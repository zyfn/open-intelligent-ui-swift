import Foundation
import OpenUILang

extension IntelligentUILibrary {
    public var specification: LibrarySpec { components.toSpec() }
    public var specificationJSON: String { specification.jsonString() }
    public var systemPrompt: String {
        let generated = components.prompt(PromptOptions(
            additionalRules: [
                "Output only the complete openui-lang program, without a Markdown fence or a JSON wrapper. Use registered components, declared positional arguments and supported functions. State defaults are literals; derived values belong in ordinary variables. Use ASCII identifiers, quoted non-ASCII keys and bracket access. Respect exact case-sensitive source field names.",
                "Organize the answer around the user task: concise conclusion, meaningful groups, then supporting details. Choose one primary presentation for each idea. Keep secondary facts and long explanations in optional details; do not repeat the same entities, caveats or source limitations across text, cards and tables. For follow-ups, show requested updates and briefly refer to unchanged material; do not recreate unrelated interactive sections unless the user requests them.",
                "Compose ordinary content with Col, Row, Grid, Box, Text, Image and Carousel. Use whitespace and alignment for reading; use Card for a real object or coherent group, not every paragraph. Vary structure to fit content rather than reproducing an example page.",
                "Generate Image(src, alt) using required arguments only. Any registered image-search component also takes only its query. The SDK owns framing, crop, radius and image sizes according to layout. Do not emit image proportions or use Box dimensions to override an image frame. Use Col for covers, Row for leading/trailing thumbnails, Grid for tiles and Carousel for a short visual collection. No page numbers or current/total counters.",
                "Keep a figure and its attribution in one compact Col([Image(src,alt), Text([suppliedCredit, Citation(suppliedSources)], \"xs\", \"muted\")], 2). The small supporting line preserves supplied author/license facts; the inline citation is the source entry. Use the surrounding flow for separation from subsequent prose. Use Link for intentional navigation such as an official site or full guide, not a duplicate standalone image-source row. Add references only where supported and useful; do not fabricate attribution or add an empty source entry.",
                "Use the default semantic typography and colors. Title labels real headings; Text is the reading body; Caption is supporting text. Text sizes are xs/sm/md/lg only. Leave body weight at normal; emphasize only short key phrases when useful. Do not wrap headings in Markdown bold or make entire paragraphs semibold. Avoid display headings inside every card, muted primary prose and equivalent solid foreground/background colors. Status backgrounds are soft tints. SVG drawing coordinates are the exception: preserve readable labels and provide native explanatory text for accessibility.",
                "Use Badge for static facts, SegmentedControl for a short view switch, RadioGroup for one choice and Checkbox for independent choices. Group fields by meaning. Bind edits to visible results or an explicit action. Use Form status/error only from real validation or execution feedback. No decorative controls or fabricated progress.",
                "Every enabled Button, IconButton and Pressable needs an explicit action. Never nest interactive controls in a Pressable or Popover trigger. ToAssistant is allowed only when the caller explicitly supports a follow-up request; the SDK provides no assistant or order service. An OpenUrl action navigates, it does not purchase or confirm inventory.",
                "Use ProductCard for supplied purchasable goods or bookable services, including accommodation; use TransportCard for transport. One transport card represents one source journey/direction and only that journey's supplied ordered segments. Do not flatten independent journeys, outbound/return or alternatives into connecting legs; use separate cards and preserve parent quote ownership. Only supplied connection facts justify transfer labels. Preserve known price, images, exact purchase/booking destination and stable entity identity. On later turns, filtering, confirmation or adding a checklist must keep selected entities as cards; use a compact layout if needed and collapse only alternatives. A task checklist supplements the entity card, never replaces it with plain links.",
                "Product and transport price is the supplied amount plus optional source currency and priceNote. Use supplied field definitions for the quote scope; an earlier assistant explanation is not additional source evidence. Correct unsupported scope descriptions instead of repeating them on later turns, keeping the known price unchanged. Do not generate legacy priceText, offers, marketing prefixes or inferred units. Missing conditions do not justify discarding a known amount. A round URL or number of legs does not establish a round-trip total. Never sum, split, reprice, invent stock, ratings or cancellation conditions.",
                "Copy each source URL once into a variable and reuse its exact opaque string, including encoded/compressed values and padding. Never normalize, shorten, decode, repair or remove parts. Keep fields owned by their exact source entity or endpoint. Do not infer elapsed time from local clocks, fees from unknown status codes, missing photos or coordinates. Describe planned amounts as estimates, not actual purchases.",
                "Build Map markers and its internal card carousel from one supplied entity array with stable matching ids. When those places have supplied photos or richer details, include a linked internal Carousel: reuse compact ProductCard for supplied purchasable goods/services or accommodation with known price and destination; ordinary places use Card([Row([Image(src,alt),Col([Title(name),Caption(detail)])])]). Preserve supplied facts and let the SDK own the compact map framing. Derive markers, cards and itemIds from that same array, not separately hand-written copies. Share selected and visibleIds with an outside collection when both are present. visibleIds=null is unfiltered and [] hides all. Keep all markers for filtering. Use built-in marker-only cards only when richer place facts are unavailable. route draws straight connectors; routeIds expresses an actual supplied visit order, not all alternatives or road navigation.",
                "Use stable entity ids for switched, filtered or reordered ListItem/Carousel content. Use explicit bindings for state that must survive unmounting. ListItem.description is a secondary summary; put substantial reading content in children. Timeline times/stages use marker. References attached to a sentence belong in mixed Text([text, Citation(...)]) so they share paragraph flow; standalone source lists remain valid. Do not append sources around consumer cards by default.",
                "The native runtime publishes a source-ordered ready prefix: later siblings do not overtake an unresolved earlier section, Each input or state default. Start with a self-contained introduction and give major reading sections stable named statements. Finish each section's supplied data, complete URLs and derived records next to its component definitions so readiness advances promptly. Explicit null, inactive branches and resolved empty collections do not create pending barriers. The current unfinished text/container can stream; reactive edits may still update existing content.",
                "Examples show syntax and composition only; replace illustrative data with supplied task facts. Project records to component schemas instead of passing rich business objects wholesale. Parser success does not establish source fidelity, legal fields, correct calculations or accessible layout. Preserve source uncertainty concisely.",
                "Use typed calculations: numeric Min/Max do not consume clock strings. Same-date/same-zone zero-padded clocks can be sorted then the owning record selected. FormatDate has no locale argument; its named styles are English, iso is language-neutral. Plural defaults to English. Keep monetary rounding and source duration scope explicit. Flashcard, Celebration, HTML and SVG are for tasks that need them, not decoration."
            ].filter(generationTextIsAvailable), examples: selectedGenerationExamples, toolCalls: false, bindings: true
        ))
        // The pinned upstream template describes its own implicit button action.
        // Our registered Button deliberately requires an explicit action.
        // Reader schemas keep the deprecated field for historical programs;
        // writer-facing declarations expose only the canonical price field.
        let imageSignature = specification.components.first { $0.name == "Image" }?.signature ?? ""
        let writer = imageSignature.isEmpty ? generated : generated.replacingOccurrences(of: imageSignature, with: "Image(src: string, alt: string)")
        let searchSignature = specification.components.first { $0.name == "SearchImage" }?.signature ?? ""
        let imageWriter = searchSignature.isEmpty ? writer : writer.replacingOccurrences(of: searchSignature, with: "SearchImage(query: string)")
        let streamingWriter = imageWriter.replacingOccurrences(of: #"## Hoisting & Streaming \(CRITICAL\)[\s\S]*?(?=## Examples)"#, with: "## Streaming\n\nThe renderer publishes each flow's source-ordered ready prefix. An unresolved earlier section, input collection or state default holds subsequent siblings; it is not interpreted as an intentional null result. Already-ready text can stream before the rest of the program finishes. Explicit null results, inactive branches and resolved empty collections do not create pending barriers. Keep each section's data, complete URLs and derived records together so the next section becomes ready promptly. Original source and chunks remain unchanged. Reactive state edits can update existing content.\n\n", options: .regularExpression)
        return streamingWriter.replacingOccurrences(of: #", priceText\?: (?:string|any)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "visibleIds?: $binding<string[] | any>", with: "visibleIds?: $binding<string[] | null>").replacingOccurrences(
            of: "Buttons without an action automatically send their label to the assistant (equivalent to @ToAssistant(label)).",
            with: "Buttons without an explicit action are disabled. No implicit assistant request is sent."
        )
    }

    /// Omit complete examples/rules that require a Host-excluded component.
    /// Component filtering itself is handled by the upstream library extension.
    var selectedGenerationExamples: [String] { Self.generationExamples.filter(generationTextIsAvailable) }

    private func generationTextIsAvailable(_ text: String) -> Bool {
        !excludedComponentNames.contains { name in
            text.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\b"#, options: .regularExpression) != nil
        }
    }

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
        inputItems = [ListItem("", "", "", [Checkbox($done, "输入步骤", true), Disclosure("说明", [Text("准备输入资料。")])], "input-task")]
        outputItems = [ListItem("输出步骤", "", "", [Disclosure("说明", [Text("查看输出资料。")])], "output-task")]
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
        journey = {id:"connection", legs:[{id:"rail", mode:"train", from:"A站", to:"B站", departureDate:"2026-11-12", arrivalDate:"2026-11-12", departureTime:"21:00", arrivalTime:"22:00", bookingURL:"/transport/train"},{id:"air", mode:"flight", from:"B机场", to:"C机场", departureDate:"2026-11-13", arrivalDate:"2026-11-13", departureTime:"08:00", arrivalTime:"11:00", bookingURL:"/transport/flight"}], connections:[{afterLeg:0, changeStation:true, durationText:"10小时"}], separateTickets:true}
        """,
        """
        Independent outbound/return source journeys are two cards, not a transfer. The parent's quote is shown once without inventing a per-direction split:
        root = Col([Text("来源成人销售价：¥106；具体计价范围按来源定义。"), @Each(journeys,"j",TransportCard({id:j.id,legs:j.segments})), Button("查看原结果",@OpenUrl(sourceURL),"outline")])
        sourceURL = "https://example.com/source?journeyType=round&opaque=keep%3D%3D"
        journeys = [{id:"outbound",segments:[{mode:"train",from:"A站",to:"B站",departureDate:"2026-11-23",arrivalDate:"2026-11-23",departureTime:"06:02",arrivalTime:"06:52",serviceNumber:"T1"}]},{id:"return",segments:[{mode:"train",from:"B站",to:"A站",departureDate:"2026-11-23",arrivalDate:"2026-11-23",departureTime:"19:55",arrivalTime:"20:49",serviceNumber:"T2"}]}]
        """,
        """
        Shared map/card/filter data: all names, coordinates, photos and addresses come from one supplied entity array. Outside collection is optional; if both are needed, share selected and visible ids. The example visitIds are an explicit illustrative visit order, not a road route or an instruction to connect alternatives:
        root = Col([Carousel(cards, 288, 3, $selected, shownIds), Map(markers, true, $selected, 360, [Carousel(cards, 288, 3, $selected, shownIds)], true, $visible, visitIds)])
        $selected = "deshou"
        $visible = null
        allIds = @Each(places, "p", p.id)
        shownIds = $visible == null ? allIds : $visible
        shown = @Each(shownIds, "id", @Find(places, "id", id))
        markers = @Each(places, "p", MapMarker(p.title, p.latitude, p.longitude, p.category, "landmark", p.id))
        cards = @Each(shown, "p", Card([Row([Image(p.image.url,p.image.alt),Col([Title(p.title),Caption(p.address)])])]))
        visitIds = ["deshou", "huxueyan"]
        places = [{id:"deshou",title:"南宋德寿宫遗址博物馆",latitude:30.238678,longitude:120.173273,category:"博物馆",address:"中国浙江省杭州市上城区望江路228-264号(江城路地铁站E口步行460米)",image:{url:"https://img.alicdn.com/imgextra/i1/6000000006632/O1CN01AEaXtv1yrVVKfCqT1_!!6000000006632-2-fliggyimage.png",alt:"南宋德寿宫遗址博物馆实景（FlyAI景点资料图）"}},{id:"huxueyan",title:"胡雪岩旧居（胡雪岩故居）",latitude:30.237273,longitude:120.172906,category:"历史建筑",address:"中国浙江省杭州市上城区元宝街18号",image:{url:"https://img.alicdn.com/imgextra/i4/O1CN01H2nHQX1eMY8l7wyno_!!0-alitrip.jpg",alt:"胡雪岩旧居（胡雪岩故居）实景（FlyAI景点资料图）"}}]
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
