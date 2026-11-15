# 组件示例

`openui.json` 对应 OpenUI，`openintelligentui.json` 对应 OpenIntelligentUI。文件名沿用既有内部产品标识；界面和新的命令行参数使用产品名称。

每个键是实际注册的组件名称，值包含展示分类、完整 Lang 示例，以及可选的结构/数据子项与父组件说明。Gallery 从真实 `OpenUILibrary.specification` 取得名称、签名和描述，并检查示例键集合与组件目录完全一致。这里不维护第二份组件契约。

目录沿用 OpenIntelligentUI 源码的 `Layout / Content / Controls / DataDisplay / Media`，OpenUI 也按同一目录体系组织对应展示。静态检查逐项核对 OpenIntelligentUI 示例目录与实际组件实现的文件夹归属；不额外发明展示分类。组件用法默认展开，仍可手动收起。

每个组件都可以独立选择。TabItem、Series、MapMarker 等嵌套或数据组件在父组件中展示；Slice 没有独立原生视觉，示例明确说明这一点。图片复用 Images 清单中来源精确匹配的本地素材，不为不同来源伪造图片映射。SearchImage 使用 Gallery 的本地模拟适配器。

OpenUI 的 87 是注册定义数：72 个定义有原生视觉实现，15 个结构/数据定义由父组件消费或保留协议读取，因此不对应 87 种独立控件画面。目录保留全部条目，给结构/数据定义标注“子项”及父组件；不要用重复示例或空视图充当独立视觉能力验收。当前示例组合覆盖全部 87 个名称。

修改组件目录时同步补齐示例；`Tools/check_gallery_catalog.py` 检查资源完整性，`Examples/Gallery/verify.sh` 用真实库验证完整与流式求值。实际外观及交互仍需打开原生 Gallery 检查。
