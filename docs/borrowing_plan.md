# AFFiNE + Excalidraw 可借鉴点分析 + 借鉴计划（2026-08-21）

> 基于 AFFiNE blocksuite（12 模块）和 Excalidraw（16 目录）深度调研，分析尚未借鉴的功能。

## 一、已借鉴清单（24 项）

| 来源 | 已借鉴功能 |
|------|-----------|
| AFFiNE | 数据库表格/幻灯片/便签/侧边栏/质感/动画/工具栏/块编辑器/Kanban/层管理/属性面板/历史面板/导出 UI |
| Excalidraw | 无限画布/手绘/导出/转换/形状库/箭头绑定/画笔/缩放控件/导出 UI/历史面板 |
| Saber | 深色反转 |
| pdfx | PDF 导入 |

## 二、尚未借鉴的高价值功能

### 优先级 P0（核心编辑体验）

| 功能 | 来源 | 模块 | 价值 |
|------|------|------|------|
| **Lasso 选择** | Excalidraw | lasso/ | 多元素框选/套索选择——编辑器核心交互 |
| **Clipboard 操作** | Excalidraw | clipboard.ts | 复制/粘贴/剪切元素——编辑器基础能力 |
| **Grid/Snap** | Excalidraw | scene/ | 网格对齐/元素吸附——精确绘制 |
| **WYSIWYG** | Excalidraw | wysiwyg/ | 行内文本编辑——富文本块交互 |

### 优先级 P1（增强功能）

| 功能 | 来源 | 模块 | 价值 |
|------|------|------|------|
| **Charts** | Excalidraw | charts/ | 数据可视化图表——嵌入画布 |
| **i18n** | Excalidraw | locales/ | 国际化——多语言支持 |
| **Animated Trail** | Excalidraw | animatedTrail.ts | 绘制动画效果——手绘感增强 |
| **GFX 引擎** | AFFiNE | gfx/ | 图形渲染管线优化 |
| **扩展加载器** | AFFiNE | ext-loader/ | 插件架构——动态加载扩展 |

### 优先级 P2（后续迭代）

| 功能 | 来源 | 模块 | 价值 |
|------|------|------|------|
| **Measurement** | Excalidraw | — | 距离/角度测量工具 |
| **Gesture 高级手势** | Excalidraw | gesture.ts | 高级手势识别 |
| **Fragment 片段化** | AFFiNE | fragments/ | 页面片段化架构（侧边栏/标题栏独立） |
| **Inline 组件** | AFFiNE | inlines/ | 行内小部件（提及/链接/公式） |

## 三、借鉴计划（按优先级——积木式——不搞崩）

### P0-1：Lasso 选择（Excalidraw 借鉴）
- **模型**：LassoSelection（选择区域——矩形/自由曲线——纯 Dart 不可变）
- **命令**：SelectByLassoCommand（选择区域内的元素——距离判定）
- **集成**：EditorV2Toolbar 加 lasso 工具 + CanvasPainterV2 绘制选择区域
- **测试**：纯逻辑测试（选择区域判定——元素包含检测）

### P0-2：Clipboard 操作（Excalidraw 借鉴）
- **模型**：ClipboardData（剪贴板数据——元素集合——纯 Dart 不可变）
- **命令**：CopyCommand/CutCommand/PasteCommand
- **集成**：EditorV2Screen 键盘快捷键（Ctrl+C/V/X）+ 右键菜单
- **测试**：纯逻辑测试（复制/粘贴/剪切——元素不变性）

### P0-3：Grid/Snap（Excalidraw 借鉴）
- **模型**：GridConfig（网格配置——间距/吸附开关——纯 Dart 不可变）
- **逻辑**：snapToGrid（坐标吸附到网格点）+ snapToElement（元素吸附）
- **集成**：ViewportState 加网格参数 + CanvasPainterV2 绘制网格
- **测试**：纯逻辑测试（吸附计算——边界）

### P1-1：Charts（Excalidraw 借鉴）
- **模型**：ChartData（数据点/标签/类型——纯 Dart 不可变）
- **渲染**：CanvasPainterV2 绘制柱状图/折线图/饼图
- **测试**：纯逻辑测试（数据计算——渲染逻辑）

## 四、实施原则

1. **积木式**：每个功能独立 Widget/模型——不耦合——可插拔
2. **纯 Dart 优先**：域模型纯 Dart 不可变——可独立测试——NO UI
3. **不搞崩**：测试后合入——全量验证——Actions 绿色
4. **保留版权**：NOTICE 更新——注明来源

## 五、执行计划

| 阶段 | 功能 | 周期 |
|------|------|------|
| 阶段 1 | Lasso 选择 + Clipboard 操作 | 本轮 |
| 阶段 2 | Grid/Snap + Charts | 下轮 |
| 阶段 3 | i18n + Animated Trail + GFX | 后续 |
