# Windows 与 Android 触控笔真机调试手册

**适用版本：本仓库优化版（2026-08-14）**  
**目标：验证真实压感、掌托行为、笔画跟手、保存恢复与跨输入回退，而不是只确认应用能启动。**

## 一、先理解本版本的输入状态

本版本已经将触控笔输入分为两类：**真实硬件压感** 与 **受控回退输入**。每次在画布中落笔后，底部状态栏会显示以下其中之一。

| 状态栏文案 | 含义 | 应如何处理 |
| --- | --- | --- |
| `触控笔压感 0–100%` | 应用收到了带有效最小/最大范围的 stylus 压力，并已正规化 | 继续做压力曲线与低延迟体验测试 |
| `鼠标速度模拟` | 当前输入没有报告可用的硬件压感，应用使用稳定回退 | 检查设备、驱动、Windows Ink 或 Flutter Windows 输入链；不要将其当成真实压感验收 |
| `固定笔宽` | 当前未能得到压力也没有可计算的速度回退 | 检查是否是单击、输入事件是否正确送达或工具是否切到橡皮擦 |

Flutter 的 `PointerEvent.pressure` 在不支持压力的设备上会返回 1.0；`pressureMin`/`pressureMax` 也用于描述可用范围。因此状态栏的来源标记比仅看笔触粗细更可靠。[1] [2] [3]

> **验收原则：只有状态栏出现“触控笔压感”且轻压/重压笔迹有稳定、可重复的差异时，才能记录为该设备的压感通过。**

## 二、Windows 真机配置

### 开发环境

请在实际 Windows 10/11 触控屏或外接数位板的电脑上执行。Flutter Windows 开发需要安装 **Visual Studio（不是 VS Code）**，并在安装器中勾选 **Desktop development with C++**；随后使用 `flutter doctor -v` 和 `flutter devices` 检查工具链与 Windows 设备。[4]

| 步骤 | 命令或操作 | 通过条件 |
| --- | --- | --- |
| 1 | 安装与项目版本相容的 Flutter SDK，并将 `flutter/bin` 加入 PATH | `flutter --version` 可运行 |
| 2 | 安装 Visual Studio 2022 的 `Desktop development with C++` 工作负载 | `flutter doctor -v` 的 Windows/Visual Studio 项无阻断错误 |
| 3 | 打开 PowerShell，进入项目目录 | 工作目录包含 `pubspec.yaml` |
| 4 | `flutter pub get` | 依赖解析成功 |
| 5 | `flutter devices` | 能看到 `windows` 目标 |
| 6 | `flutter run -d windows --debug` | 应用以 Debug 方式打开，可热重载 |

当需要排查 Windows runner 或平台通道时，先执行 `flutter build windows`，再用 Visual Studio 打开生成的 Windows runner 解决方案，设置应用项目为 Startup Project 后使用 F5 进行原生断点调试；这是 Flutter 官方文档给出的宿主调试路径。[5]

### 硬件与系统检查

优先使用带主动笔且硬件/驱动明确支持压感的设备，例如带笔的 Surface、Wacom、Huion 或 XP-Pen 数位屏。先在设备厂商的笔测试页或绘图应用中确认压力硬件本身工作，再启动本应用。若该应用始终显示“鼠标速度模拟”，即使其他应用支持压感，也应记录为 **Flutter Windows 输入链兼容性问题**，不要通过修改笔刷曲线伪装为通过。

Windows 的原生输入能力能够报告压力、笔尖形状、尺寸与旋转；Win32 还提供 `GetPointerPenInfoHistory` 读取同一帧的笔采样历史。[6] [7] 当前项目优先使用 Flutter 的默认 PointerEvent 链，以尽量保持跨平台；只有真机证据表明默认链无法取得压力或采样太稀疏时，才应在 Windows runner 中实现 `WM_POINTER` → EventChannel 的 P2 回退层。

### Windows 压感验收脚本

请在同一空白或方格页面里完成下列测试，并截取完整窗口和状态栏。每一项都应标注设备型号、笔型号、系统版本、Flutter 版本和构建号。

| 编号 | 操作 | 预期结果 | 失败判定 |
| --- | --- | --- | --- |
| W-01 | 画笔 12px，缓慢从轻到重绘制 3 条 8cm 直线 | 状态栏为触控笔压感；线宽随压力平滑变化 | 始终显示回退，或线宽只跳变不连续 |
| W-02 | 每条线起笔轻压、末尾重压 | 起笔不应总是突变到最粗；末尾没有明显锯齿 | 首点明显肥大、线宽闪烁 |
| W-03 | 快速画 20 个圆和 10 条折线 | 画布跟手，抬笔后内容不丢失 | 有断线、明显补帧、笔画延迟超过主观可接受范围 |
| W-04 | 笔尖落下书写期间，用手掌轻触屏幕边缘 | 墨迹不应被第二触点中断或意外缩放 | 发生捏合、旋转或笔画被取消；记录为掌托缺陷 |
| W-05 | 用鼠标绘制一条线 | 状态栏应明确为鼠标速度模拟/固定笔宽，不应声称为硬件压感 | 鼠标被误报为触控笔压感 |
| W-06 | 保存、关闭、重开后观察 W-01 页面 | 压力笔触外观、页面内容和历史版本一致 | 重开后线条粗细明显改变或笔画缺失 |
| W-07 | 选择笔画、移动、撤销、重做 | 选区与变换稳定，撤销不会影响无关笔画 | 选错对象、重做后丢失其他内容 |

