# 开源项目代码匹配度分类报告（2026-08-15）

> 研读对象：14 个开源项目（6 画布引擎 + 4 富文本编辑器 + 4 完整应用）全量重新研读。
> 信源：GitHub 官方仓库、pub.dev 官方页面、项目官网/文档（中英双语核实到 2026-08-15）。
> 适用：中国政府内部开发项目（Flutter/Dart，Windows 桌面优先），249 测试基线。
> 分类标准：**完全匹配**（MIT/Apache 许可 + 语言/平台匹配 + 可本地化适配引入）、
> **一般匹配**（部分适用：许可兼容但需适配 / 平台受限 / 功能重叠）、
> **不匹配**（GPL/AGPL 传染不可引入代码 / 语言或平台不匹配）。

---

## 一、分类总览

| 分类 | 项目 | 判定依据 |
| --- | --- | --- |
| ✅ 完全匹配（3） | scribe_canvas、iwb_canvas_engine、flutter_quill | MIT/Apache + Flutter 全平台 + 可本地化适配 |
| 🟡 一般匹配（5） | flare_draw、fldraw、industrial_drawing、flutter_smart_editor、printnotes | 许可兼容但功能重叠/alpha 阶段/需较大适配 |
| 🔴 不匹配（6） | zeba_academy_canvas_board、AppFlowy Editor、smart_rich_text_quill、Saber、AppFlowy、notemesh | GPL/AGPL 传染 / 平台仅移动端 / star 过低不可用 |

---

## 二、画布引擎分类（6 个）

| 项目 | 许可 | 平台 | 成熟度 | 分类 | 依据 |
| --- | --- | --- | --- | --- | --- |
| **scribe_canvas** | MIT | Android/iOS/macOS/Windows | 0.6.3 / 3 个月前更新 | ✅ **完全匹配** | **O(1) 向量图片缓存**（60fps 千笔级）——本项目最大借鉴点；多页 A4 + PDF 导出 + 控制器 API 与本项目架构一致；Windows 支持 |
| **iwb_canvas_engine** | MIT | 全平台 | 5.0.1 / 5 个月前 | ✅ **完全匹配** | 不可变场景模型 + **SceneWriteTxn 事务写入** + 严格 JSON 校验/schemaVersion——与本项目命令栈互补；Windows 支持 |
| **flare_draw** | MIT | 全平台 | 1.0.1 / 4 个月前 | 🟡 **一般匹配** | Catmull-Rom + 速度压感 + 撤销/重做 + 零依赖；但功能简单（单层、无 PDF），与本项目现有能力重叠，仅对照压感算法 |
| **fldraw** | MIT | 全平台 | 134 star / **alpha** / 37 commits | 🟡 **一般匹配** | 无限画布 + 节点系统 + BLoC 架构理念好；但 **alpha 阶段、37 commits、成熟度低**，仅借鉴控制器/撤销组织 |
| **industrial_drawing** | MIT | 全平台 | 4 star / 11 commits | 🟡 **一般匹配** | 生产级矢量引擎 + 测量模式理念好；但 **4 star、11 commits 早期**，仅借鉴测量模式设计 |
| **zeba_academy_canvas_board** | **GPL** | 全平台 | 0.0.1 / 4 个月前 | 🔴 **不匹配** | **GPL 传染**，不可引入代码；且 0.0.1 无撤销/图层（roadmap 中），仅可参考 JSON 交互思路 |

## 三、富文本编辑器分类（4 个）

