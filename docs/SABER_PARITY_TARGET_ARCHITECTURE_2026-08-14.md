# Saber 功能等效目标架构

**架构目标：** 在保留现有 Flutter、图层、混排笔记、本地加密、命令注册和苹果式视觉系统的前提下，逐步演进为具备 Saber 等效手写、资料、导出、备份与同步能力的独立实现。  
**核心原则：** 以用户任务闭环而非页面入口为边界；每个服务独立测试；不复制 Saber GPLv3 源码或其内部数据格式。  

## 1. 当前结构与主要瓶颈

当前应用已有可用的 `DrawingController`、`StrokeRenderer`、`StylusInputProcessor`、`DocumentRepository`、`NotebookRepository`、`EditorCommandRegistry` 和本地加密存储。它的主要问题不是底层不存在，而是 `EditorPage` 已增长到约 179KB，集中承担输入、画布布局、快捷键、菜单、文件操作、对象编辑和导出；`NotebookViewPage` 也混合了工作流与界面职责。当前 `NotebookStorage` 已具备原子写入、图片副本和页面密文保护，但没有格式迁移、统一资源清单、文件变更流或同步状态模型。

| 现有模块 | 可保留的基础 | 等效能力所需演进 |
| --- | --- | --- |
| `DrawingController` | 图层、活动笔画、位图缓存、基础选择和 60 步历史 | 抽出操作日志、视图状态和笔画几何缓存；持续只负责可绘制文档状态 |
| `StrokeRenderer` | 平滑曲线、压感线宽、透明擦除、脏矩形 | 增加笔刷策略、实时/完成态路径缓存、高亮专用分层与导出能力标签 |
| `StylusInputProcessor` | 压力正规化、来源标注与 EMA 平滑 | 升级为 `EditorInputArbiter` 的一部分，统一笔/手/鼠标/双指/侧键/悬停策略 |
| `DocumentCommands` | 新笔画逆命令、低频快照命令 | 升级为操作日志、保存点、批处理、误触回滚和跨对象命令 |
| `NotebookStorage` | 原子写、图片副本、密码/密钥文件加密 | 加入版本头、迁移器、资源清单、备份归档与存储变更事件 |
| `CommandRegistry` | 分类、可用性谓词、关键词、命令面板 | 接入所有资料库、页面、导入导出和输入模式操作，消除旁路调用 |
| 玻璃主题组件 | 控制层局部玻璃、内容优先 | 保持仅用于导航/工具层，画布、PDF 和正文始终为高对比实色内容层 |

## 2. 目标分层

```text
┌──────────────────────────────────────────────────────────────┐
│ Presentation                                                  │
│ HomeWorkspace · Library · Notebook · Editor · Export dialogs │
│ Apple-style glass controls only; content surfaces stay solid  │
├──────────────────────────────────────────────────────────────┤
│ Application services                                          │
│ EditorInputArbiter · DocumentActionService · HistoryService  │
│ PageWorkflowService · LibraryService · ExportSnapshotService │
│ BackupService · SyncCoordinator · FeatureAvailability         │
├──────────────────────────────────────────────────────────────┤
│ Domain                                                        │
│ Notebook/Pages · MixedElements · Layers · Strokes · Assets    │
│ BrushPreset · InputPolicy · DocumentOperation · SyncChange    │
├──────────────────────────────────────────────────────────────┤
│ Infrastructure                                                │
│ GeometryCache · RasterLayerCache · Codec/Migration · Storage  │
│ PDF adapter · Platform input adapter · WebDAV adapter         │
├──────────────────────────────────────────────────────────────┤
│ Platform                                                      │
│ Flutter pointer events · Android channels · Windows Ink       │
│ Files/Share/Save dialogs · Key storage · Release update feed  │
└──────────────────────────────────────────────────────────────┘
```

### 2.1 `EditorInputArbiter`

此服务是 Saber 等效书写体验的首要改造。它接收原始指针事件与当前编辑策略，输出受控的 `InkStart`、`InkMove`、`InkEnd`、`PanZoom`、`Hover`、`TemporaryEraser` 或 `Ignored` 事件。其规则如下：触控笔和倒置笔优先产生墨迹；手指默认用于平移与双指缩放；鼠标只在明确画笔/选择模式下产生编辑事件；笔在接触时可忽略新增 touch 事件；从单点转为双点缩放时通过 `HistoryService` 撤销刚刚创建的意外笔画。该服务不绘制 UI，不直接保存文件。

### 2.2 `InkRenderPipeline`

渲染管线由 `BrushPolicy`、`StrokeGeometryCache`、`HighlighterCompositor` 和 `RasterLayerCache` 组成。原始 `StrokePoint` 永远是唯一真相；实时阶段以采样/简化路径预览，收笔后生成完成态几何并在必要时压缩近点。高亮笔不进入普通逐笔位图合成路径，而在页面绘制时按颜色进行局部离屏合成，以避免重叠变深。每种笔刷声明是否支持压感、是否需要光栅导出、是否可作为擦除目标。

### 2.3 `HistoryService` 与保存点