## 三、Android 真机配置

### 连接和运行

Android 官方文档说明：在 Android 4.2 及以上版本中，先连续点击设备的 **Build number（版本号）** 七次启用开发者选项，然后在开发者选项中打开 **USB debugging**；Android 9 及以上通常位于 `设置 > 系统 > 高级 > 开发者选项 > USB 调试`。也可使用 Wireless debugging 配对。[8]

| 步骤 | 命令或操作 | 通过条件 |
| --- | --- | --- |
| 1 | 在真机开启开发者选项与 USB 调试 | 连接时允许 RSA 调试授权 |
| 2 | 使用数据线连接后执行 `adb devices` | 设备状态为 `device`，不是 `unauthorized` |
| 3 | 项目目录执行 `flutter devices` | 出现对应 Android 设备 ID |
| 4 | `flutter run -d <设备ID>` | Debug 应用安装并启动 |
| 5 | 查看实时日志可执行 `flutter logs -d <设备ID>` | 能捕获崩溃或异常信息 |
| 6 | 需要独立安装包时执行 `flutter build apk --debug` | 生成 Debug APK；发行签名另按 Android 发布流程配置 |

建议首先用 USB，而不是无线调试；压感、帧时间和日志排查期间 USB 的稳定性更高。测试结束后可关闭 USB 调试，避免长期开放设备调试入口。

### Android 系统辅助观察

Android 开发者选项提供 **Show taps**、**Pointer Location** 与 **Profile GPU Rendering**。Pointer Location 会显示交叉坐标及轨迹，可用于确认笔尖或手指的系统输入路径；Profile GPU Rendering 可帮助判断绘制过程是否出现异常渲染柱状峰值。[8]

| 观察项 | 推荐设置 | 用途 |
| --- | --- | --- |
| 输入路径 | 开启 `Pointer Location` | 判断笔、手指和掌托是否都进入系统输入；录屏时关闭以避免干扰用户界面 |
| 触摸可见性 | 可选开启 `Show taps` | 验证手指是否误触；不用于压感判定 |
| 渲染性能 | 需要时开启 `Profile GPU Rendering` | 对比慢速书写、快速涂鸦、缩放和含大量笔画页面 |
| 屏幕常亮 | 测试时可开启 `Stay awake` | 防止长时压感测试中息屏 |

### Android 压感验收脚本

Android 的验收应重复 W-01 至 W-07，并新增下面两项。若设备是普通手机且无压感笔，应验收“稳定回退”而非强求硬件压感通过。

| 编号 | 操作 | 预期结果 |
| --- | --- | --- |
| A-01 | 使用设备原装触控笔在横线模板连续书写一段文字 | 笔迹连续、压力来源可见、手掌不会意外触发缩放 |
| A-02 | 用两根手指缩放/旋转后立即继续以笔书写 | 双指动作结束后不会留下误画线，笔的坐标与笔尖位置一致 |
| A-03 | 打开含 300+ 笔画的页面，连续缩放、平移、书写和撤销 | 无崩溃、无明显内容消失；如卡顿，附录中记录 GPU 配置和录屏 |

## 四、缺陷报告必须包含的证据

高质量笔输入问题不能仅写“压感不灵”。请使用如下格式提交每个失败项。

| 字段 | 示例 |
| --- | --- |
| 设备与笔 | `Samsung Tab S9 + S Pen` / `Surface Pro + Surface Slim Pen 2` |
| 平台和版本 | `Android 15` / `Windows 11 24H2` |
| App 构建 | Git commit、Flutter 版本、Debug/Profile/Release |
| 输入来源 | 状态栏显示的完整文案，例如 `触控笔压感 37%` |
| 最短复现步骤 | “新建方格页 → 12px 画笔 → 轻压到重压直线” |
| 预期与实际 | 分别描述笔宽、延迟、掌托、坐标或保存问题 |
| 附件 | 15–30 秒原始录屏、截图、`flutter logs` 片段；不含私密笔记内容 |

## 五、通过门槛与后续决策

在至少一台 Windows 触控笔设备和一台 Android 触控笔设备上通过 W/A 测试后，才进入高级笔刷（倾角、书法笔、笔杆按钮、低延迟湿墨）的 P2 开发。如果任何具备压感的设备始终显示“鼠标速度模拟”，先保留该数据和日志；再决定是否实现 Windows `WM_POINTER` 原生通道或 Android `MotionEvent` 原生诊断。不要在没有硬件证据时引入复杂平台代码。

## References

[1] [Flutter `PointerEvent.pressure`](https://api.flutter.dev/flutter/gestures/PointerEvent/pressure.html)  
[2] [Flutter `PointerEvent.pressureMin`](https://api.flutter.dev/flutter/gestures/PointerEvent/pressureMin.html)  
[3] [Flutter `PointerEvent.pressureMax`](https://api.flutter.dev/flutter/gestures/PointerEvent/pressureMax.html)  
[4] [Flutter: Set up Windows development](https://docs.flutter.dev/platform-integration/windows/setup)  
[5] [Flutter: Building Windows apps](https://docs.flutter.dev/platform-integration/windows/building)  
[6] [Microsoft: Pen interactions and Windows Ink](https://learn.microsoft.com/en-us/windows/uwp/ui-input/pen-and-stylus-interactions)  
[7] [Microsoft: Pointer Input Messages and Notifications](https://learn.microsoft.com/en-us/windows/win32/api/_inputmsg/)  
[8] [Android Developers: Configure on-device developer options](https://developer.android.com/studio/debug/dev-options)
