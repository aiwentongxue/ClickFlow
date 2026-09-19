# ClickFlow

**Mouse Automation for macOS**

[简体中文](README.md) | [English](README_EN.md)

ClickFlow 是使用 Swift、SwiftUI、AppKit、Quartz、GameController 与少量封装 Carbon API 编写的原生 macOS 输入自动化工具。它提供鼠标/键盘连点、全局鼠标宏、组合宏、全局快捷键和菜单栏控制。

## 宏循环与分享

鼠标宏和组合宏的「播放设置」均支持播放一次、指定次数和无限循环。次数可直接输入，包含第一次播放；循环间隔不受播放速度影响。每轮结束会释放尚未松开的鼠标和键盘输入。播放时底部显示当前轮次，可暂停、继续或停止。

选中宏后点击「导出宏」，保存 JSON 文件并发给其他用户。对方在任一宏页面点击「导入宏」，应用会识别类型、保存为新副本并选中它，不覆盖同名宏，也不会自动播放。事件、速度、循环模式、次数和间隔都会保留。分享文件上限为 20 MB；损坏、无效或不兼容版本的文件会显示错误。

分享的鼠标坐标是原始屏幕坐标，接收方应根据自己的屏幕和目标窗口调整。组合宏中的手柄事件可分享，但仍受下文的手柄回放限制。

## 功能

- 左键、右键、中键或自定义键盘按键自动重复
- 单击/双击手势，有限次数或持续执行
- 点击间隔与 CPS 双向换算，范围 10 ms–60 s / 0.0167–100 CPS
- 当前鼠标位置或固定 Quartz 全局坐标
- 固定位置模式下可用内置全局快捷键 `⌘⌥X` 获取当前鼠标位置
- 鼠标移动、三键按下/松开、拖动和滚轮录制
- 鼠标宏可选择完整轨迹或只记录点击位置
- 组合宏录制鼠标、键盘，以及 Xbox、DualSense、Switch 等由 GameController 识别的手柄输入
- 组合宏可通过实验性的 CrossOver XInput 代理回放 A/B/X/Y、方向键、肩键、扳机、摇杆、Start/View、L3/R3 与 Guide；ClickFlow 运行期间会把实体手柄透传到同一 XInput 槽位，并按控件与宏状态混合
- “组合宏”下方的“CrossOver 手柄宏安装、诊断与恢复”二级入口可自动识别 CrossOver 版本与容器，对 Aniimo、原神和绝区零使用实机验证配置，并提供按游戏的一键安装、诊断、原 DLL/注册表备份及安全恢复；详见 [CrossOver Windows 游戏手柄宏](docs/CrossOverControllerAdapter.md)
- 鼠标宏和组合宏支持在现有时间轴末尾继续录制；点击界面停止按钮不会把停止按钮本身写入宏
- 约 60 Hz 的鼠标轨迹采样与距离阈值，减少冗余事件
- 0.25×、0.5×、1×、1.5×、2×、4× 宏播放速度
- 按录制时间轴的绝对时间点调度，复杂宏不会累积事件发送耗时而逐步变慢
- 鼠标宏和组合宏支持暂停/继续播放；暂停期间冻结时间轴并安全释放按住的输入
- 单次、指定次数、无限循环与独立循环间隔
- 表格宏编辑、多选删除、顺序调整和撤销
- 可捕获任意按键或组合键的全局快捷键，修改后立即保存并应用
- 菜单栏控制、后台运行和 Emergency Stop
- 简体中文与英文界面

全新安装默认不分配任何“用户操作”全局快捷键。设置页按“连点器”“鼠标宏”“组合宏”分类；用户可分别设置连点器开/关、宏录制开/关、播放、暂停/继续和停止。每组对应的开始/停止操作可以共用同一组合键。`⌘⌥X` 是固定位置模式专用的内置保留快捷键。macOS 是否将功能键识别为 F1–F12 仍由“系统设置 > 键盘”中的功能键设置决定。

## 系统与开发要求

