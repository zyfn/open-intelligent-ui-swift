import SwiftUI
import OpenUILang
import OpenUICore
import OpenIntelligentSwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@main struct GalleryApp: App {
    init() {
        if CommandLine.arguments.contains("--validate-fixtures") {
            let model = GalleryModel()
            guard let state = model.state else { print(model.failure ?? "Gallery initialization failed"); exit(1) }
            var failures: [String] = []
            for fixture in GalleryFixture.allCases {
                state.setSource(fixture.source)
                if !state.errors.isEmpty || state.root == nil { failures.append(fixture.rawValue + ": " + String(describing: state.errors)) }
            }
            print("Validated \(GalleryFixture.allCases.count) Gallery fixtures; failures: \(failures.count)")
            failures.forEach { print($0) }
            exit(failures.isEmpty ? 0 : 1)
        }
    }
    var body: some Scene {
        WindowGroup("Swift Intelligent UI Gallery") {
            GalleryView()
                #if os(macOS)
                .frame(minWidth: 420, minHeight: 520)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 800)
        #endif
    }
}

@MainActor private final class GalleryModel: ObservableObject {
    let library: IntelligentUILibrary?
    let state: OpenUIState?
    let failure: String?
    let images: [String: Image]
    @Published var action = "尚未触发外部动作"
    private var streamTask: Task<Void, Never>?

    init() {
        do {
            let library = try IntelligentUILibrary(imageSearch: IntelligentUIImageSearch { query in
                if query == "加载状态" { try await Task.sleep(nanoseconds: 15_000_000_000) }
                if query == "失败状态" { throw NSError(domain: "GallerySearch", code: 1) }
                guard query == "Nikon D850" || query == "加载状态" else { throw NSError(domain: "GallerySearch", code: 1) }
                return .init(url: "https://upload.wikimedia.org/wikipedia/commons/9/9b/Nikon_DSLR_camera_D850.jpg", alt: "Nikon D850 来源照片")
            })
            let images = try Self.loadImages()
            self.library = library
            self.images = images
            state = library.makeState()
            failure = nil
        } catch {
            library = nil
            state = nil
            failure = String(describing: error)
            images = [:]
        }
        state?.onAction = { [weak self] event in
            if event.type == "CopyToClipboard", case .string(let text) = event.params.first(where: { $0.0 == "text" })?.1 {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text.displayString, forType: .string)
                #else
                UIPasteboard.general.string = text.displayString
                #endif
                self?.action = "已复制代码"
                return
            }
            let value = event.params.first { $0.0 == "url" }?.1
            let url: String = { if case .string(let text) = value { return text.displayString }; return "" }()
            self?.action = "事件：\(event.type) · \(url)"
        }
        if let index = CommandLine.arguments.firstIndex(of: "--program"), CommandLine.arguments.indices.contains(index + 1) {
            do {
                let text = try String(contentsOfFile: CommandLine.arguments[index + 1], encoding: .utf8)
                let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
                state?.setSource(json?["program"] as? String ?? text, streaming: CommandLine.arguments.contains("--stream-suffix"))
                action = "模型生成案例 · " + URL(fileURLWithPath: CommandLine.arguments[index + 1]).lastPathComponent
            } catch {
                state?.setSource(GalleryFixture.layout.source)
                action = "无法读取模型案例：" + error.localizedDescription
            }
        } else { show(GalleryFixture.initial) }
    }
    func appendReviewSuffix() {
        guard let index = CommandLine.arguments.firstIndex(of: "--stream-suffix"), CommandLine.arguments.indices.contains(index + 1), state?.isComplete == false else { return }
        do {
            state?.push(try String(contentsOfFile: CommandLine.arguments[index + 1], encoding: .utf8))
            state?.complete()
            action = "流式后缀已完成"
        } catch { action = "无法读取流式后缀：" + error.localizedDescription }
    }
    func show(_ fixture: GalleryFixture) {
        streamTask?.cancel()
        action = "尚未触发外部动作"
        if fixture == .streaming {
            state?.reset()
            let characters = Array(fixture.source)
            streamTask = Task { @MainActor [weak self] in
                for start in stride(from: 0, to: characters.count, by: 48) {
                    guard !Task.isCancelled else { return }
                    self?.state?.push(String(characters[start..<min(start + 48, characters.count)]))
                    try? await Task.sleep(nanoseconds: 80_000_000)
                }
                guard !Task.isCancelled else { return }
                self?.state?.complete()
            }
        } else { state?.setSource(fixture.source) }
    }

    private static func loadImages() throws -> [String: Image] {
        let files = [
            ("nikon-front", "https://upload.wikimedia.org/wikipedia/commons/9/9b/Nikon_DSLR_camera_D850.jpg"),
            ("nikon-rear", "https://upload.wikimedia.org/wikipedia/commons/4/49/Nikon_DSLR_camera_D850_lateral_rear_view.jpg"),
            ("sony-headphones", "https://upload.wikimedia.org/wikipedia/commons/thumb/1/13/Sony_WH-CH500-40869.jpg/500px-Sony_WH-CH500-40869.jpg")
        ] + ShowcasePrograms.photoResources
        return try Dictionary(uniqueKeysWithValues: files.map { name, source in
            guard let url = GalleryResources.bundle.url(forResource: name, withExtension: "jpg") else {
                throw NSError(domain: "GalleryResources", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "无法加载来源图片：" + name])
            }
            #if os(macOS)
            guard let image = NSImage(contentsOf: url), image.isValid else { throw NSError(domain: "GalleryResources", code: 2) }
            return (source, Image(nsImage: image))
            #else
            guard let image = UIImage(contentsOfFile: url.path) else { throw NSError(domain: "GalleryResources", code: 2) }
            return (source, Image(uiImage: image))
            #endif
        })
    }
}

