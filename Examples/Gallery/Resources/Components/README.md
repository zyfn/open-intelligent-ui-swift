# 组件用法

文档版本：1.11 · 更新日期：2026-11-23

`openui.json` 对应 OpenUI，`openintelligentui.json` 对应 OpenIntelligentUI。文件名沿用既有内部产品标识；界面和新的命令行参数使用产品名称。

每个键对应新生成契约中的组件。独立展示的组件填写 `examples`，每个用法包含页内唯一的 `id`、界面标题 `title` 与可执行的 `program`。结构或数据子项填写 `container`，继承父项的分组与全部用法。Gallery 从真实 `OpenUILibrary.specification` 读取名称、签名和描述，并核对 writer 的组件覆盖；仅供历史读取的组件不出现在这个目录。

OpenUI 的分组和顺序来自 [SDK 注册目录](../../../../docs/openui.md#组件目录) 的 `componentGroups`。侧栏合并显示表格与图表、表单与按钮。原目录中未分组的 `FollowUpBlock` 通过示例配置放入「表单与按钮」。OpenIntelligentUI 的独立组件填写与源码目录对应的 `category`。可用相同内容直接比较的形态放在同一用法中，例如 Card 的三种底层容器。图库张数、日期 Tabs、表单校验等需要单独互动的用法，通过当前组件页面切换。

TabItem、StepsItem、MapMarker 等跟随各自的父组件。多个图表共用的 Series 位于「表格与图表」，用同一组数据对照柱状图与折线图。Slice 的页面展示数据定义。图片复用 Images 清单中来源精确匹配的本地素材。SearchImage 使用 Gallery 的本地模拟适配器。

OpenUI 有 88 个注册定义，OpenIntelligentUI 的 Gallery writer 有 60 个（包括已注入模拟图片服务的 `SearchImage`）。图文由基础布局组件组合表达：上图下文使用 `Col`，左图右文使用 `Row`。普通图文直接写 `Row([Image(...), Col([...])])`，图片尺寸和对齐交给 Row 的默认媒体布局；`SearchImage` 页面展示同样的并排组合。`Grid` 对照固定列数与设置 `minChildWidth` 后随容器减少列数的效果，并展示不带 Card 的图文集合；`Box` 展示省略背景色但保留边框的透明分组。普通 Tabs 和日期 Tabs 各有一项用法，`TabItem` 共用这两项。点流式播放后可以观察首项和手选项如何随正文追加保持选中。

修改组件目录时同步补齐示例；`Tools/check_gallery_catalog.py` 检查资源完整性，`Examples/Gallery/verify.sh` 用真实库验证完整与流式求值。实际外观及交互仍需打开原生 Gallery 检查。

`Map` 提供地点标记、道路路线、预选绑定、字面量初值和同名标记五个用法。绑定示例用普通 Text 显示当前 label，检查点选后的联动以及筛选、全览不改写业务值；展开后点选标记会关闭展开。同名用法明确标为演示，复用既有坐标检查两个点均保留。地图高度随视口适配，不添加地点卡片或详情面板。各用法仅使用已有坐标，参数及平台边界见[地图说明](../../../../docs/openintelligentui.md#25-地图与平台桥接)。

`Title` 对照六档尺寸并展示开篇、章节和对象标题的实际分工。`Caption` 的图注用法把图片与说明放进显式紧凑 Col，下一节独立分组。`JourneyLine` 展示端点加连接线的原子组合，以及 flight、train、bus、taxi 四种方式；时间、站点、价格与操作继续属于普通兄弟组件。
