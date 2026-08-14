# 代码质量控制与拆分工具评估报告（2026-08-15）

> 评估对象：12 个开源工具（4 约束检查 + 8 代码拆分，全部联网研读官网/GitHub/npm/lib.rs）。
> 评估基准：本项目为 **Flutter/Dart 桌面应用（1.1.0+2，中国政府开发项目）**。
> 核心要求：新增文件 ≤1000 行、正常 500 行左右、不为拆而拆、拆分须让逻辑更精简。

---

## 一、约束与检查工具（定规矩，防变坏）

### 1.1 toobig —— ❌ 不推荐（已归档）
- **状态**：作者于 2023-03-22 **归档**（read-only），停止维护。
- 能力：按 glob 设置文件/目录体积预算，超限非零退出；支持 line/table/json/junit/tap 报告器。
- **结论**：已停止维护，政府项目不宜引入。

### 1.2 linecheck —— ✅ 强烈推荐（轻量门禁）
- **Rust 核心**，语言无关（对比 cloc/tokei/scc 只统计无阈值；ESLint max-lines 仅 JS/TS）。
- 特性：按文件/glob 独立阈值、**warn/error 双档**、CI 友好退出码、`.gitignore` 式嵌套配置、`--json`/`--status` 仪表盘、内置 `--strict`(100/100)/`--default`(200/400)/`--loose`(400/400) 预设、WASM/Go 绑定。
- 许可证：MIT；约 1.5K SLoC，轻量。
- **契合**：`linecheck --default lib/` 即可做 200 行警告 / 400 行错误门禁，与 CI 无缝集成。

### 1.3 sloc-guard —— ✅✅ 首选（最完整约束）
- **Rust 高性能 CLI**，语言无关；Apache-2.0。
- 独有能力：
  - **SLOC 限制**（默认排除注释/空行）+ 目录结构规则（max_files/max_dirs/max_depth/命名/deny 扩展）
  - **Git 感知**：`--diff`/`--staged` 只查改动文件（CI 提速）
  - **基线祖父化**（baseline grandfathering）+ **趋势追踪** + SARIF 输出 + 远程配置继承
- 配置 `.sloc-guard.toml`：`max_lines = 500`、`warn_threshold = 0.8`（400 行警告）。
- **契合**：政府项目"硬约束让 AI/开发者自动收敛"——超限即 CI 失败，倒逼拆分。

### 1.4 scopewalker-mcp —— ✅ 推荐（AI 代理分析）
- **本地 MCP 服务器**（stdio、无网络调用、开源），基于 tree-sitter + tokei。
- 8 个只读工具：行数统计 / 函数检测（含超大函数定位）/ 复杂度指标（嵌套深度、参数数、圈复杂度）/ **阈值检查**（默认文件 300 行、函数 100 行）/ 代码清单 / 文档覆盖率 / 代码异味 / 依赖。
- **契合**：作为 AI 代理的只读分析层，检查超大函数、圈复杂度热点，为拆分提供依据。

---

## 二、代码拆分工具（智能拆，帮你干）

### 2.1 Refactory —— ⚠️ 部分适用（AI 混合分解）
- **JS/Python 机械化提取**（~80% 机械，LLM 只做分组规划）；其他语言走 LLM 提取。MCP/CLI。
- 指标：15 个单体 32,736 行 / 1,017 函数 / pipeline 0.89。
- **结论**：Dart 非主力语言（机械提取不覆盖），本项目暂不引入；可借鉴"AI 规划 + 确定性引擎执行"思想（本项目已用 part/extension 拆分，思路一致）。

### 2.2 viberequest —— ❌ 不适用（JS/TS 专用）
- 终端工具：split 大 PR / smell AI 异味 / dedup 重复 / inspect 声明依赖 / extract 移动符号重写 import。
- **结论**：**仅 JS/TS**，import 重写依赖符号级 import——Dart 项目不适用。

### 2.3 Coca —— ⚠️ 参考价值（Go 工具箱，非 Dart 专用）
- Go 编写，989 star / 1341 commits（活跃）；**Java 全功能**，支持调用图/概念分析/API 树/设计模式建议/坏味道/重构。
- **结论**：不直接适用于 Dart 解析；**"分析调用图+重构任务生成"的方法论值得借鉴**（对应本项目 trace_callers/blast_radius）。

