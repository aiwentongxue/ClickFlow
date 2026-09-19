# CrossOver Windows 游戏手柄宏

ClickFlow 的 Windows 游戏手柄宏采用按游戏安装的 XInput 代理，而不是 macOS
系统级虚拟 HID。这样不需要 Apple 限制发放的
`com.apple.developer.hid.virtual.device` entitlement，也不会要求关闭 SIP、AMFI
或修改系统文件。

```text
实体手柄 ─┐
          ├─ ClickFlow 状态混合 ─ /private/tmp/ClickFlow.xinput
组合宏 ───┘                                      │
                                                  ▼
游戏目录 xinput*.dll ─ CrossOver/Wine ─ Windows 游戏的 XInput 槽位 0
```

## 面向普通用户的流程

1. 打开 ClickFlow 的“组合宏”，点击宏列表下方的“CrossOver 手柄宏安装、诊断与恢复”入口进入二级页面。
2. 选择游戏主程序 `.exe`。已验证游戏会自动选择适配方案与常用容器名。
3. 确认 CrossOver 容器和 CrossOver 版本，点击“开始诊断”。
4. 退出游戏后点击“一键安装”。
5. 保持 ClickFlow 运行，直接使用真实手柄，或通过快捷键播放含手柄事件的组合宏。
6. 如果游戏更新、无法启动或不再需要适配，先退出游戏，再点击“恢复安装前状态”。

安装器会备份游戏目录中原有的同名 DLL、保存容器原注册表值，并为每次安装写入
独立清单。恢复时会先校验代理文件哈希；若文件已被游戏更新或第三方工具修改，
ClickFlow 会停止恢复，避免覆盖新文件。

## 已验证方案

| 游戏 | 容器 | XInput 代理 | 额外设置 | 实机结果 |
| --- | --- | --- | --- | --- |
| Aniimo | `aniimo` / CrossOver Preview | `xinput1_3.dll` | 禁用 `windows.gaming.input` | 实体手柄、宏混合、关闭 ClickFlow 后回退均通过 |
| 原神国服 | `yuanshen` / CrossOver 25.1.1 | `xinput1_3.dll`, `xinput1_4.dll`, `xinput9_1_0.dll` | 不禁用 WGI/DirectInput/HID | 实体手柄、宏混合、关闭 ClickFlow 后回退均通过 |
| 绝区零 | `zzz` / CrossOver 26.3 | `xinput1_3.dll`, `xinput1_4.dll` | 禁用 `windows.gaming.input` | 实体手柄、宏混合、关闭 ClickFlow 后回退均通过 |

上述结论只覆盖测试时的游戏和 CrossOver 版本。更新后的游戏可能更换输入 DLL、
启用完整性校验或改变反作弊策略，因此诊断页面不会把“DLL 已安装”等同于
“游戏一定会接受输入”。

## 真实手柄与宏的行为

- ClickFlow 打开、宏停止：真实手柄持续透传到 XInput 槽位 0。
- 宏播放：宏只接管当前非中性的控件，其他按钮、摇杆和扳机继续使用真实手柄状态。
- 宏暂停、停止或释放控件：对应控件立即归还真实手柄。
- ClickFlow 未打开、崩溃或退出：状态文件超过 3 秒即失效，代理自动调用
  CrossOver/Wine 内置 XInput，让真实手柄继续工作。

## 诊断内容

界面会检查：

- 游戏是否为 x86/x64 Windows PE，以及可执行文件或相邻 `UnityPlayer.dll`
  是否出现支持的 XInput DLL 名称；
- CrossOver 容器、`user.reg`、所选 CrossOver 的 `wine` 命令是否存在；
- 应用内是否包含匹配架构的代理资源；
- 游戏进程是否仍在运行；
- ClickFlow 状态文件、心跳和连接标志是否有效；
- 已安装代理清单与 Wine DLL override 是否一致；
- 游戏目录附近是否出现常见反作弊相关文件名。

## 兼容边界和安全

- 只支持游戏实际调用的 XInput DLL。DirectInput、Raw HID、GameInput、直接 SDL
  输入或静态链接的输入实现不会自动生效。
- 该方案不会出现在 IORegistry、GameController.framework 或原生 Mac 游戏中。
- ClickFlow 不隐藏实体手柄；若游戏同时直接打开实体 HID，仍可能出现双输入。
- DLL 代理可能被联网游戏或反作弊视为进程修改。ClickFlow 不绕过反作弊；用户必须
  自行确认游戏规则。诊断发现可疑文件时会在安装前再次警告。
- “恢复”只还原 ClickFlow 记录的 DLL 和 Wine DLL override，不会回滚游戏文件、
  存档、CrossOver 容器的其他设置或用户自定义 hosts。

## 开发与来源

代理源码、导出表、探针、测试程序和可复现构建脚本位于
`Experimental/CrossOverXInputProxy/`。应用内的 x86/x64 DLL 均由这份项目源码通过
MinGW-w64 构建；它们不是微软 DLL，也不冒充微软官方硬件。整个 ClickFlow 项目按
仓库根目录的 GPL-3.0 许可证发布。
