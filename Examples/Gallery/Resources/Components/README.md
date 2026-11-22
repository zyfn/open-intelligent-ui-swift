# 组件用法

文档版本：1.7 · 更新日期：2026-11-22

`openui.json` 对应 OpenUI，`openintelligentui.json` 对应 OpenIntelligentUI。文件名沿用既有内部产品标识；界面和新的命令行参数使用产品名称。

每个键对应实际注册的组件。独立展示的组件填写 `examples`，每个用法包含页内唯一的 `id`、界面标题 `title` 与可执行的 `program`。结构或数据子项填写 `container`，继承父项的分组与全部用法。Gallery 从真实 `OpenUILibrary.specification` 读取名称、签名和描述，并核对注册项覆盖。

OpenUI 的分组和顺序来自 [SDK 注册目录](../../../../docs/openui.md#组件目录) 的 `componentGroups`。侧栏合并显示表格与图表、表单与按钮。原目录中未分组的 `FollowUpBlock` 通过示例配置放入「表单与按钮」。OpenIntelligentUI 的独立组件填写与源码目录对应的 `category`。可用相同内容直接比较的形态放在同一用法中，例如 Card 的三种底层容器。图库张数、日期 Tabs、表单校验等需要单独互动的用法，通过当前组件页面切换。

TabItem、StepsItem、MapMarker 等跟随各自的父组件。多个图表共用的 Series 位于「表格与图表」，用同一组数据对照柱状图与折线图。Slice 的页面展示数据定义。图片复用 Images 清单中来源精确匹配的本地素材。SearchImage 使用 Gallery 的本地模拟适配器。

OpenUI 有 88 个注册定义，OpenIntelligentUI 有 61 个。普通 Tabs 和日期 Tabs 各有一项用法，`TabItem` 共用这两项。点流式播放后可以观察首项和手选项如何随正文追加保持选中。

修改组件目录时同步补齐示例；`Tools/check_gallery_catalog.py` 检查资源完整性，`Examples/Gallery/verify.sh` 用真实库验证完整与流式求值。实际外观及交互仍需打开原生 Gallery 检查。
