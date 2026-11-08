# OJD 系统虚拟手柄

ClickFlow 1.0.3 的组合宏可手动选择两种手柄输出，每个宏分别保存选择：

| 方案 | 用途 | 安装位置 |
| --- | --- | --- |
| XInput 代理 | 已适配的 CrossOver/Wine Windows 游戏，实体输入与宏共享 XInput 槽位 | 游戏目录及容器配置 |
| OJD 系统虚拟手柄 | 支持该 Xbox 兼容设备的原生 Mac、PlayCover 游戏 | `~/Library/Application Support/ClickFlow/OJD/OpenJoystickDriver.app` |

在组合宏编辑器的“手柄输出”选择方案。ClickFlow 不自动切换，缺少组件或连接失败时会说明原因。旧宏默认 XInput；新组合宏文件为版本 2，1.0.2 及以上可以导入旧宏，旧版 ClickFlow 不接受版本 2 文件。

## 使用 OJD

1. 打开组合宏列表下方的“OJD 系统虚拟手柄”。
2. 点击“一键安装官方组件”。组件保存在当前用户的 ClickFlow 支持目录，路径见上表；不写入 ClickFlow.app，也不要求管理员权限。已有匹配的旧安装会先校验并复制；没有旧安装时下载官方 DMG，校验 SHA-256、版本、签名、虚拟 HID entitlement 和系统信任后安装。已有其他版本保留并显示原因。
3. 连接实体手柄，刷新并选择“实体输入来源”；也可选择“不合并实体手柄”。
4. 首次使用，在 macOS“隐私与安全”中为 OpenJoystickDriver 开启“输入监控”和“辅助功能”（部分系统称为“设备控制和数据访问”），然后重启 OJD。“输入监控”未列出它时，点列表下方 ＋，按 ⌘⇧G 并粘贴组件路径，添加 `~/Library/Application Support/ClickFlow/OJD/OpenJoystickDriver.app`。无需批准 Xbox USB 驱动。点击“连接手柄”。需要在启动时发现手柄的游戏，请先连接再打开游戏。
5. 在组合宏中选择“OJD 系统虚拟手柄”，通过播放按钮或快捷键运行。
6. 停止宏会交还实体输入；“断开手柄”移除 ClickFlow 的虚拟设备。录制新宏前会断开输出，避免回录。

宏接管当前非中性的按钮、摇杆或扳机，其余控件保留实体输入。宏暂停时实体手柄继续透传，恢复后继续宏状态。输入来源在连接前固定，连接期间新出现的设备不自动成为来源；手柄断线后不擅自替换。录制和混合都排除本应用的虚拟输出。

本机《无限暖暖》若在启动时先选中实体设备，可保持 OJD 已连接，关闭实体手柄后重新启动游戏；通过宏 A 键进入游戏，再连接实体手柄，停止宏并在 OJD 管理页断开、选定实体来源、重新连接。该顺序已验证移动、镜头与实体混合。

系统虚拟手柄可被其他正在运行的游戏接收。若游戏同时读取实体与虚拟手柄，应在游戏中选择虚拟设备；ClickFlow 不提供系统级实体设备隐藏功能。GameController 与 SDL 使用不同识别规则，具体游戏兼容性以测试记录为准。游戏或系统可能对摇杆施加额外死区；若小幅宏没有响应，可先用较大幅度确认输入，再调整游戏死区与宏数值。

## 从 1.0.2 迁移

1. 点击“一键安装官方组件”，将已校验的 `/Applications/OpenJoystickDriver.app` 复制到 ClickFlow 的支持目录，原副本暂时保留。
2. 若页面提示旧服务仍在运行，点击“退出旧组件并切换”。确认后正常退出旧 OJD，再从新路径启动。使用该服务的其他应用也会断开输入；无法正常退出时不会强杀。其他位置的服务需自行退出。
3. 点击“连接手柄”，检查权限并在游戏中确认按钮、摇杆及宏正常。需要重新授权时，使用页面的复制路径和对应系统设置按钮，针对新位置的 OpenJoystickDriver 授权。
4. 确认游戏输入正常后，勾选验收项并点击“将旧组件移到废纸篓”。清理失败时旧副本保留，可稍后重试。废纸篓中的原包可以恢复。

“在 Finder 中显示”可查看新组件；删除 ClickFlow 支持目录会同时删除组件，需要重新安装。本轮不自动升级 OJD。

## 组件与开发

固定版本：[OpenJoystickDriver 0.6.0-alpha.1](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.6.0-alpha.1)，源提交 `3552be925d7dacef3fd895ac0c6cbf39e9d3cd70`。

- 官方 DMG SHA-256：`d2b771ffe4382b7bfd218932c7003227216d334a14154e95976c4f114b1c2056`。
- bundle ID：`com.openjoystickdriver`；作者 Team：`9PQP6CDMQT`。
- 校验完整签名、`com.apple.developer.hid.virtual.device` 与系统信任；不改包、不重签、不激活 USB DriverKit 扩展。
- 命令入口位于 `~/Library/Application Support/ClickFlow/OJD/ojd`，不写全局命令目录。
- ClickFlow 为自己的 CLI 与 feed 设置官方 `OJD_RUN_REPOSITORY_CLI=1`，关闭包外命令链接向旧 `/Applications` 安装的自动转发；不修改或重签原包。服务启动前后均检查真实可执行路径。
- 使用持久 CLI：`ojd --json --no-input --no-color --timeout 2 virtual feed --as game-controller-compatible`。stdin 为完整状态 JSONL；正 Y 向下，扳机 0–1。单帧发送节奏至少 10ms，不提交长保持队列；同时间戳连续手柄事件合为一帧。
- 官方服务有心跳与断线清理；发送超时或进程退出时停止宏，重连从中性状态开始。退出仅清理本应用 feed，不停止共享 OJD 服务。

OJD 为 MIT 许可，源码中的 `ClickFlow/Resources/OJD/LICENSE.txt` 随构建复制为应用资源 `LICENSE.txt`。受限虚拟 HID 权限由 OJD 官方原包持有，不转移给 ClickFlow。
