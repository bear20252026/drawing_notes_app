# 最新版开发指南与计划（2026-08-15）

> 编制背景：中国政府特殊支持内部开发项目（绘图笔记应用 1.1.0+2）。
> 编制依据：2026 年 8 月 15 日前的行业实践与国内外开源生态调研（中英双语）：
> 500 行"硬红线"共识、Flutter 无限画布/富文本组件选型、国际大厂（Notion 系 AppFlowy、
> tldraw 系 fldraw）与手写标杆（Saber）的架构经验。
> 承接历史：前序已完成 249 项测试全绿、11 大问题修复、11 大发现落地、架构拆分优化。

---

## 一、架构现状（2026-08-15 审视结论）

### 1.1 代码规模与行数门禁

| 指标 | 状态 |
| --- | --- |
| 全量测试 | 249 项全绿（analyze 零问题） |
| 行数门禁 | sloc-guard（1000 硬上限/500 警告）+ linecheck（500/1000 双档）+ 内置回退已接入 CI |
| 原超限文件 | editor_page(5092)/drawing_controller(2385)/notebook_view_page(1211)/editor_page_overlays(1793) |

### 1.2 本轮拆分成果（单文件一功能，≤1000 行为硬红线）

| 文件 | 拆分前 | 拆分后 | 拆出的逻辑域 |
| --- | --- | --- | --- |
| editor_page.dart | 5092 | **1006** | overlays(860)/drag_ops(942)/input/editing/actions/tools/commands(210)/shortcuts(138)/persistence(79)/dialogs |
| drawing_controller.dart | 2385 | **954** | objects(901)/selection/render/history(158)/temporary |
| notebook_view_page.dart | 1211 | **453** | imports(426)/manage(354)/widgets(412) |
| editor_page_overlays.dart | 1793 | 860+942 | 拆分为构建域(overlays) + 交互/手柄/选区域(drag_ops) |

**方法论**（经语言级实验验证）：Dart part 顶层函数无法访问主类实例字段、类内 part 非法、
mixin on 递归继承不可行 → 采用**同库 extension + `_applyState`/`_applyNotify` 薄包装**转发
受保护成员，行为零变化。**不为拆而拆**：过度拆分导致跨 extension 耦合时回滚合并。

### 1.3 剩余待拆分文件（500+ 行，下一轮目标）

| 文件 | 行数 | 建议 |
| --- | --- | --- |
| home_page.dart | 871 | 拆出文档卡片/新建流程/设置面板子 Widget |
| editor_toolbar.dart | 760 | 按工具类别拆 toolbar 子组件 |
| editor_components.dart | 718 | 拆出独立组件文件 |
| editor_page_editing.dart | 742 | 拆出文字/图片编辑子域 |
| editor_page_actions.dart | 565 | 拆出菜单/导出子域 |

---

## 二、开源生态调研与借鉴评估（14 个项目全量研读）

### 2.1 绘图画布引擎（6 个）

| 项目 | 许可证 | 亮点 | 本地化适配建议 |
| --- | --- | --- | --- |
| **fldraw** | MIT | 无限画布 + BLoC 状态 + 自定义 RenderObject + 节点系统 + fldraw-lang 文本生成图表 | ✅ 借鉴"控制器 API + 撤销重做 + 键盘快捷键"组织方式；与本项目 controller 架构一致 |
| **scribe_canvas** | MIT | **O(1) 向量图片缓存**（60fps 千笔级）+ 多页 A4 + 速度压感采样 + Catmull-Rom 平滑 + 对象擦除 + PDF 导出 | ✅ **最大借鉴点**：向量 PictureRecorder 缓存（本项目已有 Expando 双质量缓存，可对照升级）；多页滚动/离散导航对照本项目分页 |
| **industrial_drawing** | MIT | 生产级矢量引擎 + 测量模式 + 渲染/UI 分离 + 形状吸附 | ✅ 借鉴"测量模式"（距离/尺寸标注）与引擎/UI 分层 |
| **flare_draw** | MIT | Catmull-Rom 贝塞尔平滑 + 速度压感 + 零依赖 + PNG 导出 | ✅ 对比压感算法（本项目 EMA+inverseLerp 可对照）；零依赖理念 |
| **zeba_academy_canvas_board** | GPL | 离线画板 + 网格吸附 + JSON 导入导出 | ⚠️ GPL 许可，**不直接引入代码**，仅借鉴 JSON 交互设计 |
| **iwb_canvas_engine** | MIT | **不可变场景模型 + SceneWriteTxn 事务写入 + 严格 JSON 校验/规范化** | ✅ **第二大借鉴点**：事务写入 API 与本项目命令栈互补；schemaVersion 版本化对照本项目 codec |

