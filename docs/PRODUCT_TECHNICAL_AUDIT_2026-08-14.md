# 绘图笔记 App：产品与代码全量审计

**审计日期：2026-08-14**  
**范围：Flutter 应用源代码、自动化测试、Android/Windows 宿主层、外部产品与平台对标**

## 审计结论

应用拥有扎实的本地绘图内核：图层、笔画、橡皮擦、撤销/重做、选区、基础压力渲染、离线存储、加密和导出已有真实代码与测试保护。问题不是“没有功能”，而是**产品能力与实现成熟度不均衡**。大量高级入口被放入了主界面，但其背后的数据模型、可靠保存、性能边界、跨平台输入与端到端任务流程尚未同步完成。

当前源码与测试合计约 **17,090 行**，其中 UI 约 **10,487 行**，`EditorPage` 单文件约 **4,600 行**。绘图控制器虽有较高的自动化覆盖，但页面级 UI、真机触控笔、Android/Windows 平台层和多步骤任务流程缺少自动化保护。因此，继续增加图标和菜单会放大体验问题；下一阶段应该把已有的高价值能力收敛为可完成、可验证的工作流。

| 审计维度 | 现状 | 结论 |
| --- | --- | --- |
| 绘图内核 | `DrawingController` 管理笔画、图层、选择、位图缓存和 60 步撤销历史；自动化覆盖约 94.9% 行 | **可作为可靠基础继续演进** |
| 笔触压力 | 模型和渲染器保存/渲染压力；编辑器只在 `0 < pressure < 1` 时直接使用原始压力，起笔固定为 1.0 | **需要正规化、起笔采样、校准和真机诊断** |
| 页面/笔记本 | 有页面、文件夹、标签、历史、克隆引用、加密 | **组织模型已具雏形，但缺收藏/排序/索引/可视化页导航** |
| 高级笔记工作流 | 可导入 Markdown/文本，支持图片与混排 | **没有 PDF 逐页批注、音频、OCR 或有效的跨内容搜索闭环** |
| 版本恢复 | `PageVersion` 仅保存 `document` 与 `textItems`，恢复逻辑也仅覆盖二者 | **P1 数据完整性缺陷：图片、形状、图表、连接线未纳入版本快照** |
| 无限画布 | `DrawingDocument.infinite` 可切换；Canvas 仍按固定 `width/height` 绘制白纸 | **声明与体验不一致，不能宣传为真正无限画布** |
| 测试 | `flutter test` 118 项通过；核心引擎覆盖高，UI 页面覆盖近乎未建立 | **必须增加模型回归、组件测试和真机测试清单** |
| Android 原生层 | `MainActivity` 是空的 `FlutterActivity` 子类 | **当前完全依赖 Flutter 默认事件链；无压力诊断、无原始笔事件或录音原生支持** |
| Windows 原生层 | 仅实现 PNG 剪贴板通道，未处理 `WM_POINTER` 笔事件 | **不保证在所有触控笔硬件上取得完整压力/历史采样** |

## 已验证的真实能力

下表列出的功能以源码路径和自动化测试为依据，可作为产品基础保留和完善。它们不是仅有入口的概念性功能。

| 功能 | 实现证据 | 可用性评估 |
| --- | --- | --- |
| 笔画绘制、压力值存储与渲染 | `Stroke`、`DrawingController.startStroke/extendStroke`、`StrokeRenderer` | 可用；压力策略需要重做 |
| 离线图层与擦除 | `LayerCompositor`、`BlendMode.clear`、脏矩形重建 | 可用；大画布需真机性能验证 |
| 撤销/重做 | 命令模式与 60 条限制，新增笔画使用逆操作 | 可用；元素级历史需统一 |
| 套索/矩形选择、复制、变换 | `Selection` 与 `DrawingController` | 可用；需要提升视觉反馈与键盘闭环 |
| 文本/图片/形状/图表混排 | `NotebookPage` 对应元素模型和编辑器操作 | 基础可用；历史/搜索/缩略图未完整覆盖 |
| 本地加密与密码盘 | `EncryptionService`、`NotebookStorage`、密码盘页面 | 已有测试；需要真实恢复演练与 UX 简化 |
| PNG/SVG/PDF/JSON/PPTX/Markdown 导出 | 编辑器导出流程 | 基础可用；需在真实文档、字体、图片和多页场景做兼容验证 |
| 纸张背景 | `PaperType` 与 `CanvasPainter` | 可用；模板不足且创建流程不可选 |

## 不应作为已完成能力宣传的项目

### 1. 真正无限画布

`infinite` 标志目前只改变状态和适配行为，文档尺寸仍是不可变的固定整数，`CanvasPainter` 始终绘制固定白色纸张矩形。因此当前形态应命名为“宽阔画布模式”或暂时隐藏，而不能宣称是 Excalidraw 式无限场景。真正实现需要可扩展坐标系、分块/瓦片渲染、元素空间索引、无边界命中测试和按视口导出策略。