private enum GalleryFixture: String, CaseIterable, Identifiable {
    case compositionDemo = "智能排版"
    case designRevamp = "设计改造验收"
    case layout = "布局", reading = "阅读", editorial = "图文检索", technical = "技术文章", data = "数据", comparison = "对比", controls = "交互", inputs = "输入", timing = "日期与计时", products = "商品", transport = "交通", timeline = "行程时间线", patterns = "组合模式", mapProducts = "地图与地点", images = "图片", productDetails = "商品布局", imageStates = "图片状态", formFeedback = "表单反馈", streaming = "连续生成", empty = "异常状态", drawing = "图示", platform = "平台内容", functions = "计算", styles = "样式"
    private static let productDefinitions = """
        productA = {id: "nikon-d850", title: "Nikon D850 机身", images: [{url: "https://upload.wikimedia.org/wikipedia/commons/9/9b/Nikon_DSLR_camera_D850.jpg", alt: "Nikon D850 正面"}], specification: "单反相机 · 机身", priceText: "¥9,999", purchaseURL: "/products/nikon-demo?item=camera", sourceURL: "https://commons.wikimedia.org/wiki/File:Nikon_DSLR_camera_D850.jpg"}
        productB = {id: "sony-wh-ch500", title: "Sony WH-CH500 耳机", images: [{url: "https://upload.wikimedia.org/wikipedia/commons/thumb/1/13/Sony_WH-CH500-40869.jpg/500px-Sony_WH-CH500-40869.jpg", alt: "Sony WH-CH500 蓝色耳机"}], specification: "头戴式耳机", priceText: "¥299", purchaseURL: "/products/sony-demo?item=headphones", sourceURL: "https://commons.wikimedia.org/wiki/File:Sony_WH-CH500-40869.jpg"}
        """
    var symbol: String {
        switch self {
        case .compositionDemo: return "rectangle.3.group"
        case .designRevamp: return "checkmark.rectangle"
        case .layout: return "rectangle.3.group"
        case .reading: return "doc.text"
        case .editorial: return "text.below.photo"
        case .transport: return "airplane"
        case .timeline: return "point.3.connected.trianglepath.dotted"
        case .patterns: return "square.stack.3d.up"
        case .technical: return "curlybraces"
        case .comparison: return "tablecells"
        case .data: return "chart.bar"
        case .controls: return "switch.2"
        case .inputs: return "text.cursor"
        case .timing: return "calendar"
        case .products: return "bag"
        case .mapProducts: return "map"
        case .images: return "photo.on.rectangle"
        case .productDetails: return "list.bullet.rectangle"
        case .imageStates: return "photo"
        case .formFeedback: return "checklist"
        case .streaming: return "text.append"
        case .empty: return "exclamationmark.triangle"
        case .drawing: return "scribble.variable"
        case .platform: return "globe"
        case .functions: return "function"
        case .styles: return "paintpalette"
        }
    }
    var id: String { rawValue }
    static var initial: Self {
        guard let index = CommandLine.arguments.firstIndex(of: "--fixture"), CommandLine.arguments.indices.contains(index + 1) else { return .layout }
        return Self(rawValue: CommandLine.arguments[index + 1]) ?? .layout
    }
    var source: String {
        switch self {
        case .compositionDemo: return CompositionDemo.source
        case .designRevamp: return """
        root = Col([
          Title("设计改造 · 人工验收", "lg"),
          Caption("以下均为测试数据。切换语言、深色和大字号后，检查输入、来源原文和局部状态。"),
          Text("普通正文与 **强调文字**"),
          Text(["同字号混排与 **强调文字** ", Badge("来源原文", "info")]),
          Card([Text("第一项仍是显式大字正文", "lg"), Text("次级正文", "sm")]),
          Input($amount, "数值草稿", "number", "尝试输入 1e 或 1,2"),
          Text("已提交值：" + $amount),
          Slider($range, 0, 100, 1, "越界源值", "", [{value:48,label:"临近的较长标记 A"},{value:50,label:"临近的较长标记 B"},{value:52,label:"临近的较长标记 C"}]),
          DatePicker($date, "非法源日期", "2026-01-01", "2026-12-31"),
          Chart("line", [{x:"A",v:0.004},{x:"B",v:null},{x:"C",v:1.23456}], "x", ["v"]),
          Row([Text("首项"), Spacer(), Text("尾项")]),
          Popover("打开并编辑内容", Col([Input($note,"弹层草稿"),Disclosure("详情",[Text("关闭后重开，确认草稿与展开行为。")])])),
          Flashcard("正面来源内容", "背面来源内容"),
          Timer($seconds),
          Button("查看当前状态", @ToAssistant("amount=" + $amount + "; range=" + $range + "; date=" + $date + "; note=" + $note))
        ])
        $amount=100
        $range=150
        $date="2026-02-30"
        $note=""
        $seconds=40000000
        """
        case .editorial: return ShowcasePrograms.editorial
        case .transport: return ShowcasePrograms.transport
        case .timeline: return ShowcasePrograms.timeline
        case .patterns: return ShowcasePrograms.patterns

        case .mapProducts: return ShowcasePrograms.placesMap
        case .images: return """
        root = Col([Title("图片呈现", "lg"), Caption("宽图 · 16:9"), Image("https://upload.wikimedia.org/wikipedia/commons/9/9b/Nikon_DSLR_camera_D850.jpg","相机宽图",1.7778,"md","cover"), Title("横滑画廊", "lg"), Carousel([Image("https://upload.wikimedia.org/wikipedia/commons/9/9b/Nikon_DSLR_camera_D850.jpg","相机正面",1,"md","cover"),Image("https://upload.wikimedia.org/wikipedia/commons/4/49/Nikon_DSLR_camera_D850_lateral_rear_view.jpg","相机背面",1,"md","cover"),Image("https://upload.wikimedia.org/wikipedia/commons/thumb/1/13/Sony_WH-CH500-40869.jpg/500px-Sony_WH-CH500-40869.jpg","耳机",1,"md","cover")],240), Caption("比例、裁切、圆角和大图查看由同一个 Image 组件控制。")])
        """
        case .imageStates: return """
        root = Col([Title("图片状态", "lg"), SearchImage("加载状态", 1), SearchImage("失败状态", 1)])
        """
        case .formFeedback: return """
        root = Col([Title("基本信息", "lg"), Text("填写名称，备注可选。","sm","muted"), Form([Input($name,"名称","text","请输入名称"), $error == "" ? null : Text($error,"sm","danger"), TextArea($note,"备注","添加备注",3), Row([Button("提交",Action([@Set($error,$name == "" ? "请输入名称" : ""),@Set($message,$name == "" ? "" : "演示提交完成")]),"solid"), Button("重置",Action([@Set($name,""),@Set($error,""),@Set($message,"")]),"ghost")],3,"center","start",true)]), $message == "" ? null : Text($message,"sm","success")])
        $name = ""
        $note = ""
        $error = ""
        $message = ""
        """
        case .streaming:
            let paragraphs = (1...24).map { "Text(\"第 \($0) 段：内容逐步到达时，保持阅读位置和已有组件身份。继续向下阅读，检查后续段落到达是否打断当前操作。\")" }
            return "root = Col([Title(\"连续生成\",\"lg\")," + paragraphs.joined(separator: ",") + "])"

        case .reading: return """
        root = Col([Caption("摄影手记"), Title("看见细节，再做选择", "xl"), Text("一台相机是否适合自己，并不只取决于参数。握持习惯、携带场景和愿意投入的时间，同样决定了它会不会经常被拿起来。"), Col([Image("https://upload.wikimedia.org/wikipedia/commons/9/9b/Nikon_DSLR_camera_D850.jpg", "Nikon D850 正面"), Text(["Nikon D850 · 摄影：Wolfgang Moroder / CC BY-SA 3.0 ", Citation([{title:"Nikon D850 照片来源与许可",url:"https://commons.wikimedia.org/wiki/File:Nikon_DSLR_camera_D850.jpg"}])],"xs","muted")],2), Title("从使用场景开始", "lg"), Text("先想一想，照片通常发生在哪里：每天经过的街角，周末的一段路，还是需要提前准备的拍摄。场景越清楚，比较时越容易抓住真正重要的差异。"), Text("把需要核对的信息放在一起，其余细节留到有兴趣时再展开。这样，选择的过程也可以保持从容。"), Quote("真正有价值的装备，是愿意经常带出门的那一件。"), Title("留下两条简单的判断", "lg"), List([ListItem("是否适合日常携带", "把体积、握持和自己的使用习惯一起考虑。"), ListItem("信息是否足够确定", "规格、报价和购买条件分别核对，未知之处保持未知。")], "number")])
        """
        case .technical: return """
        root = Col([Caption("技术笔记"), Title("先说清楚，再给出依据", "xl"), Markdown("好的技术说明从一个清楚的判断开始。正文解释原因，代码和公式提供可核对的依据。\\n\\n## 保持阅读连续\\n\\n- 用标题区分章节\\n- 用段落说明关系\\n- 用链接保留[信息来源](/reading/source)"), Code("let library = try IntelligentUILibrary()", "swift"), Caption("一个明确的入口，连接契约与渲染。"), Title("表达式也属于内容", "lg"), Math("E = mc^2"), Quote("排版为理解服务，而不是让每个区块争夺注意力。"), Table(["表达","用途"],[["正文","解释上下文"],["代码","呈现具体实现"],["公式","描述数量关系"]])])
        """
        case .data: return """
        root = Col([Caption("季度观察 · 演示数据"), Title($kind == "donut" ? "各月收入，占比如何？" : "收入增长快于成本", "xl"), Text($kind == "donut" ? "三个月的收入合计 4.6 万元，其中三月占 40%。" : "三月收入比一月增长约 53%，同期成本增长约 29%。先看整体趋势，再按需核对具体数值。"), SegmentedControl($kind, [{value:"bar",label:"柱状"},{value:"line",label:"折线"},{value:"area",label:"面积"},{value:"donut",label:"占比"}], true), Chart($kind, rows, "月份", ["收入","成本"], "currency", "CNY", false, 260), Caption("金额单位：人民币。所有数值均为固定示例，不代表真实经营记录。")])
        $kind = "bar"
        rows = [{"月份":"一月","收入":12000,"成本":7200},{"月份":"二月","收入":15600,"成本":8100},{"月份":"三月","收入":18400,"成本":9300}]
        """
        case .comparison: return """
        root = Col([Caption("方案比较 · 演示数据"), Title("把重要的差异，放在一起", "xl"), Text("先比较同一维度，再核对每个选项的条件。没有提供的信息保持空白，不用猜测补齐。"), Table(["方案","预算","条件","来源"],[["A","¥4,500","条件待确认",Link("来源 A","/comparison/a")],["B","¥6,000","条件待确认",Link("来源 B","/comparison/b")],["C","¥7,200","条件待确认",Link("来源 C","/comparison/c")]]), Caption("表格保留统一顺序；来源入口与各行数据一一对应。")])
        """
        case .timing: return """
        root = Col([Title("日期与渐进交互", "lg"), DatePicker($date, "日期", "2026-01-01", "2026-12-31"), Text("已选：" + $date), Timer($seconds, "倒计时"), Popover("查看说明", "原生弹出层保留操作上下文。"), Flashcard("什么负责运行时状态？", "OpenUI Swift。", "点击查看答案"), Celebration($seconds == 0), Form([Input($note,"记录"), Button("发送记录", @ToAssistant("查看记录", {note:$note}), "outline")])])
        $date = "2026-11-03"
        $seconds = 5
        $note = ""
        """
        case .drawing: return """
        root = Col([Title("用图示说明关系", "lg"), Slider($offset,0,40,1,"移动距离"), Svg([Rect(10,25,100,60,"surface","info",2,1,12), SvgText("输入",60,60,16,"ink","middle","medium"), Line(110,55,190,55,"muted",2), G([Circle(240,55,36,"info"), SvgText("结果",240,60,16,"white","middle","semibold")], "translate(" + $offset + " 0)")], "0 0 340 120", null, 180), Caption("拖动滑块，图形跟随状态更新。SVG 使用隔离的本地排版桥接。"), Carousel([Card([Text("第一项")]),Card([Text("第二项")]),Card([Text("第三项")])],200,3)])
        $offset = 0
        """
        case .platform: return """
        root = Col([Title("平台能力与外部资源", "lg"), Caption("图片搜索使用固定测试适配器；地图底图由 MapKit 提供。"), SearchImage("Nikon D850",2,"md","contain"), Map([MapMarker("南宋德寿宫遗址博物馆",30.238678,120.173273),MapMarker("胡雪岩旧居（胡雪岩故居）",30.237273,120.172906)],false,$place,260), Text("选中：" + $place), Caption("地点坐标来自MapKit查询快照，不代表路线规划。"), HtmlView("<h3>隔离交互</h3><p id='count'>0</p><button onclick='document.getElementById(&quot;count&quot;).textContent=Number(document.getElementById(&quot;count&quot;).textContent)+1'>增加</button>",180,"本地计数器"), YouTube("invalid","无效视频地址验证")])
        $place = "南宋德寿宫遗址博物馆"
        """
        case .functions: return """
        root = Col([Title("可以核对的计算", "lg"), Input($budget,"预算","number"), Text("三人分摊：" + @Join(@Allocate($budget,[1,1,1])," / ")), Text("摄氏转华氏：" + @Convert(20,"c","f")), Text("日期：" + @AddDays("2026-11-03",7)), Table(["统计","结果"], [["平均值",@Stats([10,20,30]).mean],["中位数",@Stats([10,20,30]).median]]), Button("复制分摊", @CopyToClipboard(@Join(@Allocate($budget,[1,1,1])," / ")), "outline")])
        $budget = 100
        """
        case .layout: return """
        root = Col([Title("组件布局", "lg"), Text("缩小窗口观察 Row 换行与 Grid 列数变化。", "sm", "muted"), Row([Box([Text("第一项")], "col", 2, 3, "surface", "md", true, 140), Box([Text("第二项较长的文字")], "col", 2, 3, "surface", "md", true, 140), Box([Text("第三项")], "col", 2, 3, "surface", "md", true, 140)], 3, "start", "start", true), Grid([Card([Title("一", "sm"), Text("内容自然增高，支持较长中文文字。")]), Card([Title("二", "sm"), Text("等宽列")]), Card([Title("三", "sm"), Text("最多三列")])], 3, 180, 3), Box([Text("Box：表面、内边距和边框"), Image("", "图片来源缺失示例", 3, 16, "contain")], "col", 2, 3, "surface", "lg", true)])
        """
        case .controls: return """
        root = Col([Title("绑定与动作", "lg"), Checkbox($selected, "加入比较", true), Text($selected ? "已加入比较" : "尚未加入比较"), Slider($count, 1, 10, 1, "数量", "件"), Text("合计 ¥" + ($count * 12), "lg", "ink", "semibold", false, false, true), Button("重置", @Set($count, 2), "outline", "primary", "md", "minus"), Button("查看来源", @OpenUrl("/products/demo?sku=2"), "solid", "primary", "md", "arrow-up-right", false, true), Button("禁用操作", @Set($count, 9), "soft", "danger", "md", "x", true, true)])
        $selected = false
        $count = 2
        """
        case .styles: return """
        root = Col([Title("标签与选择", "xl"), Text("标签说明状态，选择控件切换内容。", "sm", "muted"), Row([Badge("推荐"),Badge("已确认","success","check"),Badge("待核对","warning")],3,"center","start",true), SegmentedControl($style,["概要","详情"],true), Text($style == "概要" ? "保留重点，按需查看细节。" : "展开内容时，保持同一套文字与间距。"), RadioGroup($preference,["便携","均衡","性能"],"使用偏好","pills"), Title("相同内容，统一节奏", "lg"), SegmentedControl($readingStyle,["Text","Markdown","分块"],true), $readingStyle == "Text" ? Col([Text(paragraphA),Text(paragraphB)]) : $readingStyle == "Markdown" ? Markdown(paragraphA + "\\n\\n" + paragraphB) : Col([Markdown(paragraphA),Markdown(paragraphB)])])
        $style = "概要"
        $preference = "均衡"
        $readingStyle = "Text"
        paragraphA = "先看内容，再看形式。文字、图片与操作保持清楚的层级，让阅读自然向下展开。"
        paragraphB = "相同的正文，无论由独立文字还是富文本呈现，都使用一致的字号、行距与段落节奏。"
        """
        case .inputs: return """
        root = Col([Title("购买偏好", "xl"), Text("调整预算与偏好，在下方查看当前方案。", "sm", "muted"), Input($name, "用途", "text", "输入使用场景"), Input($amount, "预算（元）", "number", "输入金额"), TextArea($note, "补充要求", "可选", 3), Select($delivery, [{value: "standard", label: "普通配送"}, {value: "express", label: "加急配送"}], "配送", "请选择配送"), Label("使用偏好"), SegmentedControl($size, ["便携", "均衡", "性能"], true), RadioGroup($plan, [{value: "basic", label: "简洁", description: "保留主要信息"}, {value: "detail", label: "详细", description: "补充规格和使用条件"}], "信息偏好", "cards"), Title("当前方案", "lg"), Text($name + " · 预算 ¥" + $amount + " · " + $size), Text(($delivery == "" ? "" : $delivery == "standard" ? "普通配送 · " : "加急配送 · ") + ($plan == "basic" ? "简洁信息" : "详细信息"),"sm","muted"), $note == "" ? null : Text($note,"sm","muted"), Button("重置", Action([@Set($name, "日常使用"), @Set($amount, 1200), @Set($note, ""), @Set($delivery, ""), @Set($size, "均衡"), @Set($plan, "basic")]), "ghost")])
        $name = "日常使用"
        $amount = 1200
        $note = ""
        $delivery = ""
        $size = "均衡"
        $plan = "basic"
        """
        case .empty: return """
        root = Col([Caption("异常状态验证"), Title("缺失的信息，保持未知", "xl"), ProductCard({id: "missing", title: "待补充图片与价格的商品", images: []}), Title("空数据", "lg"), Table(["名称","金额"],[]), Chart("bar",[],"月份",["收入"]), Image("", "缺少来源的图片", 2, "md", "contain")])
        """
        case .products: return """
        root = Col([Caption("商品展示 · 演示价格"), Title("横向浏览商品", "xl"), Text("左右滑动，逐项查看商品与购买条件。"), Carousel([ProductCard(productA), ProductCard(productB,"vertical","contain")], 288, 4), Text("图片：W. Moroder · [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/)；R. Spekking · [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)，来自 Wikimedia。价格为测试数据。", "xs", "muted")])
        """ + "\n" + Self.productDefinitions
        case .productDetails: return """
        root = Col([Title("商品布局", "xl"), SegmentedControl($layout, [{value: "vertical", label: "图在上"}, {value: "horizontal", label: "图文横排"}], true), ProductCard(product, $layout), Text("照片：Wolfgang Moroder · [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/)，Wikimedia 缩略图；商家与价格为测试数据。", "xs", "muted")])
        $layout = "vertical"
        product = {id: "nikon-d850-demo", title: "Nikon D850 机身", images: [{url: "https://upload.wikimedia.org/wikipedia/commons/9/9b/Nikon_DSLR_camera_D850.jpg", alt: "Nikon D850 正面"}, {url: "https://upload.wikimedia.org/wikipedia/commons/4/49/Nikon_DSLR_camera_D850_lateral_rear_view.jpg", alt: "Nikon D850 背面"}], specification: "单反相机 · 机身", priceText: "¥9,999", purchaseURL: "/products/nikon-demo?item=camera", sourceURL: "https://commons.wikimedia.org/wiki/File:Nikon_DSLR_camera_D850.jpg"}
        """
        }
    }
}