### 2.2 富文本编辑器（4 个）

| 项目 | 许可证 | 亮点 | 本地化适配建议 |
| --- | --- | --- | --- |
| **flutter_quill** | Apache-2.0 | 2.9k star 成熟 WYSIWYG，Delta 文档模型，大量验证 | ✅ 项目文字块已实现 Delta runs 思想；如需升级完整富文本可评估引入（Apache-2.0 兼容政府项目） |
| **AppFlowy Editor** | AGPL-3.0 | 块级编辑器（Notion 风格），主题/工具栏/快捷键可定制 | ⚠️ AGPL 传染性——**不直接引入**，仅借鉴块级/选择菜单交互 |
| **flutter_smart_editor** | MIT | 纯 Dart HTML 编辑器（无 WebView）+ 表格/列表/撤销重做 + Material 3 | ✅ 评估引入做 RTF/HTML 导入导出层（MIT 兼容） |
| **smart_rich_text_quill** | 未标 | Markdown 编辑 + 鉴权图片 + PDF 查看 + 零 flutter_quill 依赖 | ✅ Markdown 渲染管线可借鉴（本项目文字块为轻量 TextRun） |

### 2.3 完整应用参考（4 个）

| 项目 | 许可证 | 亮点 | 本地化适配建议 |
| --- | --- | --- | --- |
| **Saber** | GPL-3.0 | 4.7k star 手写标杆：SBN 格式/双质量缓存/WebDAV 同步/路径加密 | ✅ 已深度研究并落地大部分（BSON 压缩/同步抽象/加密）；继续对照 UI 细节 |
| **AppFlowy** | AGPL-3.0 | 75.4k star Notion 替代：前端 Flutter + 核心 Rust，AI 工作区 | ⚠️ 不引入代码；借鉴"前端 Flutter + 核心 Rust"分层与 inlang 国际化 |
| **printnotes** | GPL | Google Keep/Obsidian 风格 Markdown 笔记，跨平台 | ⚠️ 参考产品交互，不引入 GPL 代码 |
| **notemesh** | MIT | 简洁本地笔记 + 深浅色模式 | ✅ 借鉴极简信息架构（本项目功能较重，可评估简化入口） |

### 2.4 许可合规结论（政府项目红线）

- **可直接借鉴/引入**（MIT/Apache-2.0）：fldraw、scribe_canvas、industrial_drawing、flare_draw、iwb_canvas_engine、flutter_quill、flutter_smart_editor、notemesh
- **仅借鉴思想、不引入代码**（GPL/AGPL）：zeba_academy、AppFlowy Editor、AppFlowy、Saber、printnotes

---

## 三、下一步开发计划（P0-P2）

### P0（质量与架构收尾）
1. 继续拆分剩余 500+ 行文件（home_page/editor_toolbar/editor_components 等）
2. 门禁 CI 落地验证（code-guard.yml 官方 Rust 工具）
3. 行数红线写入 Code Review 硬性标准（500 行警告/1000 行阻断）

### P1（功能增强，借鉴开源）
1. **矢量缓存升级**：对照 scribe_canvas O(1) 缓存，评估将 Expando Path 缓存升级为 PictureRecorder 位图缓存（重绘性能）
2. **事务写入 API**：对照 iwb_canvas_engine SceneWriteTxn，封装批量命令事务（原子性/审计）
3. **测量模式**：借鉴 industrial_drawing 增加距离/角度标注
4. **Markdown 支持**：评估 flutter_smart_editor/smart_rich_text_quill 做文字块 Markdown 渲染

### P2（体验与协作）
5. 对照 Saber 继续打磨 UI 细节（工具栏/页签/主题自适应）
6. 评估 AppFlowy 式 AI 集成（事件流 + YAGNI 约束，本地优先）

---

## 四、质量门禁与红线（本报告起生效）

| 规则 | 阈值 |
| --- | --- |
| 新增文件硬上限 | **≤1000 行**（极限条件才可突破，需评审记录） |
| 正常文件规模 | **500 行左右**（<500 为最佳；500-1000 需警惕并找拆分机会） |
| 拆分原则 | 先找自然边界（SRP/领域/抽象层/I/O 边界），**不为拆而拆**，拆分须让逻辑更精简 |
| CI 门禁 | sloc-guard（SLOC+结构+git diff）+ linecheck（双档）+ 内置回退 |
| 测试 | 每步拆分后跑全量测试（当前 249 项基线），确保零回归 |

> 本指南基于 2026-08-15 当日代码状态与开源调研出具；国际视野（tldraw/Notion/AppFlowy/Saber
> 生态）+ 国内实践（OpenHarmony/Isar 等）均已纳入评估，后续按 P0→P2 滚动执行。