所有会改变持久化文档的行为均实现为 `DocumentOperation`，包括：增加/擦除/切分笔画、移动/复制/删除元素、增加/复制/删除/重排页面、设置背景、导入资产和文本编辑。服务维护过去/未来栈、保存点、最大内存预算和批处理边界。`NotebookStorage.save` 成功后仅标记保存点；UI 不再维护容易失真的 `isDirty` 标志。低频复杂操作可使用序列化快照，高频书写使用逆命令以控制内存。

### 2.4 版本化 `NotebookDocument` 与资源资产

现有笔记本 JSON 在根对象中增加不可变的 `formatVersion`、资源清单、文档 ID、创建应用版本和迁移历史。图片、PDF 页面渲染图、录音和缩略图作为资产资源，以内容 ID/校验摘要引用，而不是在页面对象中只存绝对路径。`DocumentMigrator` 是纯函数链；超过阈值的解析、缩略图重建、PDF 栅格化和加解密均转到 isolate/后台任务。无法识别的新版本进入只读恢复模式并允许导出原始备份。

### 2.5 `LibraryService` 与变更流

`LibraryService` 统一项目、文件夹、标签、最近访问、收藏、缩略图和搜索索引。`NotebookStorage` 的写入、移动、删除、导入和恢复后都发出 `LibraryChange`；主页、搜索页和已打开的笔记本视图订阅同一流，避免直接从页面各自刷新。初始阶段以应用数据目录为资料根；自定义目录和外部文件夹同步在后续阶段引入。

### 2.6 `ExportSnapshotService`

导出开始时冻结一个独立的 `ExportSnapshot`，预载所有资产，指定纸张主题、页面范围、目标尺寸和导出格式。它根据对象能力矩阵选择矢量、光栅或混合结果：普通矢量笔画/形状可输出为 PDF 路径；透明高亮、铅笔纹理、PDF 背景和图片保留为受控位图。导出过程不读取屏幕截图，不依赖用户当前玻璃主题或编辑器滚动位置。

### 2.7 `BackupService` 和 `SyncCoordinator`

备份在同步之前实现：版本化 ZIP、资源清单、校验值、加密信息和可恢复演练。同步协调器只消费本地变更日志，并输出显式状态：待处理、上传、下载、冲突、暂停、失败、完成。远端适配器（例如 WebDAV）与端到端加密层相互独立；账户密码、远端认证和文档密钥绝不共用。没有冲突模型与恢复演练的同步功能不得在产品界面露出。

## 3. 迁移路线与不回归策略

| 里程碑 | 新建模块 | 被逐步迁出的职责 | 允许上线的能力 | 强制质量门禁 |
| --- | --- | --- | --- | --- |
| M1：输入与书写 | `EditorInputArbiter`、`BrushPolicy`、`StrokeGeometryCache` | `EditorPage` 的 Pointer 回调与压力分支 | 压感校准、手掌拒绝、高亮笔、笔刷预设 | 单元测试 + Android/Windows 真笔 QA + 书写性能基准 |
| M2：历史与文档 | `HistoryService`、`DocumentOperation`、`DocumentMigrator` | 页面内撤销、脏状态、版本快照逻辑 | 完整撤销、保存点、误触回退、迁移读取 | 恢复一致性测试、损坏文件测试、旧版本金样 |
| M3：资料工作流 | `LibraryService`、`AssetStore`、`PageWorkflowService` | 首页/笔记本页面的存储和刷新分支 | 文件夹、缩略图、搜索、页面管理、PDF 导入 | 导入—编辑—保存—重开—删除/移动端到端测试 |
| M4：交付 | `ExportSnapshotService`、PDF adapter | UI 内导出分支 | PDF/PNG 导出、多页面、主题一致性 | 导出 PDF 可解析、图像金样、内存上限测试 |
| M5：备份同步 | `BackupService`、`SyncCoordinator`、`WebDavAdapter` | 存储旁路与未来同步占位 | 备份恢复、加密同步、冲突界面 | 断网、冲突、密钥丢失、重试和安全审查 |

## 4. 不允许的简化

第一，不能把 `infinite` 布尔标记继续宣传为无限画布；真正无限画布需要无界坐标、视口裁剪、空间索引和按视图导出。第二，不能把速度模拟称作真实压感；状态栏和测试报告必须区分来源。第三，不能让版本恢复只包含部分对象。第四，不能把 PDF “导入”实现为一张不可编辑整图，随后声称逐页批注。第五，不能让云同步覆盖冲突或把私密明文默认上传。第六，玻璃视觉不得覆盖正文、纸张、PDF 或长列表；任何用户的减少透明度/减少动效设置都必须得到尊重。

## 5. 当前实施决策

下一轮代码改造从 **M1：输入与书写** 开始，因为它最直接提升 Apple 级创作体验，复用现有 `DrawingController`/`StylusInputProcessor` 的基础最多，且不需要网络、账户或 PDF 原生插件。M1 的首批可交付项目为：触控笔/手掌仲裁、暂时侧键橡皮逻辑、低/高质量路径缓存、分层不叠色高亮笔、工具独立预设、保存点和误触撤销。每项均先有模型/渲染测试，再要求 Windows 与 Android 真机验收。