- macOS 14 或更新版本
- Xcode 16 或更新版本，Swift 6 模式
- 当前工程启用 Swift 6 严格并发检查
- 默认构建 `arm64`；Release 配置构建 `arm64 + x86_64`

本仓库首次验证使用的是当前机器唯一安装的 **Xcode 27.0 Beta / Swift 6.4**。尚未在同版本稳定版 Xcode 上复验。

## 首次启动

首次打开 ClickFlow 时，应用会先显示免责声明。在用户点击“同意”之前，ClickFlow 不会初始化宏、全局快捷键或自动化功能。

- 点击“同意”：在本地记录当前免责声明版本并进入主界面。
- 点击“拒绝并退出”：ClickFlow 立即关闭。

如果未来免责声明版本更新，应用可以通过提高内部版本号再次请求确认。

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

## ⚠️ 免责声明

ClickFlow 是一款用于 macOS 的鼠标自动化工具，提供自动点击、鼠标宏录制与回放等功能。

本项目仅用于合法的自动化、效率提升、软件测试、辅助操作和学习研究用途。

使用 ClickFlow 即表示你理解并同意以下事项：

1. **请遵守相关软件和服务的使用规则**

   ClickFlow 可以模拟鼠标输入。某些游戏、在线服务、考试系统、办公系统或其他第三方软件可能禁止或限制自动化工具、宏或模拟输入。

   用户有责任在使用前确认目标软件或服务的用户协议、服务条款以及相关规定。因使用 ClickFlow 导致账号限制、封禁、数据损失或其他后果，由用户自行承担。

2. **请勿用于恶意或违法用途**

   请勿使用 ClickFlow 从事未经授权的自动化操作、破坏系统正常运行、规避安全机制、作弊、骚扰他人或其他违反法律法规及第三方服务规则的行为。

3. **自动化操作存在风险**

   鼠标宏或自动点击可能因坐标变化、窗口位置变化、显示器配置变化、软件响应延迟或其他因素执行到非预期位置。

   在执行涉及删除文件、发送消息、购买、支付、提交数据或其他不可逆操作之前，请务必自行确认并谨慎测试。

4. **软件按“原样”提供**

   ClickFlow 按“原样”（AS IS）提供，不保证软件始终无错误、不中断，也不保证其适用于任何特定用途。

   在法律允许的最大范围内，开发者不对因安装、使用或无法使用 ClickFlow 而产生的直接或间接损失承担责任。

5. **用户数据**

   ClickFlow 默认在本地处理鼠标宏及相关配置，不会主动上传用户的鼠标操作数据。

   用户应自行负责本地宏文件、配置以及其他相关数据的备份和安全。

6. **与 Apple 及其他第三方无关联**

   ClickFlow 是独立开发的软件，与 Apple Inc.、游戏开发商、软件厂商或其他第三方平台不存在官方隶属、授权或背书关系，除非另有明确说明。

使用本软件即视为你已经阅读、理解并接受以上免责声明。

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

- Apple 的公开 GameController API 仍不提供向其他 macOS 应用注入手柄事件的能力。当前手柄回放只对安装了 [实验性 XInput 代理](Experimental/CrossOverXInputProxy/README.md) 的 CrossOver/Wine XInput 游戏生效，并非系统级虚拟手柄；DirectInput、Raw HID、GameInput、SDL 直连或带反作弊的游戏可能绕过或拒绝它。
- 尚未实现条件触发或脚本。
- 显示器布局变化时不会自动重映射坐标。
- 触控板的滚动惯性/手势阶段不会完整保存，只回放实际水平和垂直滚动增量。
- Carbon 热键的 exclusive 注册可以发现许多系统冲突，但无法保证识别所有采用非独占监听方式的第三方快捷键。
- 系统权限必须由用户手动确认；自动化测试不能代替真实 TCC 授权后的运行验证。
- 工程尚未进行 Developer ID 签名、公证或 DMG 发布。

## 版权声明

Copyright © 2026 我是艾文喵
