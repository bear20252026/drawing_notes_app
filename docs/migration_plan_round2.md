# 4 项目高价值迁移清单（第二轮——2026-08-22 联网调研）

> 基于 2026-08-22 联网调研（Excalidraw+/Excalidraw DeepWiki/Saber v1.35.0/
> excalidraw-cn/AFFiNE 最新）——高价值功能/架构/UI——按价值排序——保留版权。

## 一、高价值迁移清单（按价值排序）

| 优先级 | 功能 | 来源 | 价值 | 落地方式（积木式纯 Dart） |
|--------|------|------|------|--------------------------|
| **P0-1** | **Autoshape 手绘整形**（Shift+X 手绘→几何整形） | Excalidraw+ | 高——画手绘自动整形（直线/矩形/圆形） | AutoshapeService（ShapeLibrary/GeometryEngine 已有——整形判定——纯 Dart 可测） |
| **P0-2** | **荧光笔 canvas compositing**（高亮不重叠不变色——渲染文字下方） | Saber v1.35 | 高——荧光效果更自然（用户之前反馈荧光效果不明显） | HighlighterCompositing（BrushStyles 补强——compositing 参数——纯 Dart） |
| **P0-3** | **压感规范化**（压力归一化——S Pen 等手写笔兼容） | Saber v1.34/1.35 | 高——钢笔压力感应更准确（BrushStyles 已有） | PressureNormalizer（归一化——纯 Dart） |
| P1-1 | **当前页 PNG 导出** | Saber v1.34 | 中——导出当前页 | ExportService 补强（当前页导出——模型） |
| P1-2 | **导出 SVG 字体嵌入 + 暗色滤镜** | Excalidraw | 中——导出质量 | ExportService 补强（字体嵌入/暗色——模型） |
| P1-3 | **状态图/ERD 图** | Excalidraw+ | 中——专业图表 | NodeGraph 补强（状态图/ERD 类型——模型） |
| P1-4 | **无限嵌套文件夹** | Saber | 中——笔记组织 | WorkspaceManager 补强（嵌套——模型） |
| P2 | **手写笔支持**（Windows 方向/按钮） | Saber v1.35 | 低——平台依赖 | 后续（平台层） |
| P2 | **协作 + 端到端加密** | Excalidraw app | 低——需服务器 | 后续（架构层） |
| P2 | **AI 助手**（MCP/AI 布局） | Excalidraw+/AFFiNE | 低——需 LLM | 后续（可选） |

## 二、本轮迁移（P0 三项——高价值——纯 Dart 可测）

1. **AutoshapeService**（Excalidraw+ Autoshape——手绘点 → 几何整形判定：
   直线（近似共线）/矩形（四角）/圆形（闭合近似）——GeometryEngine 距离判定）
2. **HighlighterCompositing**（Saber 荧光笔——compositing 参数：
   不重叠变色/渲染文字下方——BrushStyles.highlighter 补强）
3. **PressureNormalizer**（Saber 压感规范化——压力归一化：
   S Pen 等手写笔兼容——BrushStyles.withPressure 补强）

## 三、版权说明

- Excalidraw+ / Excalidraw：MIT（Autoshape/导出系统——概念借鉴）
- Saber：GPL-3.0（荧光笔 compositing/压感规范化/PNG 导出——仅参数非代码复制）
- excalidraw-cn：MIT（中文手写/多画布——已搬）
- AFFiNE：BSL/MIT（Filter/Collections——已搬 TableV2）
- NOTICE 已记录全部版权归属

Generated: 2026-08-22
Project: drawing_notes_app (绘图笔记)