### 2.4 dismantle —— ❌ 不适用（JS/TS 半自动拆分）
- 指令拆分 / 函数调用拆分 / 闭包提取 / 远程控制流 / 远程修改。MIT，45 star。
- **结论**：JS/TS 生态，Dart 不适用。

### 2.5 CodeMason（编舟）—— ⚠️ 理念参考（自主 Agent）
- 自主编码 Agent（Claude Code/Cline 同级）：事件流唯一真相、YAGNI 约束引擎（七级决策阶梯）、Staging 审查沙盒、安全分级、AI 贡献报告。
- **结论**：是 Agent 平台而非文件拆分工具；**"YAGNI 约束 + 事件审计"理念与本项目政府审计要求契合**，但引入成本高，暂不纳入。

### 2.6 codexray —— ❌ 不适用（TypeScript 专用）
- 本地代码健康分析（A-F 评级、重构计划、符号图），**TypeScript only**，2 star / 8 commits（早期）。
- **结论**：语言不匹配且早期，排除。

### 2.7 Negentropy —— ✅ 推荐（结构复杂度分析）
- **Rust**，MIT+Apache-2.0 双许可。测量软件熵（耦合、归属模糊、生命周期失配、依赖拓扑），产出**可执行重构任务**；`--fail-on` 门禁回归、基线对比。
- V2 指标：IIE/EAD/TCR/TCE/EDR/PLME/SSE+OA/VND/LDP/DIS/DMR/BFP。
- **结论**：默认后缀为 TS/JS 系，但扫描器可配置 `--extensions`；对本项目 **Dart 符号级分析可能受限**，但其"结构复杂度+重构任务"思路与本项目 Negentropy 类需求吻合，可做 CI 门禁补充。

---

## 三、选型结论（结合本项目 Flutter/Dart 政府项目）

### 3.1 推荐落地（按优先级）

| 优先级 | 工具 | 角色 | 落地方式 |
| --- | --- | --- | --- |
| P0 | **sloc-guard** | 主约束门禁 | `.sloc-guard.toml`：`max_lines=1000`（硬上限）、`warn_threshold=0.5`（500 行警告）；接入 CI，超限即失败 |
| P0 | **linecheck** | 轻量双档门禁 | `linecheck --strict lib/`（100/100）或自定义 500/1000；CI 步骤 |
| P1 | **scopewalker-mcp** | AI 代理只读分析 | 接入 AI 工作流，定位超大函数/圈复杂度热点 |
| P1 | **Negentropy** | 结构复杂度门禁 | `negentropy analyze . --extensions .dart --format json`，`--fail-on` 回归门禁 |
| P2 | Refactory/Coca/CodeMason | 方法论借鉴 | 借鉴"AI 规划+确定性执行""调用图分析""YAGNI 约束"思想，不直接引入 |

### 3.2 排除清单

| 工具 | 排除原因 |
| --- | --- |
| toobig | 已归档（2023-03）停止维护 |
| viberequest / dismantle / codexray | JS/TS 专用，Dart 不适用 |
| Refactory | 机械化提取仅 JS/Python，Dart 非主力 |

### 3.3 与本项目现状的衔接

- 本项目已用 **dart_code_metrics 5.7.6**（复杂度门禁）+ `flutter analyze` + `flutter test`（249 项）作为现有门禁；
- 拆分后当前超 500 行文件：editor_page_overlays(1793)/editor_page(1405)/drawing_controller(1102)/drawing_controller_objects(901)/home_page(871)/editor_toolbar(760)/editor_page_editing(742)/editor_components(718)/editor_page_actions(565)/notebook(513)/editor_page_input(509)；
- **落地方案**：引入 sloc-guard/linecheck 后，以上文件在 CI 中即被标记为警告（500+）或错误（1000+），倒逼后续继续拆分；editor_page_overlays(1793) 作为"不为拆而拆"评审对象，由专家组评估是否拆分。

---

## 四、结论

**最优组合**：`sloc-guard`（硬约束门禁，SLOC+目录结构+git diff）+ `linecheck`（轻量双档，快速反馈）+ `scopewalker-mcp`（AI 只读分析）+ `Negentropy`（结构复杂度门禁）。四个工具均为 Rust/语言无关/本地优先/宽松许可（MIT/Apache-2.0），完全契合中国政府项目的安全、可审计、无外部网络依赖要求。
**排除**：JS/TS 专用工具与已归档工具。

> 建议下一步：CI 接入 sloc-guard（1000 行硬上限 + 500 行警告）与 linecheck，形成"分析→约束→拆分→再分析"的质量闭环。
