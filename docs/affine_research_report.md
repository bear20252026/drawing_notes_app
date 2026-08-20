# AFFiNE 深度研究报告（2026-08-21）

> 基于 AFFiNE（`toeverything/AFFiNE`——71.7k 星/11462 提交）+ Saber（`saber-notes/saber`——4.7k 星/4249 提交——Flutter 同框架）+ Excalidraw（130k 星）综合研究。

## 一、AFFiNE 项目概览

| 项 | 值 |
| --- | --- |
| 项目 | AFFiNE（`toeverything/AFFiNE`——71.7k 星/11462 提交——canary 分支） |
| 定位 | **all-in-one workspace**（Notion & Miro 替代品）——"Write, Draw and Plan All at Once" |
| 核心理念 | **Docs、canvas 和 tables 超融合**（hyper-merged——如 affine 一词） |
| 技术栈 | TypeScript/React（web + Electron 桌面 + React Native 移动）+ Rust（native 层）+ Blocksuite（编辑器核心） |
| 特色 | 本地优先（local-first——数据在自己磁盘）+ 实时协作 + 自托管 + 多模态 AI + 插件社区 |

## 二、架构分析（核心——可照搬模式）

```
AFFiNE 仓库结构：
├── blocksuite/          # 编辑器核心（@blocksuite——画布/块编辑器/数据库）
├── packages/            # 客户端包
│   ├── @affine/desktop  # 桌面端（Electron——完整功能）
│   ├── @affine/mobile   # 移动端（React Native——精简/适配触控）
│   └── @affine/web      # Web 端
└── tests/ tools/        # 测试与工具
```

### 核心功能模式（可照搬）

| 功能 | AFFiNE 实现 | 本地化适配（Flutter——本项目） |
| --- | --- | --- |
| **edgeless 画布**（无限画布） | 任何块可放画布（富文本/便签/网页/数据库/形状/幻灯片） | ✅ 已有（InfiniteCanvasWidget/ViewportState——Excalidraw 模式） |
| **块编辑器**（rich text block） | 一切皆块（Notion 模式） | ⏳ 可借鉴（TextItem 扩展为块——富文本） |
| **数据库/表格**（database view） | 多视图数据库（表格/Kanban/Airtable） | ⏳ 可借鉴（表格数据模型 + 多视图） |
| **幻灯片**（presentation） | 大纲→幻灯片（AI 生成） | ⏳ 可借鉴（分页 PageV2 已有——幻灯片模式） |
| **多模态 AI** | 写报告/转幻灯片/摘要思维导图/画原型 | ⏳ 后续（本地 AI 或外部 API） |
| **local-first** | 数据在自己磁盘（离线优先） | ✅ 已有（本地存储——VFS/加密） |
| **实时协作** | 跨平台实时同步 | ⏳ 后续（同步门禁——专家延后） |

## 三、桌面端 vs 移动端差异（用户指出"电脑端和手机端好像还不太一样"）

| 维度 | 桌面端（Electron） | 移动端（React Native） |
| --- | --- | --- |
| 功能 | 完整（全部功能——键盘/鼠标/多窗口） | 精简（核心功能——触控/手势） |
| 输入 | 键盘/鼠标/触控笔（精准） | 触控/手指/手写笔（粗放） |
| 画布交互 | 缩放/平移（滚轮/拖拽） | 双指缩放/拖拽（手势） |
| UI 布局 | 侧边栏/多面板（宽屏） | 底部导航/单面板（窄屏） |
| 工具栏 | 完整工具栏（图标+文字） | 精简工具栏（图标） |
| 性能 | 完整渲染（GPU） | 优化渲染（省电/触控） |

**关键洞察**：**同一内核（blocksuite）+ 双端适配层**——业务逻辑共享，UI/输入层按平台适配。这正是本项目 V2 架构（editor_core 纯 Dart + editor_v2 presentation 适配）的**印证**。

## 四、可照搬功能清单（按优先级——渐进——不搞崩）

### 高优先级（与当前批次 F 相关）

| 功能 | 来源 | 本地化方案 | 状态 |
| --- | --- | --- | --- |
| **数据库表格**（database） | AFFiNE | TableV2 数据模型 + 表格视图（纯逻辑——可测试） | ⏳ 可搬 |
| **幻灯片模式**（presentation） | AFFiNE | PageV2 已有——加全屏播放/翻页 | ⏳ 可搬 |
| **深色模式反转**（invert） | Saber | CanvasPainterV2 加反转（白墨黑底——暗光护眼——图片/PDF 也反转） | ⏳ 可搬 |
| **PDF 导入**（pdf import） | Saber/AFFiNE | pdfx 包渲染 + 多页背景（批次 F-4 方案已就绪） | ⏳ 可搬 |
| **集成测试**（CUJ-01~07） | 专家方案 | EditorV2Screen Widget 测试——不搞崩 | ⏳ 推进中 |

### 中优先级（批次 F 后）

| 功能 | 来源 | 本地化方案 |
| --- | --- | --- |
| 块编辑器（rich text） | AFFiNE | TextItem 扩展（富文本块——加粗/斜体/列表） |
| 便签（sticky note） | AFFiNE | 便签块（背景色 + 文本） |
| 多视图数据库（Kanban） | AFFiNE | TableV2 加 Kanban 视图 |
| 双密码保护 | Saber | 已有加密（NotebookSession）——可加双密码层 |

### 低优先级（后续）

| 功能 | 来源 | 说明 |
| --- | --- | --- |
| 多模态 AI | AFFiNE | 本地 AI 或外部 API（后续） |
| 实时协作 | AFFiNE | 专家方案延后（同步门禁） |
| 插件系统 | AFFiNE | 后续（V2 稳定后） |

## 五、与专家方案/现有架构的印证

1. **双端适配层**（同一内核 + 平台适配）——印证本项目 V2 架构（editor_core 纯 Dart + editor_v2 presentation 适配 + infrastructure platform adapter）
2. **local-first**——印证本项目（本地存储——VFS/加密——专家方案）
3. **渐进集成**（不搞崩）——印证本项目安全约束（测试后合入——新增层不修改现有功能）

## 六、下一步（批次 F 推进——借鉴 AFFiNE/Saber）

1. **集成测试**（CUJ-01 EditorV2Screen Widget 测试——验证无限画布/手绘/导出集成——不搞崩）
2. **PDF 导入**（批次 F-4——pdfx 渲染 + 多页背景）
3. **深色模式反转**（Saber——白墨黑底——暗光护眼）
4. **数据库表格**（AFFiNE——TableV2——纯逻辑可测试）

## 参考

- [AFFiNE](https://github.com/toeverything/AFFiNE)（71.7k 星）
- [Saber](https://github.com/saber-notes/saber)（4.7k 星——Flutter 同框架）
- [Excalidraw](https://github.com/excalidraw/excalidraw)（130k 星）
- [excalidraw-cn](https://github.com/korbinjoe/excalidraw-cn)（中文手写+多画布）
- 专家方案（批次 F——docs/batch_f_recovery_plan.md）
