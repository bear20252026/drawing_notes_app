# 富文本 / 画布升级技术选型报告（2026-08-15）

> 依据：开发指南（docs/DEVELOPMENT_GUIDE_2026-08-15.md）P1 项与第二批开源调研结论。
> 目的：为文字记录模块（富文本）与绘图画布模块（性能/功能）选定升级技术方案。
> 原则：中国政府内部项目——许可证合规（MIT/Apache 优先）、本地优先、审慎引入、不破坏 249 测试基线。

---

## 一、富文本编辑器选型

### 1.1 现状
本项目文字块为轻量实现：`PageTextItem` + `TextRun` 片段（已实现 Delta runs 思想的简化版），
支持加粗/斜体/下划线/删除线/对齐/字体族，但**无表格、列表、撤销重做、图片内嵌、Markdown**。

### 1.2 候选方案对比

| 方案 | 许可证 | 特性 | 政府项目契合 |
| --- | --- | --- | --- |
| **flutter_quill** | Apache-2.0 | 成熟 WYSIWYG、Delta 模型、2.9k star、大量验证 | ✅ 许可兼容；功能最全 |
| **flutter_smart_editor** | MIT | 纯 Dart HTML 编辑器（无 WebView）、表格/列表/撤销重做、Material 3 | ✅ 许可兼容；无 WebView 更可控 |
| **smart_rich_text_quill** | 未标 | Markdown 编辑、图片上传、PDF 查看、零 flutter_quill 依赖 | ⚠️ 许可需确认 |
| **AppFlowy Editor** | AGPL-3.0 | 块级编辑器（Notion 风格） | 🔴 AGPL 传染，不引入 |
| **自研扩展（当前）** | — | 轻量 TextRun、零依赖 | 🟢 可控但功能受限 |

### 1.3 推荐

**首选：`flutter_quill`（Apache-2.0）——渐进式引入**
- 理由：Apache-2.0 与政府项目完全兼容；Delta 模型与本项目 `TextRun` 片段天然衔接（当前 runs 可视作 Delta 的子集）；生态最成熟、中文支持好。
- 引入方式（三步渐进，不破坏基线）：
  1. 评估期：`flutter pub add flutter_quill` 后仅在新文字块启用，旧块保持 `TextRun` 渲染（向后兼容）
  2. 并存期：新增 `PageTextItem.delta` 字段承载 Quill Delta，旧 `runs` 字段保留读取
  3. 收敛期：确认稳定后统一走 Delta，`runs` 标记 deprecated

**备选：`flutter_smart_editor`（MIT）**——若政府验收明确要求"无 WebView 纯本地"，选它更可控。

### 1.4 需注意
- flutter_quill 有 WebView 依赖（链接预览/图片），内网部署需评估是否裁剪
- 引入前先做 1 周小范围试用 + 10 条人工抽检（同 OCR 评审质检思路）

---

## 二、绘图画布性能升级选型

### 2.1 现状
本项目已有：Expando 双质量 Path 缓存（stroke_renderer）、视图 LRU 缓存（view_transform_cache）、
铅笔 FragmentShader、压感正规化（EMA+inverseLerp）。测试 249 项全绿。

### 2.2 候选方案对比

| 方案 | 许可证 | 亮点 | 政府项目契合 |
| --- | --- | --- | --- |
| **scribe_canvas** | MIT | **O(1) 向量图片缓存**（60fps 千笔级）、多页 A4、速度压感采样、Catmull-Rom 平滑、对象擦除、PDF 导出 | ✅ 最大借鉴点；许可兼容 |
| **iwb_canvas_engine** | MIT | 不可变场景模型 + SceneWriteTxn 事务写入 + 严格 JSON 校验 | ✅ 事务写入与本项目命令栈互补 |
| **industrial_drawing** | MIT | 生产级矢量引擎 + 测量模式 + 渲染/UI 分离 | ✅ 测量模式可借鉴 |
| **flare_draw** | MIT | Catmull-Rom + 速度压感 + 零依赖 | ✅ 压感对比 |
| **zeba_academy_canvas_board** | GPL | 网格吸附 + JSON 交互 | 🔴 GPL 不引入 |
| **fldraw** | MIT | 无限画布 + 控制器 API + 节点系统 | ✅ 控制器组织方式 |

### 2.3 推荐

**首选方案：自研升级（借 iwb_canvas_engine 思想）+ 借鉴 scribe_canvas 缓存**
- 理由：本项目画布架构已自成体系（controller + renderer + 命令栈），**整体替换引擎风险极高**（会破坏 249 测试与既有行为）；正确路线是**局部升级**。
- 落地三步：
  1. **矢量缓存升级（P1）**：对照 scribe_canvas O(1) 思路，评估把 Expando Path 缓存升级为 `PictureRecorder` 位图缓存（千笔级重绘性能）
  2. **事务写入 API（P1）**：借鉴 iwb SceneWriteTxn，封装 `DocumentTransaction`（批量命令原子提交 + 审计留痕）
  3. **测量模式（P2）**：借鉴 industrial_drawing，增加距离/角度标注工具

**备选：不引入第三方引擎**——保持自研，仅吸收设计思想（本次调研 6 个画布项目的核心方法均已记录在开发指南）。

### 2.4 需注意
- PictureRecorder 位图缓存需处理缩放/旋转失效（现有 geometryRevision 机制可扩展）
- 事务写入需与现有命令栈（DocCommand）对齐，避免双历史栈
- 每步升级后跑全量测试 + RepoPilot diff 门禁

---

## 三、升级影响面与风险控制

| 维度 | 富文本升级 | 画布升级 |
| --- | --- | --- |
| 破坏面 | 新增依赖 + 新字段（delta） | 渲染缓存替换（高风险） |
| 兼容性 | runs → delta 双向兼容 | 旧文档无影响（缓存是运行时态） |
| 测试策略 | 新增 delta 序列化测试 | 新增缓存失效测试 |
| 回滚方案 | 依赖移除 + 字段保留读取 | 缓存开关（可切回旧 Path 缓存） |
| 验收标准 | 249 测试全绿 + 新增测试 | 249 测试全绿 + 性能基准对比 |

---

## 四、结论

1. **富文本**：首选 `flutter_quill`（Apache-2.0），三步渐进引入；备选 `flutter_smart_editor`（MIT）。
2. **画布**：不整体替换引擎；按 scribe_canvas（位图缓存）/ iwb（事务写入）/ industrial_drawing（测量）思路做**局部自研升级**。
3. **共同原则**：MIT/Apache 许可、本地优先、向后兼容、每步验证、政府验收可审计。

> 本报告供技术决策参考；正式实施前建议就 flutter_quill 依赖引入与"位图缓存替换"两项做专项评审（人审 + OCR 评审双确认）。
