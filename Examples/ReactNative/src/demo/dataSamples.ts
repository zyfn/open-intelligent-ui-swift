import type { GallerySample } from './samples';

const literal = JSON.stringify;

const cartesian = `root = Stack([heading, note, groupedTitle, grouped, stackedTitle, stacked, lineTitle, line, areaTitle, area, horizontalTitle, horizontal], "column", "l")
heading = CardHeader("让数字有自己的形状", "柱状、折线、面积与横向比较")
note = TextContent("轻点图中数据查看当前值。长按图表或使用图内菜单查看完整数值；图例可以切换系列。", "small")
groupedTitle = TextContent("每周收支 · 分组", "large-heavy")
grouped = BarChart(["周一", "周二", "周三", "周四"], [Series("收入", [120, 90, 160, 110]), Series("支出", [-60, -100, -70, -45])], "grouped", "日期", "金额")
stackedTitle = TextContent("变化来源 · 正负分开堆叠", "large-heavy")
stacked = BarChart(["一月", "二月", "三月"], [Series("新订单", [30, 55, 40]), Series("续费", [15, 20, 30]), Series("退款", [-8, -12, -5])], "stacked", "月份", "订单数")
lineTitle = TextContent("两段步行记录 · 自然曲线", "large-heavy")
line = LineChart(["周一", "周二", "周三", "周四", "周五"], [Series("本周", [30, 55, 40, 65, 50]), Series("上周", [25, 38, 45, 40, 60])], "natural", "日期", "分钟")
areaTitle = TextContent("逐日净变化 · 阶梯面积", "large-heavy")
area = AreaChart(["周一", "周二", "周三", "周四"], [Series("净变化", [12, -5, 18, 9])], "step", "日期", "变化")
horizontalTitle = TextContent("不同地点的停留时间", "large-heavy")
horizontal = HorizontalBarChart(["苏堤", "孤山", "湖边书店"], [Series("步行", [45, 25, 20]), Series("休息", [15, 30, 40])], "stacked", "分钟", "地点")
`;

const proportions = `root = Stack([heading, pieTitle, pie, radialTitle, radial, stackedTitle, stacked, radarTitle, radar, scatterTitle, scatter], "column", "l")
heading = CardHeader("比例与关联", "圆环、径向、雷达与散点")
pieTitle = TextContent("旅行预算 · 半圆环", "large-heavy")
pie = PieChart(["交通", "餐饮", "住宿"], [60, 100, 240], "donut", "semiCircular")
radialTitle = TextContent("三段行程的时长", "large-heavy")
radial = RadialChart(["步行", "骑行", "阅读"], [45, 30, 60])
stackedTitle = TextContent("一天的时间分配", "large-heavy")
stacked = SingleStackedBarChart(["移动", "休息", "探索"], [20, 30, 50])
radarTitle = TextContent("两条路线的五个维度", "large-heavy")
radar = RadarChart(["安静", "自然", "方便", "文化", "轻松"], [Series("湖边", [9, 10, 6, 7, 9]), Series("老街", [5, 4, 9, 10, 7])])
scatterTitle = TextContent("距离、时间与停留次数", "large-heavy")
scatter = ScatterChart([ScatterSeries("湖边", [Point(1.2, 24, 2), Point(2.4, 45, 4), Point(3.1, 58, 3)]), ScatterSeries("城区", [Point(0.8, 20, 1), Point(2.1, 50, 5)])], "公里", "分钟")
`;

const editableColumns = [
  { type: 'text', key: 'place', header: '地点', width: 176 },
  { type: 'number', key: 'cost', header: '预算' },
  { type: 'date-single', key: 'date', header: '日期', width: 190 },
  { type: 'select', key: 'status', header: '状态', options: [
    { value: 'planned', label: '计划中' }, { value: 'booked', label: '已确认' },
  ] },
  { type: 'url', key: 'reference', header: '参考链接', width: 240 },
];
const editableRows = [
  { id: 'west-lake', values: ['西湖', 60, '2026-11-20', 'planned', 'https://example.com/lake'] },
  { id: 'bookstore', values: ['湖边书店', 100, '2026-11-21', 'booked', 'https://example.com/books'] },
];

const tables = `root = Stack([heading, readonlyTitle, readonly, editTitle, editor, note], "column", "l")
heading = CardHeader("可以阅读，也可以修改", "原生表格、分页与按列编辑")
readonlyTitle = TextContent("路线速览", "large-heavy")
readonly = Table([Col("地点", ["苏堤", "孤山", "湖边书店"]), Col("停留分钟", [60, 40, 45], "number"), Col("操作", [Button("查看苏堤", @ToAssistant("查看苏堤"), "secondary"), Button("查看孤山", @ToAssistant("查看孤山"), "secondary"), Button("查看书店", @ToAssistant("查看书店"), "secondary")], "action")])
editTitle = TextContent("行程草稿", "large-heavy")
editor = EditableTable("itinerary", ${literal(editableColumns)}, ${literal(editableRows)})
note = TextContent("横向滑动查看各列。修改后选择 Save Changes，会保存本条消息的字段并发送宿主动作；此离线示例只记录动作，不向远端保存。", "small")
`;

const boundaries = `root = Stack([heading, emptyTitle, empty, zeroTitle, zero, negativeTitle, negative, signedTitle, signed], "column", "l")
heading = CardHeader("边界数据也应可解释", "空数据、零值与负数")
emptyTitle = TextContent("没有记录时", "large-heavy")
empty = LineChart([], [])
zeroTitle = TextContent("比例合计为零时", "large-heavy")
zero = PieChart(["待安排", "已安排"], [0, 0], "donut")
negativeTitle = TextContent("比例数据包含负数时", "large-heavy")
negative = PieChart(["收入", "退款"], [20, -5])
signedTitle = TextContent("相同负数可以放在数轴中比较", "large-heavy")
signed = BarChart(["本次"], [Series("收入", [20]), Series("退款", [-5])])
`;

export const dataSamples: readonly GallerySample[] = [
  { id: 'cartesian-charts', label: '趋势图表', title: '趋势与正负数', source: cartesian },
  { id: 'proportion-charts', label: '比例图表', title: '比例与关联', source: proportions },
  { id: 'tables', label: '表格', title: '阅读与编辑表格', source: tables },
  { id: 'data-boundaries', label: '数据边界', title: '空值与负数', source: boundaries },
];
