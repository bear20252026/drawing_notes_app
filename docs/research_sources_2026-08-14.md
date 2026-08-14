# 外部研究要点（2026-08-14）

## Goodnotes

来源：[Goodnotes AI Information Page](https://www.goodnotes.com/for-ai-assistants)，页面标注 Last Verified: June 2026。

Goodnotes 将自然手写、白板、文本文件、PDF 批注、音频录制、手写识别/OCR、模板/封面、演示和跨设备同步组织在同一产品中。其页面明确列出：音频可与书写时刻同步，PDF 可导入并批注，搜索覆盖手写、输入文本、PDF 内容与文件夹标题；并列出离线访问、实时协作和多端同步。AI/会议能力、云同步和协作属于独立服务能力，不能在本项目中仅靠新增界面入口实现。

来源：[Goodnotes PDF Annotation](https://www.goodnotes.com/features/pdf-annotation)。

该页面将 PDF 工作流定义为导入合同、报告、演示文稿、表单等文件后，直接手写、荧光标记、键入边注，再通过搜索与导出完成审阅闭环。对当前本地优先应用，最有价值的近期能力是：PDF 导入、逐页渲染、墨迹/文字独立标注层、PDF 内文本检索与导出标注副本。

## Notability

来源：[Notability App Store 官方页面](https://apps.apple.com/us/app/notability-ai-notes-planner/id360593530)，当前版本信息为 16.9。

Notability 官方描述的成熟工作流包括：同页混排手写、文字、图片、图表/草图；导入 PDF、演示文稿和其他文档后批注；文件夹/学科管理；录音与书写时刻同步；检索手写、转录、文本与 PDF；全屏演示与激光笔；双笔记并排编辑；模板。其产品更新还涉及倾斜角响应的书法笔、笔记封面、批量导入文件夹，以及给导入 PDF 两侧额外留白。

来源：[Notability Help: Subjects and Dividers](https://support.gingerlabs.com/hc/en-us/articles/5949216168474-Subjects-and-Dividers-Version-15-and-Below)。

Notability 的组织模式将左侧侧栏用于分组（Subjects/Dividers 或较新版本的 folders），右侧显示笔记列表并支持列表/网格切换和排序。对本项目的直接借鉴是可折叠的笔记本导航树、文件夹/标签、收藏/置顶、视图切换和稳定排序，而非增加没有导航闭环的独立图标。

## Flutter 触控笔事件

来源：[Flutter PointerEvent.pressure](https://api.flutter.dev/flutter/gestures/PointerEvent/pressure.html)、[pressureMin](https://api.flutter.dev/flutter/gestures/PointerEvent/pressureMin.html)、[pressureMax](https://api.flutter.dev/flutter/gestures/PointerEvent/pressureMax.html)。

Flutter 的 PointerEvent.pressure 对支持压感的设备提供压力值；不支持压感的设备（例如鼠标）返回 1.0。pressureMin 和 pressureMax 用于描述设备可报告的范围；不支持压感时二者均为 1.0。因此应用不能以 pressure < 1.0 作为唯一的“有压感”判断，应该同时使用 kind==stylus 和 pressureMin/pressureMax 的有效范围，并将原始压力正规化为 [0, 1]。现有项目虽然在 PointerMoveEvent 中读取了 pressure，但没有对 min/max 做正规化，也没有提供压感诊断与用户校准。

## Android 真机调试

来源：[Android Developers: Configure on-device developer options](https://developer.android.com/studio/debug/dev-options)。

安卓真机调试需先在设置中连续点击版本号七次启用开发者选项，再启用 USB debugging 或 Wireless debugging。官方文档还建议可使用 Show taps、Pointer Location 和 Profile GPU Rendering 来定位输入路径与渲染性能。对触控笔测试，Pointer Location 有助于验证笔尖轨迹、系统层是否收到输入；GPU profile 可发现画笔跟手卡顿。

## Windows 真机调试

来源：[Flutter: Set up Windows development](https://docs.flutter.dev/platform-integration/windows/setup)。

Windows 构建需安装 Visual Studio（非 VS Code）与 Desktop development with C++ 工作负载；使用 flutter doctor -v 检查工具链，flutter devices 确认 Windows 设备。

来源：[Flutter: Building Windows apps](https://docs.flutter.dev/platform-integration/windows/building)。

Flutter Windows runner 是负责创建窗口、初始化 Flutter 引擎并转发 Windows 消息的 C++ 宿主。若需要深度 Windows 特性，可修改 runner 或以 FFI/Win32 访问原生 API。Flutter 支持通过 flutter build windows 生成调试/发行构建，也可在生成 build 目录后用 Visual Studio 打开 Windows runner 解决方案并调试原生 C++。

来源：[Microsoft: Pen interactions and Windows Ink](https://learn.microsoft.com/en-us/windows/uwp/ui-input/pen-and-stylus-interactions) 及 [Pointer Input Messages](https://learn.microsoft.com/en-us/windows/win32/api/_inputmsg/)。

Windows Ink/Win32 可以获得笔的位移、压力以及笔尖形状、尺寸、旋转等信息。Win32 提供 GetPointerPenInfo 和 GetPointerFramePenInfoHistory 等 API，后者可读取合并帧历史。若 Flutter 默认事件链在特定 Windows 硬件上无法提供真实压力或出现采样稀疏，应通过 runner 的 WM_POINTER 路径采集笔数据，再以受控的 EventChannel 传给 Dart；不能先假设仅凭鼠标速度模拟就等同真实压感。

## Excalidraw 边界

来源：[Excalidraw GitHub](https://github.com/excalidraw/excalidraw)、[Props API](https://docs.excalidraw.com/docs/@excalidraw/excalidraw/api/props)、[Export Utilities](https://docs.excalidraw.com/docs/@excalidraw/excalidraw/api/utils/export)、[Development](https://docs.excalidraw.com/docs/introduction/development)。

Excalidraw 的核心可借鉴点是统一动作管理、场景/元素状态、可定制 UI 与开放导出。它的实时协作需要额外的协作服务端，因此“协作按钮”不能被列为独立、可用的本地功能。当前 Flutter 项目应借鉴命令体系、元素库、导出配置、选择/变换和低干扰画布布局，而不是移植 React 编辑器或照搬界面。