### 2. 压感笔的跨设备体验

渲染器使用压力改变线宽，但编辑器在起笔时固定传入 1.0；移动时只接受 0 到 1 之间的原始值，其余情况改用速度模拟。Flutter 规定不支持压感的设备通常报告 1.0，且设备的原始范围由 `pressureMin` 与 `pressureMax` 描述。[1] [2] [3] 因此当前实现无法告诉用户“设备有没有提供真实压感”，也无法让用户校准不同笔硬件。

### 3. “全文搜索”

当前搜索只扫描笔记本标题、页面标题、文本块与独立画作标题。它不搜索标签、图片、形状文本、手写、PDF 内容、音频转录或加密内容。对用户来说应该改名为“文字搜索”，并在 P1 建立索引和结果跳转后再升级为“全局搜索”。

### 4. 版本恢复的完整性

页面版本只持久化笔画文档和文本块；恢复时也没有处理图片、形状、图表或连接线。只要用户使用这些对象，恢复一个旧版本就会得到混合状态。这是优先级高于增加任何 AI 或协作入口的数据完整性缺陷。

## P1：优先做成的高级笔记能力

P1 的标准是：不依赖用户账户或云端服务，可在离线 Windows/Android 设备上完成整个工作流，并有自动化回归测试。它们参考 Goodnotes 对 PDF 批注、模板和可检索资料的强调，以及 Notability 的组织、混排、双视图和音频-书写同步任务流。[4] [5] [6]

| P1 工作流 | 真实用户价值 | 需要的核心实现 | 验收标准 |
| --- | --- | --- | --- |
| **页面模板与新建向导** | 一次选择会议、课程、方格、康奈尔、计划页、无限白板，而不是新建后再找设置 | `PageTemplate` 数据、纸张/尺寸/边距/默认标题、模板预览 | 新建 3 步内进入正确页面；模板参数保存后重开不变 |
| **收藏、最近使用、标签与排序** | 像成熟笔记库一样找到内容，而不是只看无序网格 | 页级 `favorite/pinned`、最近打开时间、稳定排序、标签索引、筛选器 | 500 页内可按收藏/最近/标签找到目标；搜索结果能准确打开页面 |
| **可靠页面历史** | 可以放心尝试修改、恢复真实页面状态 | 版本快照覆盖全部元素；差异摘要；恢复前备份当前版本 | 恢复前后笔画、文字、图片、形状、图表、连接线数量和内容一致 |
| **PDF 导入与透明批注层** | 导入课件/合同/报告，书写和高亮后导出一份可交付文件 | PDF 选页、页面渲染、PDF 背景资源、每页标注层、导出合成 | 10 页 PDF 可导入、标注、重开、导出；原 PDF 不被破坏 |
| **压力诊断与笔刷校准** | 用户知道笔是否被识别、压力是否生效，能调整最小宽度与响应曲线 | 输入遥测面板、min/max 正规化、曲线预设、每笔元数据 | 真笔测试时压感条变化；鼠标明确显示“模拟”；导出/重开笔触一致 |
| **选择与键盘闭环** | 桌面使用时效率接近绘图工具：Esc、Delete、方向键、Ctrl/Cmd | 统一 `EditorCommand`、焦点策略、对象级选中反馈 | 每个可见工具有快捷键/菜单入口；无焦点丢失和模式残留 |

## P2：需要基础设施后再做的高级功能

P2 不应在没有数据、隐私、权限、性能与失败处理设计时上线。Goodnotes 的跨设备同步、音频/AI 工作流和 Notability 的录音转录/学习功能是成熟服务能力，不是本地单文件功能。[4] [6]

| P2 工作流 | 前置条件 | 正确实施方式 | 不应做的简化 |
| --- | --- | --- | --- |
| **录音与书写时刻同步** | Android 录音权限、Windows 音频支持、音频资产存储、播放器与时间锚点 | 每 2–5 秒/笔画开始保存时间锚点，点击笔记跳转音频，失败可恢复 | 只放麦克风图标或只存一个音频文件 |
| **手写识别/OCR 与数学转换** | 离线/云端模型选择、语言包、隐私政策、索引、纠错 UI | 先做用户手动触发的指定区域识别，保留原始墨迹和可撤销结果 | 自动上传全部私密笔记或不可编辑替换原笔迹 |
| **跨端备份与同步** | 身份、密钥管理、冲突合并、队列、网络重试与可观测性 | 本地优先变更日志 + 端到端加密资料库 + 版本冲突 UI | 覆盖式上传、只显示“已同步”而无版本/错误状态 |
| **实时协作** | 房间协议、CRDT/OT、权限、光标与存在感、冲突处理、服务端 | 先对文本/元素实现操作日志与权限模型，再增加实时编辑 | 只增加分享链接或协作按钮；Excalidraw 也将协作与编辑器库分开部署 [7] |
| **AI 问答、摘要、闪卡** | 明确的文档选择、来源定位、模型服务、成本与隐私边界 | 输出必须引用具体页面/选区，允许插入为可编辑对象 | 无来源的摘要、把私密内容默认发往外部模型 |
| **原生 Windows Ink 增强** | 真机确认 Flutter 默认链无法得到完整 pressure/tilt/history | runner 中通过 `WM_POINTER`/`GetPointerPenInfoHistory` 采样，EventChannel 传 Dart | 在未确认问题前把复杂原生采样当成必需依赖；先测试默认 Flutter 事件链 |

