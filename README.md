# ClickFlow

**Mouse Automation for macOS**

ClickFlow 是使用 Swift、SwiftUI、AppKit、Quartz、GameController 与少量封装 Carbon API 编写的原生 macOS 输入自动化工具。它提供鼠标/键盘连点、全局鼠标宏、组合宏、全局快捷键和菜单栏控制。

## 功能

- 左键、右键、中键或自定义键盘按键自动重复
- 单击/双击手势，有限次数或持续执行
- 点击间隔与 CPS 双向换算，范围 10 ms–60 s / 0.0167–100 CPS
- 当前鼠标位置或固定 Quartz 全局坐标
- 固定位置模式下可用内置全局快捷键 `⌘⌥X` 获取当前鼠标位置
- 鼠标移动、三键按下/松开、拖动和滚轮录制
- 鼠标宏可选择完整轨迹或只记录点击位置
- 组合宏录制鼠标、键盘，以及 Xbox、DualSense、Switch 等由 GameController 识别的手柄输入
- 鼠标宏和组合宏支持在现有时间轴末尾继续录制；点击界面停止按钮不会把停止按钮本身写入宏
- 约 60 Hz 的鼠标轨迹采样与距离阈值，减少冗余事件
- 0.25×、0.5×、1×、1.5×、2×、4× 宏播放速度
- 单次、指定次数、无限循环与独立循环间隔
- 表格宏编辑、多选删除、顺序调整和撤销
- 可捕获任意按键或组合键的全局快捷键，修改后立即保存并应用
- 菜单栏控制、后台运行和 Emergency Stop
- 简体中文与英文界面

全新安装默认不分配任何“用户操作”全局快捷键。用户可分别设置连点器开/关、鼠标宏录制开/关、播放/停止鼠标宏、组合宏录制开/关，以及播放/停止组合宏；每组对应的开始/停止操作可以共用同一组合键。`⌘⌥X` 是固定位置模式专用的内置保留快捷键。macOS 是否将功能键识别为 F1–F12 仍由“系统设置 > 键盘”中的功能键设置决定。

## 系统与开发要求

- macOS 14 或更新版本
- Xcode 16 或更新版本，Swift 6 模式
- 当前工程启用 Swift 6 严格并发检查
- 默认构建 `arm64`；Release 配置构建 `arm64 + x86_64`

本仓库首次验证使用的是当前机器唯一安装的 **Xcode 27.0 Beta / Swift 6.4**。尚未在同版本稳定版 Xcode 上复验。

## 编译

在 Xcode 中打开 `ClickFlow.xcodeproj`，选择 ClickFlow Scheme 和 My Mac 后运行。当前工作副本使用本机开发团队 `HP5WBFL9G3` 进行 Automatic Signing，以保持 TCC 权限身份稳定；复制到其他开发者机器时请在 Signing & Capabilities 中改为自己的团队。

命令行编译和测试：

```bash
xcodebuild -project ClickFlow.xcodeproj \
  -scheme ClickFlow \
  -configuration Debug \
  -destination 'platform=macOS' \
  build

xcodebuild -project ClickFlow.xcodeproj \
  -scheme ClickFlow \
  -configuration Debug \
  -destination 'platform=macOS' \
  test
```

只检查编译、不签名时可附加 `CODE_SIGNING_ALLOWED=NO`。

## 权限

### Accessibility（辅助功能）

连点器和宏播放通过 `CGEvent` 向系统发送鼠标事件，因此需要辅助功能/事件注入权限。ClickFlow 使用系统预检 API 检测权限；没有权限时不会静默运行，并会提供请求权限和打开系统设置按钮。

授权路径：系统设置 > 隐私与安全性 > 辅助功能。

签名身份、Bundle ID 或应用所在路径变化后，macOS 可能要求重新授权。

### Input Monitoring（输入监控）

鼠标宏与组合宏需要监听其他应用中的鼠标/键盘事件。ClickFlow 不会在启动时提前请求该权限，而是在用户开始录制时按需请求。

授权路径：系统设置 > 隐私与安全性 > 输入监控。

全局快捷键使用 `RegisterEventHotKey`，本身不依赖 Accessibility 或 Input Monitoring。

## App Sandbox

`ENABLE_APP_SANDBOX` 设置为 `NO`。ClickFlow 的核心用途是跨应用监听和注入输入事件；强行沙盒化会给这些系统级自动化能力带来不必要限制和不稳定性。本项目定位为用户自行构建或直接分发的本地工具，而不是当前版本的 Mac App Store 应用。

Hardened Runtime 在工程配置中保持开启。临时 ad-hoc/无签名命令行构建不等同于正式 Developer ID 签名和公证。

## 数据存储与隐私

宏以独立、带 schema 版本的 JSON 文件保存在：

```text
~/Library/Application Support/ClickFlow/Macros/<UUID>.json
~/Library/Application Support/ClickFlow/CombinedMacros/<UUID>.json
```

设置和最近使用记录保存在 UserDefaults。损坏的宏文件不会被删除或改写，应用会跳过它、写入 OSLog 并提示用户。

ClickFlow 默认完全离线：

- 不上传宏或鼠标轨迹
- 不包含 Analytics SDK
- 不包含 Telemetry
- 不发送用户操作记录
- 不访问网络

## 项目架构

- `App/`：应用入口、主状态和自动化互斥协调
- `Models/`：连点器、宏、事件和热键数据模型
- `Services/`：CGEvent、Event Tap、连点、录制、播放、热键、权限、设置和存储
- `Utilities/`：坐标校验、采样、调度逻辑和 OSLog
- `Views/`：分栏、连点器、宏编辑、设置和菜单栏 UI
- `Resources/`：双语资源、Accent Color 和 AppIcon
- `ClickFlowTests/`：纯逻辑单元测试

UI 状态限定在 MainActor。连点器、录制器、播放器和存储使用 actor；Event Tap 的 Core Foundation RunLoop 被限制在单独的线程安全封装中。所有持续任务均保留可取消句柄，Emergency Stop 会取消连点、播放和录制。

## 坐标与多显示器

录制与播放直接使用 `CGEvent.location` 和 `CGDisplayBounds` 的 Quartz 全局 point 坐标，不把 SwiftUI point、Retina backing pixel 和显示像素混用。播放前会检查全部坐标是否位于当前连接显示器的联合区域；显示器布局变化导致坐标越界时会阻止播放，而不会静默修改宏。

## 已知限制

- 组合宏可以记录手柄输入，但 Apple 的公开 GameController API 不提供向其他应用注入手柄事件的能力；因此组合宏播放会还原鼠标和键盘，手柄事件保留在时间轴中但不会被注入。相关读取与后台监听行为依据 [GCController](https://developer.apple.com/documentation/gamecontroller/gccontroller) 和 [shouldMonitorBackgroundEvents](https://developer.apple.com/documentation/gamecontroller/gccontroller/shouldmonitorbackgroundevents)。
- 尚未实现条件触发或脚本。
- 显示器布局变化时不会自动重映射坐标。
- 触控板的滚动惯性/手势阶段不会完整保存，只回放实际水平和垂直滚动增量。
- Carbon 热键的 exclusive 注册可以发现许多系统冲突，但无法保证识别所有采用非独占监听方式的第三方快捷键。
- 系统权限必须由用户手动确认；自动化测试不能代替真实 TCC 授权后的运行验证。
- 工程尚未进行 Developer ID 签名、公证或 DMG 发布。