| 项目 | 许可 | 平台 | 成熟度 | 分类 | 依据 |
| --- | --- | --- | --- | --- | --- |
| **flutter_quill** | **Apache-2.0** | 全平台 | 2.9k star / 2585 commits | ✅ **完全匹配** | Delta 文档模型与本项目 TextRun 片段天然衔接；生态最成熟；Apache-2.0 政府项目兼容；分页/Word 导出 |
| **flutter_smart_editor** | MIT | 全平台 | 2.1.0 / 2 个月前 | 🟡 **一般匹配** | **纯 Dart HTML 无 WebView** + Material 3 + 列表/表格；但 HTML 文档模型与本项目 JSON/Delta 模型需适配转换层 |
| **smart_rich_text_quill** | 未明确 | **仅 Android/iOS** | 1.0.8 | 🔴 **不匹配** | **平台仅移动端**（无 Windows/macOS/Linux/web）——本项目 Windows 桌面不可用；依赖重（dio/open_filex 等） |
| **AppFlowy Editor** | **AGPL-3.0** | 全平台 | 676 star / 1310 commits | 🔴 **不匹配** | **AGPL 传染**，不可引入代码；块级编辑器理念可借鉴（选择菜单/主题） |

## 四、完整应用分类（4 个）

| 项目 | 许可 | 平台 | 成熟度 | 分类 | 依据 |
| --- | --- | --- | --- | --- | --- |
| **printnotes** | GPL | 全平台含 Windows | 159 star / 261 commits | 🟡 **一般匹配** | Google Keep/Obsidian 风格 Markdown 笔记；架构可参考（极简存储/多平台）；**GPL 不可引入代码**，仅借鉴交互与信息架构 |
| **notemesh（LiteNote）** | MIT | 全平台 | 1 star / 28 commits | 🔴 **不匹配** | **1 star、28 commits**，功能极简（仅本地笔记/深浅色），成熟度不足不可用；仅参考"数据永不上传"理念 |
| **Saber** | **GPL-3.0** | 全平台含 Windows | 4.7k star / 4216 commits | 🔴 **不匹配** | **GPL 传染**不可引入代码；但**已深度研究**并落地大量设计（SBN 压缩/双质量缓存/WebDAV 抽象/路径加密），仅借鉴思想 |
| **AppFlowy** | **AGPL-3.0** | 全平台 | 75.4k star / 7210 commits | 🔴 **不匹配** | **AGPL 传染**不可引入代码；"前端 Flutter + 核心 Rust"分层与 inlang 国际化理念可借鉴 |

---

## 五、结论与落地建议

### 可直接引入（✅ 完全匹配，3 个）
1. **scribe_canvas**（MIT）：O(1) 向量缓存——升级本项目 Expando Path 缓存为 PictureRecorder 位图缓存
2. **iwb_canvas_engine**（MIT）：SceneWriteTxn 事务写入——封装批量命令原子提交
3. **flutter_quill**（Apache-2.0）：Delta 模型——升级文字块为生产级富文本（表格/列表/撤销）

### 可适配引入（🟡 一般匹配，先评估后引入）
4. **flutter_smart_editor**（MIT）：无 WebView HTML 编辑器——若验收要求"纯本地无 WebView"选它
5. **flare_draw / fldraw / industrial_drawing**（MIT）：仅借鉴压感/无限画布/测量模式设计，不整体引入

### 不可引入（🔴 不匹配，仅借鉴思想）
6. GPL/AGPL 家族（zeba/Saber/AppFlowy/AppFlowy Editor/printnotes）：**红线，代码不可转移**
7. smart_rich_text_quill / notemesh：平台或成熟度不达标

### 政府项目审慎提示
- **许可红线**：GPL/AGPL 项目一律只借鉴设计、不引入代码（本项目为内部项目，涉及合规审计）
- **平台红线**：Windows 桌面优先，任何仅移动端依赖（smart_rich_text_quill）直接排除
- **成熟度红线**：alpha/低 star（fldraw/industrial_drawing/notemesh）先观察不引入
- **本地化适配**：完全匹配项引入前做 1 周试用 + 10 条人工抽检（与 OCR 评审质检同思路）

> 本报告基于 2026-08-15 当日官方信源（GitHub/pub.dev）核实；与 docs/DEVELOPMENT_GUIDE_2026-08-15.md、
> docs/TECH_SELECTION_RICH_TEXT_CANVAS.md 结论一致并进一步细化到代码匹配度。
