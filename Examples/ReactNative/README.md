# React Native · OpenUI Gallery

文档版本：1.1 · 更新日期：2026-11-16

这个私有 Expo 工程复用官方 OpenUI parser、Store 和 Renderer，在同一份组件契约上实现自己的 iOS / Android 原生呈现。当前启用 7 个组件，提供离线 Gallery、流式生命周期、字段恢复、原生 Markdown/图片和明暗主题；尚不是已发布的 RN SDK。

架构与源码职责见[唯一架构文档](../../docs/architecture.md#7-react-native-基础验证分支)，组件能力和边界见 [OpenUI](../../docs/openui.md#react-native-验证子集)，实际验证结果见[验证说明](../../docs/validation-and-security.md#5-react-native-基础验证)。

## 启动

建议 Node 22.13+ 的 22.x 系列（CI 使用 22.x）；锁定的依赖也已在 Node 24.22.1 验证。iOS 原生构建需要 macOS / Xcode 26.2+；Android 使用 JDK 17、Android SDK 36、Build Tools 36.0.0、NDK 27.1.12297006。运行页面还需要各自的模拟器或设备。

~~~sh
cd Examples/ReactNative
npm ci
npm run ios
# 或
npm run android
~~~

也可以 `npm start` 后用匹配 Expo SDK 55 的 development build 打开。原生工程由 Expo 生成，`ios/`、`android/` 不入库；修改 native 插件或原生配置后需要重新构建。`expo-system-ui` 和 `userInterfaceStyle: automatic` 使系统外观配置在原生工程生效；这与页面内的主题切换共同验证。

依赖由 `package.json` 和 `package-lock.json` 固定。`react-dom` 是上游依赖引入的工具依赖，override 让它与 React 保持同版本；应用入口使用官方 `react-native` 导出，不使用 DOM 渲染。Metro 只额外观察已有 Gallery 图片目录，不修改模块导出条件或引用私有 dist 入口。

## 页面检查

1. 阅读样例检查中文标题、Markdown、代码/宽表和本地照片；链接只产生宿主事件，不直接打开网页。图片应有加载占位、alt、失败提示和重试。
2. 添加“交互”样例，输入称呼与邮箱，离开字段检查必填/格式反馈；“清空输入”使用官方 Reset，“记录动作”只展示宿主事件，不表示整表校验通过或业务提交成功。
3. 编辑后“卸载消息”再“恢复消息”，检查字段值；切换浅色/深色也应保留字段。焦点、选区和 IME 草稿不在恢复保证内。
4. “流式回放”开始新 epoch 并清空该消息旧字段；“停止”应保留已接收内容并冻结交互，再次回放不接受旧流和旧回调。
5. 添加“长文”样例，检查 32 段内容的滚动、宽表/代码横向拖动，以及其他消息离屏再回来后的字段。最新样例排在上方，最多保留最近 8 条；“清空历史”保留最新一条，删除的宿主记录会释放。
6. 开启系统大字号、横屏和屏幕阅读器，检查触摸区、阅读顺序、中文换行和键盘遮挡；这些原生行为不能用 Jest 的宿主 mock 代替。

页面使用本地固定输入，无模型密钥或真实后端。样例图片复用 `Examples/Gallery/Resources/Images/west-lake.jpg`；署名和来源沿用该目录的 `catalog.json`。`src/fixture.ts` 保持原始基础 fixture，扩展样例放在 `src/demo/samples.ts`，不改历史模型输出。

## 接入现有宿主

源码入口为 `src/index.ts`。宿主在消息创建时持有一个 controller，并把同一个对象交给视图：

~~~tsx
import { createMessageController, OpenUIDocument, library } from './src';

// 在宿主消息创建时执行，不放进 React render 或布局测量。
const message = createMessageController('message-42');
const handle = message.begin();

// 网络层使用创建这一轮时拿到的 handle。
message.append(handle, 'root = TextContent("你好")');
message.complete(handle);

// 组件由宿主正常挂载；原始 Lang 不需要转换成另一种 AST。
<OpenUIDocument message={message} library={library} onAction={handleAction} />;
~~~

传输失败调用 `message.fail(handle, error)`，用户停止调用 `message.interrupt(handle)`。视图卸载保留 controller；永久删除消息时 `message.dispose()`。每次开始新文档重新取得 handle，旧 handle 不可继续写入。

宿主可用 `NativeThemeProvider` 覆盖 token，用 `NativeContentProvider` 提供图片 resolver 和错误回调。默认图片仅接受 HTTPS；本地静态资源需由宿主显式映射。`onAction` 的业务异步结果由宿主自行处理，当前官方 trigger 不会等待该回调返回的任意 Promise；按钮的 busy 状态不代表远程事务已经受控。

## 为模型导出当前契约

~~~sh
npm run contract
# 可选：指定已有宿主需要的输出目录
npm run contract -- /absolute/output/path
~~~

输出 `spec.json`、`prompt.txt` 和 `manifest.json`，包含实际启用的 7 组件、schema、上游 revision、catalog 哈希与输出哈希。这个命令使用普通 Node 和同一 authoring 路径，不导入 React Native。当前 prompt 明确禁用未接入的工具调用与完整表单容器。

## 本地验证

~~~sh
npm run catalog:check
npm test
npm run test:integration
npm run typecheck
npm run contract
npm run export:ios -- --max-workers 2
npm run export:android -- --max-workers 2
~~~

修改已有权威组件目录后运行 `npm run catalog` 更新派生资源。Node 测试覆盖契约与消息控制；Jest/Expo 测试实际挂载已安装的官方 native Renderer 与真实核心，只模拟原生宿主能力。

导出产物写入根目录忽略的 `outputs/react-native/`。独立 [React Native CI](../../.github/workflows/react-native.yml) 在此功能分支 push 时依次验证 JS/契约，再构建 Android Release 测试 APK 和 iOS Simulator Release，并保存日志与产物。Android 使用开发签名，产物不代表可直接发布。CI 配置存在不等于实际运行成功，结果以验证说明与对应 run 为准。

Metro 导出不代替 Xcode / Gradle 原生编译；原生编译也不代替设备交互、截图对照或 Release 性能测量。