private enum GalleryResources {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }
}
private struct GalleryView: View {
    @StateObject private var model = GalleryModel()
    @State private var fixture: GalleryFixture? = CommandLine.arguments.contains("--program") ? nil : GalleryFixture.initial
    @State private var appearance = CommandLine.arguments.contains("--dark") ? "深色" : "自动"
    @State private var large = CommandLine.arguments.contains("--accessibility")
    @State private var localeName: String = {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--locale"), args.indices.contains(index + 1),
              ["en", "zh-Hans", "ar"].contains(args[index + 1]) else { return "system" }
        return args[index + 1]
    }()
    @State private var showEvents = false
    @Environment(\.dynamicTypeSize) private var systemType
    @Environment(\.locale) private var systemLocale
    @Environment(\.layoutDirection) private var systemDirection
    private var contentLocale: Locale { localeName == "system" ? systemLocale : Locale(identifier: localeName) }
    private var contentDirection: LayoutDirection {
        localeName == "system" ? systemDirection : localeName == "ar" ? .rightToLeft : .leftToRight
    }
    private var horizontalPadding: CGFloat {
        #if os(macOS)
        return 32
        #else
        return 20
        #endif
    }
    var body: some View {
        Group {
            if CommandLine.arguments.contains("--program") {
                NavigationStack { detail }
            } else {
                NavigationSplitView {
                    List(GalleryFixture.allCases, selection: $fixture) { item in
                        NavigationLink(value: item) { Label(item.rawValue, systemImage: item.symbol) }.tag(item)
                    }
                    .navigationTitle("组件")
                    .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 240)
                } detail: { detail }
            }
        }
        .preferredColorScheme(appearance == "自动" ? nil : appearance == "深色" ? .dark : .light)
        .onChange(of: fixture) { if let value = $0 { model.show(value) } }
    }
    private var detail: some View {
            Group {
                if let library = model.library, let state = model.state {
                    GalleryDocumentView(library: library, state: state, images: model.images,
                                        fixture: fixture, large: large, systemType: systemType,
                                        horizontalPadding: horizontalPadding)
                        .environment(\.locale, contentLocale)
                        .environment(\.layoutDirection, contentDirection)
                } else { Text(model.failure ?? "无法载入组件库").padding() }
            }
            .background(IntelligentUITheme().canvas)
            .navigationTitle(fixture?.rawValue ?? "模型生成案例")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if CommandLine.arguments.contains("--stream-suffix") {
                    ToolbarItem { Button("继续生成") { model.appendReviewSuffix() } }
                }
                ToolbarItem {
                    Menu {
                        Picker("外观", selection: $appearance) { ForEach(["自动", "浅色", "深色"], id: \.self) { Text($0) } }
                        Picker("SDK 文案与方向", selection: $localeName) {
                            Text("跟随系统").tag("system")
                            Text("English").tag("en")
                            Text("简体中文").tag("zh-Hans")
                            Text("العربية · RTL").tag("ar")
                        }
                        Toggle("大字号", isOn: $large)
                        Toggle("显示操作记录", isOn: $showEvents)
                    } label: { Label("显示选项", systemImage: "slider.horizontal.3") }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if showEvents {
                    Text(model.action).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(.bar)
                }
            }
    }
}

private struct GalleryDocumentView: View {
    let library: IntelligentUILibrary
    let state: OpenUIState
    let images: [String: Image]
    let fixture: GalleryFixture?
    let large: Bool
    let systemType: DynamicTypeSize
    let horizontalPadding: CGFloat

    var body: some View {
        document.intelligentUIReadingPosition(enabled: !CommandLine.arguments.contains("--disable-reading-anchors"))
    }
    private var document: some View {
        ScrollView {
            IntelligentUIView(state: state, library: library)
                .intelligentUIImages(images)
                .dynamicTypeSize(large ? .accessibility2 : systemType)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
                .intelligentUIReadingContent()
        }
        .id(fixture)
    }
}
