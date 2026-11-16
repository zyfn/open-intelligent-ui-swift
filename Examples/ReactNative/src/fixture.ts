// A local, deterministic stream. It does not call a model or perform business actions.
export const fixture = `root = Stack([heading, divider, body, field, preview, buttons], "column", "l")
$name = ""
heading = CardHeader("同一份协议，两种原生呈现", "OpenUI · React Native 基础验证")
divider = Separator()
body = TextContent("这条消息由官方 OpenUI 运行时解析。输入、动作与流式内容共用一份组件契约。")
field = Input("name", "输入你的名字", "text", null, $name)
preview = TextContent("你好，" + $name, "large-heavy")
clear = Button("清空", @Set($name, ""), "secondary")
submit = Button("继续", @ToAssistant("继续", {name: $name}))
buttons = Stack([clear, submit], "row", "s")
`;
