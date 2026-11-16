import type { GallerySample } from './samples';

const form = `root = Stack([CardHeader("把信息填完整", "原生字段、整表校验与重置"), form], "column", "l")
$name = ""
$email = ""
$notes = ""
$city = ""
form = Form("contact", buttons, [name, email, city, notes])
name = FormControl("称呼", Input("name", "至少两个字符", "text", {required: true, minLength: 2}, $name), "这是消息内的本地字段。")
email = FormControl("邮箱", Input("email", "name@example.com", "email", {required: true, email: true}, $email))
city = FormControl("目的地", Select("city", [SelectItem("hangzhou", "杭州"), SelectItem("chengdu", "成都"), SelectItem("xiamen", "厦门")], "选择城市", {required: true}, $city))
notes = FormControl("补充说明", TextArea("notes", "写下你的偏好", 4, {maxLength: 300}, $notes), "最多 300 个字符；支持原生多行编辑。")
buttons = Buttons([Button("记录资料", @ToAssistant("记录资料", {name: $name, email: $email, city: $city, notes: $notes}), "primary"), Button("重置表单", @Reset($name, $email, $city, $notes), "secondary")], "row")
`;

const choices = `root = Stack([CardHeader("选择适合你的方式", "单选、多选、开关、标签与选项卡"), Label("旅程设施"), facilities, Label("座位偏好"), seats, Label("消息提醒"), reminders, Label("感兴趣的主题"), topics, Label("阅读外观"), appearance, submit], "column", "l")
$facilities = {wifi: true, breakfast: false, parking: false}
$seat = "window"
$reminders = {email: true, push: false}
facilities = CheckBoxGroup("facilities", [CheckBoxItem("无线网络", "旅途中保持连接", "wifi", true), CheckBoxItem("早餐", "从容开始一天", "breakfast"), CheckBoxItem("停车位", "适合自驾出行", "parking")], null, $facilities)
seats = RadioGroup("seat", [RadioItem("靠窗", "看沿途风景", "window"), RadioItem("靠过道", "方便走动", "aisle")], "window", null, $seat)
reminders = SwitchGroup("reminders", [SwitchItem("邮件提醒", "重要信息发送到邮箱", "email", true), SwitchItem("推送提醒", "行程开始前提醒", "push")], "card", $reminders)
topics = Chips("topics", "multiple", [ChipItem("walking", "散步"), ChipItem("food", "美食"), ChipItem("museum", "博物馆"), ChipItem("closed", "暂未开放", null, true)], null, ["walking"])
appearance = OptionCards("appearance", "single", [OptionCard("quiet", "安静阅读", "减少打扰，专注内容"), OptionCard("rich", "丰富浏览", "更多图片与信息")], null, "quiet")
submit = Button("记录这些选择", @ToAssistant("记录选择"))
`;

const dates = `root = Stack([CardHeader("留出一段时间", "原生日期选择与多个数值滑块"), Label("旅行时间"), dates, Label("到店日期"), arrival, budget, intensity, preview, reset], "column", "l")
$dates = {from: "2026-12-01", to: "2026-12-07"}
$arrival = "2026-12-01"
$budget = [25, 75]
$intensity = [4]
dates = DatePicker("旅行时间", "range", {required: true}, $dates)
arrival = DatePicker("到店日期", "single", null, $arrival)
budget = Slider("budget", "discrete", 0, 100, 5, [25, 75], "预算范围", {min: 0, max: 100}, $budget)
intensity = Slider("intensity", "continuous", 0, 10, null, [4], "活动强度", null, $intensity)
preview = TextContent("拖动滑块、选择日期后，可卸载并恢复消息检查字段。日期保存为 ISO 字符串，范围使用 from / to。", "small")
reset = Button("恢复示例值", @Reset($dates, $arrival, $budget, $intensity), "secondary")
`;

export const formSamples: readonly GallerySample[] = [
  { id: 'form', label: '表单', title: '整表验证与重置', source: form },
  { id: 'choices', label: '选择', title: '全部选择控件', source: choices },
  { id: 'dates', label: '日期滑块', title: '日期范围与数值选择', source: dates },
];
