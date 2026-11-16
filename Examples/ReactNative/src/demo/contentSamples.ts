import type { GallerySample } from './samples';
const literal = JSON.stringify;

export const contentSamples: readonly GallerySample[] = [
  {
    id: 'content-svg', label: '图形', title: '原生矢量图与预览',
    source: `root = Stack([SVG(${literal('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 160"><rect x="10" y="10" width="300" height="140" rx="16" fill="#e8f1fb"/><circle cx="80" cy="80" r="36" fill="#3478f6"/><text x="144" y="88" font-size="24" fill="#222">Hello SVG</text></svg>')}, null, "圆形与文字示例")])`,
  },
  {
    id: 'content-reading', label: '内容', title: '正文、提示与代码',
    source: `root = Stack([heading, markdown, note, notification, reveal, code], "column", "l")
$notice = false
heading = InlineHeader("把信息说清楚", "内容组件保持自己的阅读层次。")
markdown = MarkDownRenderer(${literal('### 一份轻量的行程\n\n早上沿湖散步，午后留给**书店与咖啡**。\n\n- 可以慢一点\n- 也可以临时改变计划\n\n[查看说明](https://example.com/guide)')}, "clear")
note = TextCallout("neutral", "一条补充", "提示内容不会自动增加大标题。")
notification = Callout("success", "已经保存", "此提示会在三秒后关闭。", $notice)
reveal = Button("显示短提示", @Set($notice, true), "secondary")
code = CodeBlock("typescript", ${literal('const journey = { city: "杭州", days: 2 };\nconsole.log(journey.city);')})`,
  },
  {
    id: 'content-labels', label: '文字', title: '文字、标签与指标',
    source: `root = Stack([line, emphasis, icon, tags, tag, summary, metric, price], "column", "l")
line = Text("text", "给每一段内容合适的层次", "可选的说明文字", "text", "sm")
emphasis = BoldText("number", "12,840", "+8.2% 较上月", "metric", "md")
icon = Icon("map-pin", "navigation")
tags = TagBlock(["周末", "城市漫步", "不用赶路"], "sm")
tag = Tag("可预约", Icon("circle-check"), "md", "success")
summary = IconText(Icon("coffee"), "soft", "m", "巷口咖啡", "步行约十分钟", false, "horizontal")
metric = MetricIndicatorInline("18,420", "本周浏览", {direction: "up", value: 8.4})
price = MetricIndicatorWithStrikethrough("¥248", "两人套餐", "¥298", {direction: "down", value: 16.8})`,
  },
  {
    id: 'content-images', label: '图片', title: '图片与原生预览',
    source: `root = Stack([photo, thumbnail, banner, gallery], "column", "l")
photo = ImageBlock("asset://west-lake", "夕阳下的西湖")
thumbnail = ImageText("asset://west-lake", "湖面缩略图", "沿湖散步", "一张小图也能说明地点", false, "horizontal", 48)
banner = ImageTextLarge("asset://west-lake", "西湖横幅", "让傍晚慢下来", "图片与正文使用同一资源策略。", true)
gallery = ImageGallery([{src: "asset://west-lake", alt: "西湖第一张", details: "傍晚的湖面与远山。"}, {src: "asset://west-lake", alt: "西湖第二张", details: "同一资源可拥有独立的预览说明。"}])`,
  },
  {
    id: 'content-lists', label: '列表', title: '信息列表与后续问题',
    source: `root = Stack([facts, steps, places, followups], "column", "l")
facts = EntityList([{left: "地点", right: "杭州西湖"}, {left: "预计费用", right: "¥128", rightVariant: "number"}], "default", {left: "周末计划", right: "两人"}, {left: "合计", right: "¥128", rightVariant: "number"})
steps = ListBlock([ListItem("上午沿湖散步", "从断桥附近出发"), ListItem("午后逛书店", "保留一点空闲", null, "继续了解", @ToAssistant("推荐附近书店"))], "number", "default")
places = ListBlock([ListItem("西湖日落", "带上相机", {src: "asset://west-lake", alt: "西湖缩略图"})], "image", "small")
followups = FollowUpBlock([FollowUpItem("附近还有什么值得去的地方？"), FollowUpItem("帮我把行程压缩到半天")])`,
  },
];

export const cardSamples: readonly GallerySample[] = [
  {
    id: 'cards-snippet', label: '摘要卡', title: '紧凑摘要卡片',
    source: `root = Stack([cards])
cards = SnippetCardBlock([first, second], "grid", true, @ToAssistant("查看这项服务"), 12)
first = SnippetCardItem("walk", IconText(Icon("footprints"), "soft", "m", "城市漫步", "慢慢走一小时"), Text("number", "¥0"))
second = SnippetCardItem("lake", ImageText("asset://west-lake", "湖边", "湖畔小坐", "留给傍晚"), BoldText("number", "¥28"))`,
  },
  {
    id: 'cards-overview', label: '概览卡', title: '概览与横向浏览',
    source: `root = Stack([cards])
cards = OverviewCardBlock([first, second], "carousel", true, @ToAssistant("展开这个指标"), "12px")
first = OverviewCardItem("visits", IconText(Icon("users"), "neutral", "m", "本周到访", "城市空间"), MetricIndicatorInline("12,840", "人次", {direction: "up", value: 8.2}))
second = OverviewCardItem("saved", Text("text", "收藏的地点", "下一次出发时再来"), MetricIndicatorInline("24", "个地点"))`,
  },
  {
    id: 'cards-context', label: '情境卡', title: '短内容与提示卡片',
    source: `root = Stack([cards])
cards = ContextCardBlock([first, second], "grid", true, @ToAssistant("继续这个话题"))
first = ContextCardItem("quiet", "今天的留白", "把一小时还给自己。", "gray")
second = ContextCardItem("weather", Tag("适合散步", Icon("sun"), "sm", "success"), "傍晚沿湖走一走。", null, "asset://west-lake", "湖面日落")`,
  },
  {
    id: 'cards-composite', label: '组合卡', title: '组合内容与独立按钮',
    source: `root = Stack([cards])
cards = CompositeCardBlock([first, second], "grid", true, @ToAssistant("查看详情"))
first = CompositeCardItem("lake", ImageTextLarge("asset://west-lake", "西湖", "湖边一日", "给周末留一点空闲", true), [Text("text", "步行、阅读与傍晚日落"), TagBlock(["轻松", "两人"])], {price: BoldText("number", "¥128"), button: Button("选择湖边", @ToAssistant("选择湖边一日"), "secondary")})
second = CompositeCardItem("city", IconText(Icon("coffee"), "soft", "m", "城市半日", "书店与咖啡"), [EntityList([{left: "预计时间", right: "4 小时"}, {left: "步行距离", right: "3 km"}]), MetricIndicatorInline("4.8", "体验评分")], {price: MetricIndicatorWithStrikethrough("¥98", "每人", "¥118"), button: Button("选择城市", @ToAssistant("选择城市半日"), "secondary")})`,
  },
  {
    id: 'cards-visual', label: '视觉卡', title: '以图片组织短内容',
    source: `root = Stack([cards])
cards = VisualCardBlock([first, second], "carousel", true, @ToAssistant("查看这个地点"))
first = VisualCardItem(BoldText("text", "日落前出发", "沿湖走一小段", "text", "md"), "sunset", "asset://west-lake", Tag("傍晚", null, "sm"), "西湖日落")
second = VisualCardItem(BoldText("text", "把脚步放慢", "这一刻没有待办", "text", "md"), "slow", "asset://west-lake", Tag("周末", null, "sm"), "安静的湖面")`,
  },
];
