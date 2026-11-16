export type GallerySample = Readonly<{ id: string; label: string; title: string; source: string }>;
const literal = JSON.stringify;

const reading = `root = Stack([heading, photo, credit, intro, divider, details], "column", "l")
heading = CardHeader("给旅程留一点空白", "一篇用于检查原生排版的离线短文")
photo = Image("夕阳下的杭州西湖，湖面与远山", "asset://west-lake")
credit = TextContent(${literal('摄影：[Morio](https://commons.wikimedia.org/wiki/File:West_Lake_(Hangzhou)_sunset_2016_January.jpg) · [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)')}, "small")
intro = TextContent(${literal('## 慢下来，才能看见\n\n有些时刻不需要赶路。沿着湖岸走一小段，找一个能看见水面的地方，把接下来的一小时留给自己。\n\n这是一段**示例内容**，用来检查中文长段落、*强调*与链接在原生界面里的阅读节奏。')})
divider = Separator()
details = TextContent(${literal('### 一份轻一点的清单\n\n- 带一本翻到一半的书\n- 记录三种不同的声音\n- 给晚风留出时间\n\n> 留白也是内容的一部分。\n\n| 片刻 | 留意什么 |\n| :--- | :--- |\n| 走路 | 光线与树影 |\n| 坐下 | 水面与远山 |\n\n`TextContent` 在这里呈现原生 Markdown；图片使用仓库已有素材，不依赖远程加载。')})
`;

const interaction = `root = Stack([heading, description, nameLabel, nameField, emailLabel, emailField, preview, actions, note], "column", "l")
$name = ""
$email = ""
heading = CardHeader("让输入留在原处", "绑定、校验、动作与恢复")
description = TextContent("填入信息后，可以卸载再恢复这条消息，检查输入是否保留。")
nameLabel = TextContent("称呼", "small-heavy")
nameField = Input("name", "至少两个字符", "text", {required: true, minLength: 2}, $name)
emailLabel = TextContent("邮箱", "small-heavy")
emailField = Input("email", "name@example.com", "email", {required: true, email: true}, $email)
preview = TextContent("你好，" + $name, "large-heavy")
clear = Button("清空输入", @Reset($name, $email), "secondary")
continue = Button("记录动作", @ToAssistant("继续", {name: $name, email: $email}))
actions = Stack([clear, continue], "row", "s")
note = TextContent("这里只演示字段反馈和宿主事件。动作会记录在下方，不会提交资料或调用远程服务。", "small")
`;

// Several independent statements exercise unresolved forward references and
// transport boundaries. This is sample content, not a second protocol parser.
const sections = Array.from({ length: 32 }, (_, index) => {
  const body = `### ${String(index + 1).padStart(2, '0')} · 内容在继续\n\n流式界面需要保留正在阅读的位置，也需要保留已经输入的内容。这一段重复的长文用于观察增量更新、滚动与消息离开屏幕后的恢复。\n\n**可检查的细节**：中文换行、段落留白、较长的英文片段 \`streaming_document_identity_${index + 1}\`，以及系统字体放大之后的阅读。`;
  return `part${index} = TextContent(${literal(body)})`;
});
const longReading = `root = Stack([heading, ${sections.map((_, i) => `part${i}`).join(', ')}, code, table], "column", "l")
heading = CardHeader("把一段内容读完", "32 段离线长文 · 可流式回放")
${sections.join('\n')}
code = TextContent(${literal('```typescript\nconst message = createMessageController("long-reading");\nconst handle = message.begin();\nmessage.append(handle, "root = TextContent(\\"你好\\")");\nmessage.complete(handle);\n```')})
table = TextContent(${literal('| 检查项 | 预期行为 | 观察方式 |\n| :--- | :--- | :--- |\n| 窄屏排版 | 长代码和表格可横向滚动 | 横向拖动内容区域 |\n| 流式停止 | 冻结预览，不继续响应控件 | 点击停止后观察 |\n| 消息恢复 | 已保存字段从宿主恢复 | 卸载后重新显示 |')})
`;

export const samples: readonly GallerySample[] = [
  { id: 'reading', label: '阅读', title: '阅读与图片', source: reading },
  { id: 'interaction', label: '交互', title: '输入与动作', source: interaction },
  { id: 'long-reading', label: '长文', title: '长内容与流式', source: longReading },
];