## 触控笔与性能：当前代码的关键改造点

### 输入层

当前事件处理将所有按下指针计入多指表，存在触控笔书写时手掌/手指落下导致捏合状态的风险。P1 应区分 `PointerDeviceKind.stylus`、`invertedStylus`、`touch` 与 `mouse`：笔负责墨迹，手指默认只负责视图平移/双指缩放，鼠标作为桌面回退输入。可选“手掌拒绝”应在笔处于接触状态时忽略新增 touch 指针，而不能简单屏蔽所有触摸。

### 压力层

起笔、移动和结束笔事件均需保留压力；将真实压力正规化为 `(pressure - pressureMin) / (pressureMax - pressureMin)`，仅在范围有意义时应用。对不支持压力的设备明确切换到稳定常宽笔或可选速度模拟，不要默默伪装为真实压感。Windows Ink 本身能提供压力、笔尖形状、大小与旋转；Win32 还提供 `GetPointerPenInfoHistory`，可在默认 Flutter 链不足时作为 P2 原生回退。[8] [9]

### 渲染层

当前 `StrokeRenderer` 用 0.5px 宽度阈值把笔画切段，能表现压力变化但可能在细笔与高采样时显得阶梯化。P1 应引入压力平滑（指数移动平均）和速度去抖，并针对单点笔画、低压起笔、快速长线与橡皮擦建立金样测试。复杂笔刷倾角、方位、书法笔和低延迟“湿墨”预览属于 P2，需要在真机帧时间达到目标后实施。

## 代码重构建议

| 模块 | 当前问题 | 重构方向 |
| --- | --- | --- |
| `EditorPage` | 约 4,600 行，混合输入、存储、导出、菜单、对象编辑和布局 | 拆为 `EditorInputController`、`EditorDocumentActions`、`EditorLayout`、`EditorExportService` 与可测试状态对象 |
| `NotebookViewPage` | 保存、历史、导入、加密、导航和 UI 混在单个 State | 抽出 `NotebookPageService`、`VersionService`、`TemplateService`；UI 只做呈现/导航 |
| `NotebookPage` | 页面元数据少；版本模型丢元素 | 增加收藏、最近打开、模板标识、可选附件；快照覆盖全部可序列化页面状态 |
| `SearchService` | 每次全量扫描，范围小，未覆盖标签 | P1 先建立内存/本地索引与结果去重，P2 迁移 SQLite FTS/OCR 索引 |
| Windows runner | 仅剪贴板通道 | 先补笔压诊断 EventChannel，必要时才引入 Win32 指针历史采样 |
| Android `MainActivity` | 没有原生扩展 | 保持轻量；只有音频、文件导入或 Flutter 输入链无法满足硬件时增加通道 |

## References

[1] [Flutter `PointerEvent.pressure`](https://api.flutter.dev/flutter/gestures/PointerEvent/pressure.html)  
[2] [Flutter `PointerEvent.pressureMin`](https://api.flutter.dev/flutter/gestures/PointerEvent/pressureMin.html)  
[3] [Flutter `PointerEvent.pressureMax`](https://api.flutter.dev/flutter/gestures/PointerEvent/pressureMax.html)  
[4] [Goodnotes: AI Information Page](https://www.goodnotes.com/for-ai-assistants)  
[5] [Goodnotes: PDF Annotation](https://www.goodnotes.com/features/pdf-annotation)  
[6] [Notability official App Store page](https://apps.apple.com/us/app/notability-ai-notes-planner/id360593530)  
[7] [Excalidraw development documentation](https://docs.excalidraw.com/docs/introduction/development)  
[8] [Microsoft: Pen interactions and Windows Ink](https://learn.microsoft.com/en-us/windows/uwp/ui-input/pen-and-stylus-interactions)  
[9] [Microsoft: Pointer Input Messages and Notifications](https://learn.microsoft.com/en-us/windows/win32/api/_inputmsg/)
